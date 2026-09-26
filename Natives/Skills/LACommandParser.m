// LACommandParser.m — 自定义命令解析与模板展开实现（中文注释）。
#import "LACommandParser.h"

static NSString * const LACommandParserErrorDomain = @"LACommandParser";

@implementation LACommandTemplate
@end

@interface LACommandParser ()
// 自定义命令表（name → template）。
@property (nonatomic, strong) NSMutableDictionary<NSString *, LACommandTemplate *> *table;
@end

@implementation LACommandParser

// 全局单例。
+ (instancetype)sharedParser {
    static LACommandParser *sInstance = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sInstance = [[LACommandParser alloc] init];
    });
    return sInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _table = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSDictionary<NSString *, LACommandTemplate *> *)customCommands {
    @synchronized (self) {
        return [self.table copy];
    }
}

// 从 markdown 文本加载一条自定义命令。
- (nullable LACommandTemplate *)loadCustomCommandFromMarkdown:(NSString *)markdown
                                                        name:(NSString *)name
                                                  sourcePath:(nullable NSString *)sourcePath
                                                       error:(NSError **)error {
    if (name.length == 0 || markdown == nil) {
        if (error) {
            *error = [NSError errorWithDomain:LACommandParserErrorDomain
                                         code:100
                                     userInfo:@{NSLocalizedDescriptionKey: @"命令名或正文为空"}];
        }
        return nil;
    }
    NSString *frontmatter = [self frontmatterOfMarkdown:markdown];
    NSString *desc = [self frontmatterValueForKey:@"description" in:frontmatter] ?: @"";
    desc = [self stripSurroundingQuotes:
            [desc stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    NSString *agent = [self frontmatterValueForKey:@"agent" in:frontmatter];
    NSString *model = [self frontmatterValueForKey:@"model" in:frontmatter];
    NSString *subtaskRaw = [self frontmatterValueForKey:@"subtask" in:frontmatter];
    BOOL subtask = (subtaskRaw != nil &&
        ([subtaskRaw caseInsensitiveCompare:@"true"] == NSOrderedSame ||
         [subtaskRaw caseInsensitiveCompare:@"yes"] == NSOrderedSame ||
         [subtaskRaw isEqualToString:@"1"]));
    LACommandTemplate *tpl = [[LACommandTemplate alloc] init];
    tpl.name = name;
    tpl.templateDescription = desc;
    tpl.agentName = agent.length > 0 ? agent : nil;
    tpl.modelName = model.length > 0 ? model : nil;
    tpl.subtask = subtask;
    tpl.templateText = [self bodyOfMarkdown:markdown];
    tpl.sourcePath = sourcePath;
    @synchronized (self) {
        self.table[name] = tpl; // 同名覆盖（自定义覆盖内置由 commandForName 保证）。
    }
    return tpl;
}

// 按名取生效模板：自定义优先覆盖内置。
- (nullable LACommandTemplate *)commandForName:(NSString *)name
                        fallbackBuiltinTemplate:(nullable LACommandTemplate *)fallback {
    if (name.length == 0) { return fallback; }
    @synchronized (self) {
        LACommandTemplate *custom = self.table[name];
        return custom ?: fallback;
    }
}

// 展开模板：$ARGUMENTS/$1/$2 + @path 文件注入 + !shell 输出注入。
- (nullable NSString *)expandedPromptForCommand:(LACommandTemplate *)command
                                     arguments:(NSArray<NSString *> *)arguments
                                    fileReader:(nullable LAFileReader)fileReader
                                    shellRunner:(nullable LAShellRunner)shellRunner
                                          error:(NSError **)error {
    if (command == nil) {
        if (error) {
            *error = [NSError errorWithDomain:LACommandParserErrorDomain
                                         code:101
                                     userInfo:@{NSLocalizedDescriptionKey: @"命令模板为空"}];
        }
        return nil;
    }
    NSArray<NSString *> *args = arguments ?: @[];
    NSString *joined = [args componentsJoinedByString:@" "];
    NSString *out = [command.templateText stringByReplacingOccurrencesOfString:@"$ARGUMENTS"
                                                                    withString:joined];
    // $1..$9（$0 保留原文，避免误杀）。
    for (NSUInteger i = 0; i < args.count && i < 9; i++) {
        NSString *token = [NSString stringWithFormat:@"$%lu", (unsigned long)(i + 1)];
        out = [out stringByReplacingOccurrencesOfString:token withString:args[i]];
    }
    // @path 文件注入：逐行扫描行首/行内 @path token。
    out = [self injectFileRefsInText:out fileReader:fileReader];
    // !shell 输出注入：行首 ! 开头的 shell 命令。
    out = [self injectShellOutputsInText:out shellRunner:shellRunner];
    return out;
}

// 自测：test-until-green 模板展开用例。
//
// 示例模板（与 spec Scenario /test-until-green --strict 对应）：
//   description: 循环测试直到变绿
//   template: "以 --strict 跑测试：参数=[$ARGUMENTS] 首参=[$1] 次参=[$2] 文件=[@README.md] 输出=[!echo ok]"
//
// 自测用桩 fileReader 返回 "<README>"、桩 shellRunner 返回 "<ok>"，
// 断言展开后包含 "--strict"、"README" 内容与 shell 输出。
+ (BOOL)selfTestTestUntilGreenWithResult:(NSString **)result
                                   error:(NSError **)error {
    LACommandParser *parser = [[LACommandParser alloc] init];
    NSString *markdown =
        @"---\n"
        @"description: 循环测试直到变绿\n"
        @"agent: general\n"
        @"model: default\n"
        @"subtask: false\n"
        @"---\n"
        @"以 --strict 跑测试：参数=[$ARGUMENTS] 首参=[$1] 次参=[$2] "
        @"文件=[@README.md] 输出=[!echo ok]\n";
    NSError *loadError = nil;
    LACommandTemplate *tpl =
        [parser loadCustomCommandFromMarkdown:markdown
                                         name:@"test-until-green"
                                   sourcePath:nil
                                        error:&loadError];
    if (tpl == nil) {
        if (error) { *error = loadError; }
        return NO;
    }
    // 校验前 matter 解析。
    if (![tpl.templateDescription isEqualToString:@"循环测试直到变绿"] ||
        ![tpl.agentName isEqualToString:@"general"]) {
        if (error) {
            *error = [NSError errorWithDomain:LACommandParserErrorDomain
                                         code:102
                                     userInfo:@{NSLocalizedDescriptionKey: @"前 matter 解析失败"}];
        }
        return NO;
    }
    NSArray *args = @[@"--strict", @"--only=LACommandParser"];
    NSError *expandError = nil;
    NSString *expanded =
        [parser expandedPromptForCommand:tpl
                               arguments:args
                              fileReader:^NSString *(NSString *path) {
                                  return [path isEqualToString:@"README.md"] ? @"<README>" : nil;
                              }
                              shellRunner:^NSString *(NSString *cmd) {
                                  return [cmd isEqualToString:@"echo ok"] ? @"<ok>" : nil;
                              }
                                    error:&expandError];
    if (expanded == nil) {
        if (error) { *error = expandError; }
        return NO;
    }
    // 断言展开正确性。
    NSArray<NSString *> *mustContain = @[
        @"--strict --only=LACommandParser", // $ARGUMENTS
        @"首参=[--strict]",                  // $1
        @"次参=[--only=LACommandParser]",    // $2
        @"<README>",                        // @path 注入
        @"<ok>"                             // !shell 注入
    ];
    for (NSString *needle in mustContain) {
        if ([expanded rangeOfString:needle].location == NSNotFound) {
            if (error) {
                *error = [NSError errorWithDomain:LACommandParserErrorDomain
                                             code:103
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"展开缺失片段：%@\n全文：%@",
                                              needle, expanded]}];
            }
            return NO;
        }
    }
    if (result) { *result = expanded; }
    return YES;
}

#pragma mark - 内部

// @path 注入：@token（token 止于空白/括号/引号），fileReader 为 nil 时保留原文。
- (NSString *)injectFileRefsInText:(NSString *)text
                        fileReader:(nullable LAFileReader)fileReader {
    if (fileReader == NULL) { return text; }
    NSError *reError = nil;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:@"@([^\\s\"'`()\\[\\]]+)"
                                                 options:0
                                                   error:&reError];
    if (re == nil) { return text; }
    NSMutableString *out = [text mutableCopy];
    NSArray<NSTextCheckingResult *> *matches =
        [re matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    // 倒序替换避免 range 漂移；@agent 引用（纯字母短名）无法区分时一并尝试注入，
    // 失败则保留原文交由执行侧按 @agent 处理。
    for (NSTextCheckingResult *m in [matches reverseObjectEnumerator]) {
        NSRange full = [m rangeAtIndex:0];
        NSRange inner = [m rangeAtIndex:1];
        NSString *token = [text substringWithRange:inner];
        // 跳过邮箱/装饰性 @（token 含 @ 或输入为邮箱时正则已部分规避，此处再保险）。
        NSString *content = fileReader(token);
        if (content == nil) { continue; } // 保留原文。
        NSString *replacement =
            [NSString stringWithFormat:@"\n<file path=\"%@\">\n%@\n</file>",
             token, content];
        [out replaceCharactersInRange:full withString:replacement];
    }
    return [out copy];
}

// !shell 注入：行首 ! 开头的命令，用 shellRunner 输出替换为 ``` 输出块。
- (NSString *)injectShellOutputsInText:(NSString *)text
                           shellRunner:(nullable LAShellRunner)shellRunner {
    if (shellRunner == NULL) { return text; }
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSString *line in lines) {
        NSString *trimmed =
            [line stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceCharacterSet]];
        // 形如 "[!echo ok]" 包裹式也支持：提取方括号内 !命令。
        NSString *candidate = trimmed;
        if ([candidate hasPrefix:@"["] && [candidate hasSuffix:@"]"] && candidate.length >= 4) {
            candidate = [[candidate substringWithRange:
                          NSMakeRange(1, candidate.length - 2)]
                         stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]];
        }
        if ([candidate hasPrefix:@"!"] && candidate.length > 1) {
            NSString *cmd = [candidate substringFromIndex:1];
            NSString *output = shellRunner(cmd);
            if (output != nil) {
                [out addObject:[NSString stringWithFormat:
                                @"\n<shell command=\"%@\">\n%@\n</shell>", cmd, output]];
                continue;
            }
        }
        [out addObject:line];
    }
    return [out componentsJoinedByString:@"\n"];
}

// 取 markdown 顶部 --- 前言块（无则返回 nil）。
- (nullable NSString *)frontmatterOfMarkdown:(NSString *)markdown {
    if (![markdown hasPrefix:@"---"]) { return nil; }
    NSRange firstLineEnd = [markdown rangeOfString:@"\n"];
    if (firstLineEnd.location == NSNotFound) { return nil; }
    NSUInteger start = NSMaxRange(firstLineEnd);
    NSRange close = [markdown rangeOfString:@"\n---"
                                    options:0
                                      range:NSMakeRange(start, markdown.length - start)];
    if (close.location == NSNotFound) { return nil; }
    return [markdown substringWithRange:NSMakeRange(start, close.location - start)];
}

// 去前言正文（与 LASkillLoader 同规则，保持一致）。
- (NSString *)bodyOfMarkdown:(NSString *)markdown {
    NSString *frontmatter = [self frontmatterOfMarkdown:markdown];
    if (frontmatter == nil) { return markdown; }
    NSRange firstLineEnd = [markdown rangeOfString:@"\n"];
    NSUInteger start = NSMaxRange(firstLineEnd);
    NSRange close = [markdown rangeOfString:@"\n---"
                                    options:0
                                      range:NSMakeRange(start, markdown.length - start)];
    if (close.location == NSNotFound) { return markdown; }
    NSUInteger bodyStart = NSMaxRange(close);
    while (bodyStart < markdown.length &&
           [markdown characterAtIndex:bodyStart] == '\n') { bodyStart++; }
    if (bodyStart < markdown.length &&
        [markdown characterAtIndex:bodyStart] == '-') {
        NSRange nl = [markdown rangeOfString:@"\n"
                                     options:0
                                       range:NSMakeRange(bodyStart, markdown.length - bodyStart)];
        if (nl.location != NSNotFound) { bodyStart = NSMaxRange(nl); }
    }
    if (bodyStart >= markdown.length) { return @""; }
    NSString *body = [markdown substringFromIndex:bodyStart];
    return [body stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// 前言 key: value 取值。
- (nullable NSString *)frontmatterValueForKey:(NSString *)key in:(nullable NSString *)frontmatter {
    if (frontmatter == nil || key.length == 0) { return nil; }
    NSArray<NSString *> *lines = [frontmatter componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed =
            [line stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![trimmed hasPrefix:key]) { continue; }
        NSString *rest = [trimmed substringFromIndex:key.length];
        rest = [rest stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];
        if (![rest hasPrefix:@":"]) { continue; }
        rest = [rest substringFromIndex:1];
        rest = [rest stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return rest.length > 0 ? rest : nil;
    }
    return nil;
}

// 去首尾成对引号。
- (NSString *)stripSurroundingQuotes:(NSString *)text {
    if (text.length >= 2) {
        unichar first = [text characterAtIndex:0];
        unichar last = [text characterAtIndex:text.length - 1];
        if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
            return [text substringWithRange:NSMakeRange(1, text.length - 2)];
        }
    }
    return text;
}

@end
