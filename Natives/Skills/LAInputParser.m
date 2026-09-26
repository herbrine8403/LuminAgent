// LAInputParser.m — 输入语法解析实现（中文注释）。
#import "LAInputParser.h"

@implementation LAParsedInput
@end

@implementation LAInputParser

// 全局单例。
+ (instancetype)sharedParser {
    static LAInputParser *sInstance = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sInstance = [[LAInputParser alloc] init];
    });
    return sInstance;
}

// 解析输入：@path / @agent / !command / 开头 /slash / Tab 切换标记。
- (LAParsedInput *)parseInput:(nullable NSString *)text {
    LAParsedInput *out = [[LAParsedInput alloc] init];
    out.originalText = text ?: @"";
    NSString *src = text ?: @"";
    // Tab 切换：含 <TAB> 标记或 \t 前缀视作切换主 Agent 请求。
    //（UI 层将 Tab 键翻译为该标记后送入解析器。）
    if ([src rangeOfString:@"<TAB>"].location != NSNotFound ||
        [src hasPrefix:@"\t"]) {
        out.wantsTabSwitch = YES;
        src = [[src stringByReplacingOccurrencesOfString:@"<TAB>" withString:@""]
               stringByTrimmingCharactersInSet:
               [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    } else {
        out.wantsTabSwitch = NO;
    }
    // 开头 /slash 命令。
    NSString *trimmed =
        [src stringByTrimmingCharactersInSet:
         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *slash = nil;
    NSArray<NSString *> *slashArgs = @[];
    if ([trimmed hasPrefix:@"/"]) {
        NSArray<NSString *> *parts = [self splitArgs:trimmed];
        if (parts.count > 0) {
            NSString *first = parts[0];
            slash = [first hasPrefix:@"/"] ? [first substringFromIndex:1] : first;
            if (parts.count > 1) {
                slashArgs = [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)];
            }
        }
    }
    out.slashCommand = slash.length > 0 ? slash : nil;
    out.slashArgs = slashArgs;
    // @path / @agent 引用。
    NSArray<NSString *> *atTokens = [self atTokensInText:src];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSMutableArray<NSString *> *agents = [NSMutableArray array];
    for (NSString *token in atTokens) {
        // 启发式：含路径分隔符或点号 → 文件引用；否则视作 agent 名。
        if ([token rangeOfString:@"/"].location != NSNotFound ||
            [token rangeOfString:@"."].location != NSNotFound) {
            [files addObject:token];
        } else {
            [agents addObject:token];
        }
    }
    out.fileRefs = [files copy];
    out.agentRefs = [agents copy];
    // !command：行首 ! 开头的 shell 附加命令。
    out.shellCommands = [self shellCommandsInText:src];
    // plainText：去掉 @token 与行首 !行，压缩多余空白。
    out.plainText = [self plainTextFromText:src];
    return out;
}

#pragma mark - 内部

// 按空白切分（支持双引号包裹，返回去引号 token）。
- (NSArray<NSString *> *)splitArgs:(NSString *)text {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL inQuotes = NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '"') { inQuotes = !inQuotes; continue; }
        if (!inQuotes &&
            [[NSCharacterSet whitespaceAndNewlineCharacterSet]
             characterIsMember:c]) {
            if (current.length > 0) {
                [out addObject:[current copy]];
                [current setString:@""];
            }
            continue;
        }
        [current appendFormat:@"%C", c];
    }
    if (current.length > 0) { [out addObject:[current copy]]; }
    return [out copy];
}

// 提取全部 @token（止于空白/括号/引号/方括号）。
- (NSArray<NSString *> *)atTokensInText:(NSString *)text {
    NSError *reError = nil;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:@"@([^\\s\"'`()\\[\\]]+)"
                                                 options:0
                                                   error:&reError];
    if (re == nil) { return @[]; }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSArray<NSTextCheckingResult *> *matches =
        [re matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *m in matches) {
        NSString *token = [text substringWithRange:[m rangeAtIndex:1]];
        // 去掉行尾标点污染。
        while (token.length > 0 &&
                [@",;:!?" rangeOfString:
                 [token substringFromIndex:token.length - 1]].location != NSNotFound) {
            token = [token substringToIndex:token.length - 1];
        }
        if (token.length > 0) { [out addObject:token]; }
    }
    return [out copy];
}

// 提取行首 ! 开头的 shell 命令（含 [...] 包裹式）。
- (NSArray<NSString *> *)shellCommandsInText:(NSString *)text {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed =
            [line stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceCharacterSet]];
        NSString *candidate = trimmed;
        if ([candidate hasPrefix:@"["] && [candidate hasSuffix:@"]"] && candidate.length >= 4) {
            candidate = [[candidate substringWithRange:
                          NSMakeRange(1, candidate.length - 2)]
                         stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]];
        }
        if ([candidate hasPrefix:@"!"] && candidate.length > 1) {
            [out addObject:[candidate substringFromIndex:1]];
            continue;
        }
        // 行内 "[!cmd]" 包裹式。
        NSError *reError = nil;
        NSRegularExpression *re =
            [NSRegularExpression regularExpressionWithPattern:@"\\[!([^\\]]+)\\]"
                                                     options:0
                                                       error:&reError];
        if (re != nil) {
            NSArray<NSTextCheckingResult *> *matches =
                [re matchesInString:line options:0 range:NSMakeRange(0, line.length)];
            for (NSTextCheckingResult *m in matches) {
                [out addObject:[line substringWithRange:[m rangeAtIndex:1]]];
            }
        }
    }
    return [out copy];
}

// 去标记正文：移除 @token 与行首 !行，压缩空行。
- (NSString *)plainTextFromText:(NSString *)text {
    NSError *reError = nil;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:@"@([^\\s\"'`()\\[\\]]+)"
                                                 options:0
                                                   error:&reError];
    NSString *noAt = text;
    if (re != nil) {
        noAt = [re stringByReplacingMatchesInString:text
                                            options:0
                                              range:NSMakeRange(0, text.length)
                                       withTemplate:@""];
    }
    NSArray<NSString *> *lines = [noAt componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *kept = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSString *line in lines) {
        NSString *trimmed =
            [line stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"!"]) { continue; } // shell 行不入正文。
        [kept addObject:line];
    }
    NSString *joined = [kept componentsJoinedByString:@"\n"];
    // 压缩 3+ 连续换行为 2 个。
    while ([joined rangeOfString:@"\n\n\n"].location != NSNotFound) {
        joined = [joined stringByReplacingOccurrencesOfString:@"\n\n\n" withString:@"\n\n"];
    }
    return [joined stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
