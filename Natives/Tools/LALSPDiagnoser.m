#import "LALSPDiagnoser.h"

// 错误域定义。
NSString * const LALSPErrorDomain = @"org.luminagent.lsp";

@implementation LASymbol
@end

@implementation LADiagnostic
@end

@implementation LALSPDiagnoser

#pragma mark - 工具函数

// 按行切分并同步返回行数组。
- (NSArray<NSString *> *)linesOfFile:(NSString *)path error:(NSError **)error {
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!content) { return nil; }
    return [content componentsSeparatedByString:@"\n"];
}

// 去字符串字面量与行注释，保留代码骨架用于括号配平（避免 @"{" 误报）。
- (NSString *)stripLiteralsAndLineComment:(NSString *)line inBlockComment:(BOOL *)inBlock {
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0;
    BOOL inStr = NO;
    while (i < line.length) {
        unichar c = [line characterAtIndex:i];
        unichar next = (i + 1 < line.length) ? [line characterAtIndex:i + 1] : 0;
        if (*inBlock) {
            if (c == '*' && next == '/') { *inBlock = NO; i += 2; continue; }
            i++; continue;
        }
        if (!inStr && c == '/' && next == '*') { *inBlock = YES; i += 2; continue; }
        if (!inStr && c == '/' && next == '/') { break; } // 行注释开始
        if (c == '"' && (i == 0 || [line characterAtIndex:i - 1] != '\\')) { inStr = !inStr; i++; continue; }
        if (inStr) { i++; continue; }
        if (c == '\'') { // 字符字面量 'x' 跳过
            i++;
            if (i < line.length && [line characterAtIndex:i] == '\\') { i += 2; }
            else { i++; }
            if (i < line.length && [line characterAtIndex:i] == '\'') { i++; }
            continue;
        }
        [out appendFormat:@"%C", c];
        i++;
    }
    return [out copy];
}

- (LADiagnostic *)diag:(NSString *)path line:(NSInteger)line col:(NSInteger)col sev:(LADiagnosticSeverity)sev msg:(NSString *)msg rule:(NSString *)rule {
    LADiagnostic *d = [[LADiagnostic alloc] init];
    d.filePath = path;
    d.line = line;
    d.column = col;
    d.severity = sev;
    d.message = msg;
    d.rule = rule;
    return d;
}

#pragma mark - 符号表（正则轻量版）

- (NSArray<LASymbol *> *)symbolsInFileAtPath:(NSString *)path error:(NSError **)error {
    NSArray<NSString *> *lines = [self linesOfFile:path error:error];
    if (!lines) { return nil; }
    // 规则：@interface/@implementation/@protocol/ObjC 方法/C 函数/#import/#define。
    NSRegularExpression *reIf = [NSRegularExpression regularExpressionWithPattern:@"^\\s*@interface\\s+(\\w+)" options:0 error:nil];
    NSRegularExpression *reImpl = [NSRegularExpression regularExpressionWithPattern:@"^\\s*@implementation\\s+(\\w+)" options:0 error:nil];
    NSRegularExpression *reProto = [NSRegularExpression regularExpressionWithPattern:@"^\\s*@protocol\\s+(\\w+)" options:0 error:nil];
    NSRegularExpression *reMethod = [NSRegularExpression regularExpressionWithPattern:@"^\\s*[-+]\\s*\\([^)]*\\)\\s*([\\w:]+)" options:0 error:nil];
    NSRegularExpression *reCFunc = [NSRegularExpression regularExpressionWithPattern:@"^\\s*[\\w\\*\\s]+?\\s+(\\w+)\\s*\\([^;]*\\)\\s*\\{?\\s*$" options:0 error:nil];
    NSRegularExpression *reImp = [NSRegularExpression regularExpressionWithPattern:@"^\\s*#\\s*(import|include)\\s+[\"<]([^\">]+)[\">]" options:0 error:nil];
    NSRegularExpression *reDef = [NSRegularExpression regularExpressionWithPattern:@"^\\s*#\\s*define\\s+(\\w+)" options:0 error:nil];
    NSMutableArray<LASymbol *> *out = [NSMutableArray array];
    NSInteger lineNo = 0;
    for (NSString *line in lines) {
        lineNo++;
        NSArray *rules = @[
            @{@"re": reIf, @"kind": @(LASymbolKindObjCInterface), @"idx": @1},
            @{@"re": reImpl, @"kind": @(LASymbolKindObjCImplementation), @"idx": @1},
            @{@"re": reProto, @"kind": @(LASymbolKindObjCProtocol), @"idx": @1},
            @{@"re": reMethod, @"kind": @(LASymbolKindObjCMethod), @"idx": @1},
            @{@"re": reImp, @"kind": @(LASymbolKindImport), @"idx": @2},
            @{@"re": reDef, @"kind": @(LASymbolKindDefine), @"idx": @1},
        ];
        BOOL matched = NO;
        for (NSDictionary *r in rules) {
            NSTextCheckingResult *m = [(NSRegularExpression *)r[@"re"] firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
            if (m && m.numberOfRanges > [(NSNumber *)r[@"idx"] integerValue]) {
                LASymbol *s = [[LASymbol alloc] init];
                s.name = [line substringWithRange:[m rangeAtIndex:[(NSNumber *)r[@"idx"] integerValue]]];
                s.kind = [(NSNumber *)r[@"kind"] integerValue];
                s.filePath = path;
                s.line = lineNo;
                [out addObject:s];
                matched = YES;
                break;
            }
        }
        if (matched) { continue; }
        // C 函数：排除 @ 开头行与控制关键字。
        NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trim hasPrefix:@"@"] || [trim hasPrefix:@"#"] || trim.length == 0) { continue; }
        if ([trim hasPrefix:@"if"] || [trim hasPrefix:@"for"] || [trim hasPrefix:@"while"] || [trim hasPrefix:@"switch"] || [trim hasPrefix:@"return"]) { continue; }
        NSTextCheckingResult *m = [reCFunc firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        // 仅当行含 { 或下一行以 { 开头时才算定义（避免声明误收）；此处保守要求本行含 {。
        if (m && [line rangeOfString:@"{"].location != NSNotFound) {
            LASymbol *s = [[LASymbol alloc] init];
            s.name = [line substringWithRange:[m rangeAtIndex:1]];
            s.kind = LASymbolKindCFunction;
            s.filePath = path;
            s.line = lineNo;
            [out addObject:s];
        }
    }
    return [out copy];
}

#pragma mark - 诊断（clang -fsyntax-only 子集思想 + 正则）

- (NSArray<LADiagnostic *> *)diagnoseFileAtPath:(NSString *)path error:(NSError **)error {
    NSArray<NSString *> *lines = [self linesOfFile:path error:error];
    if (!lines) { return nil; }
    NSMutableArray<LADiagnostic *> *diags = [NSMutableArray array];
    // 1）括号配平：{} () [] 跨行栈检查。
    NSMutableArray *stack = [NSMutableArray array]; // @{ch, line, col}
    NSDictionary *pairs = @{@"}": @"{", @")": @"(", @"]": @"["};
    BOOL inBlock = NO;
    NSInteger lineNo = 0;
    for (NSString *line in lines) {
        lineNo++;
        NSString *code = [self stripLiteralsAndLineComment:line inBlock:&inBlock];
        for (NSUInteger i = 0; i < code.length; i++) {
            unichar c = [code characterAtIndex:i];
            NSString *ch = [NSString stringWithFormat:@"%C", c];
            if ([ch isEqualToString:@"{"] || [ch isEqualToString:@"("] || [ch isEqualToString:@"["]) {
                [stack addObject:@{@"ch": ch, @"line": @(lineNo), @"col": @(i + 1)}];
            } else if (pairs[ch]) {
                NSDictionary *top = [stack lastObject];
                if (top && [top[@"ch"] isEqualToString:pairs[ch]]) {
                    [stack removeLastObject];
                } else {
                    [diags addObject:[self diag:path line:lineNo col:(NSInteger)i + 1 sev:LADiagnosticSeverityError msg:[NSString stringWithFormat:@"括号不匹配：多余的“%@”。", ch] rule:@"bracket-balance"]];
                    // 不弹栈，避免连锁误报
                }
            }
        }
        // 2）@interface/@implementation 缺 @end（行级启发：计数）。
        // 3）#import 目标文件不存在 → warning（相对当前目录解析）。
        NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSRegularExpression *reImpFile = [NSRegularExpression regularExpressionWithPattern:@"^#\\s*import\\s+\"([^\"]+)\"" options:0 error:nil];
        NSTextCheckingResult *im = [reImpFile firstMatchInString:trim options:0 range:NSMakeRange(0, trim.length)];
        if (im) {
            NSString *target = [trim substringWithRange:[im rangeAtIndex:1]];
            NSString *base = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:target];
            if (![[NSFileManager defaultManager] fileExistsAtPath:base]) {
                [diags addObject:[self diag:path line:lineNo col:1 sev:LADiagnosticSeverityWarning msg:[NSString stringWithFormat:@"引入文件“%@”不存在（相对当前目录解析）。", target] rule:@"import-exists"]];
            }
        }
    }
    // 未闭合的开括号 → error，定位到开括号处。
    for (NSDictionary *left in stack) {
        [diags addObject:[self diag:path line:[left[@"line"] integerValue] col:[left[@"col"] integerValue] sev:LADiagnosticSeverityError msg:[NSString stringWithFormat:@"括号未闭合：“%@”缺少配对。", left[@"ch"]] rule:@"bracket-balance"]];
    }
    // 4）@interface/@implementation/@protocol 与 @end 配平。
    {
        NSInteger depth = 0;
        NSInteger lno = 0;
        for (NSString *line in lines) {
            lno++;
            NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trim hasPrefix:@"@interface"] || [trim hasPrefix:@"@implementation"] || [trim hasPrefix:@"@protocol"]) { depth++; }
            else if ([trim hasPrefix:@"@end"]) {
                if (depth > 0) { depth--; }
                else { [diags addObject:[self diag:path line:lno col:1 sev:LADiagnosticSeverityWarning msg:@"多余的 @end（无配对的 @interface/@implementation/@protocol）。" rule:@"objc-end-balance"]]; }
            }
        }
        if (depth > 0) {
            [diags addObject:[self diag:path line:(NSInteger)lines.count col:1 sev:LADiagnosticSeverityError msg:@"缺少 @end（@interface/@implementation/@protocol 未闭合）。" rule:@"objc-end-balance"]];
        }
    }
    // 5）重复符号（同文件同名同类）→ warning。
    {
        NSError *sErr = nil;
        NSArray<LASymbol *> *syms = [self symbolsInFileAtPath:path error:&sErr];
        NSMutableDictionary<NSString *, LASymbol *> *seen = [NSMutableDictionary dictionary];
        for (LASymbol *s in syms ?: @[]) {
            if (s.kind == LASymbolKindImport) { continue; }
            NSString *key = [NSString stringWithFormat:@"%ld:%@", (long)s.kind, s.name];
            if (seen[key]) {
                [diags addObject:[self diag:path line:s.line col:1 sev:LADiagnosticSeverityWarning msg:[NSString stringWithFormat:@"重复定义“%@”（首次见于第 %ld 行）。", s.name, (long)seen[key].line] rule:@"duplicate-symbol"]];
            } else { seen[key] = s; }
        }
    }
    // 按行列排序，便于行内展示。
    [diags sortUsingComparator:^NSComparisonResult(LADiagnostic *a, LADiagnostic *b) {
        if (a.line != b.line) { return a.line < b.line ? NSOrderedAscending : NSOrderedDescending; }
        if (a.column != b.column) { return a.column < b.column ? NSOrderedAscending : NSOrderedDescending; }
        return NSOrderedSame;
    }];
    return [diags copy];
}

- (nullable NSArray<LADiagnostic *> *)refreshAfterEditAtPath:(NSString *)path elapsedMilliseconds:(NSTimeInterval * _Nullable)elapsedMs error:(NSError **)error {
    // 无常驻 server：每次全量重算；计时供 UI 验证“2s 内刷新”。
    NSDate *start = [NSDate date];
    NSArray<LADiagnostic *> *r = [self diagnoseFileAtPath:path error:error];
    if (elapsedMs) { *elapsedMs = [[NSDate date] timeIntervalSinceDate:start] * 1000.0; }
    return r;
}

@end
