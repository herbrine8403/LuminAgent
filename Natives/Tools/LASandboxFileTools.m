#import "LASandboxFileTools.h"
#include <fnmatch.h> // fnmatch(3)：glob 与 .gitignore 匹配语义

// 错误域定义。
NSString * const LAFileToolsErrorDomain = @"org.luminagent.filetools";

// 单行最大读取保护：超长行截断，避免大文件卡死（对应 spec“不卡死”）。
static const NSUInteger kLAMaxPreviewLength = 512;
// 文本嗅探字节数：含 NUL 字节即判二进制。
static const NSUInteger kLASniffLength = 8000;

@implementation LAGrepMatch
@end

@implementation LAPermissionRequest
+ (instancetype)requestWithTool:(NSString *)tool target:(NSString *)target reason:(NSString *)reason {
    LAPermissionRequest *r = [[self alloc] init];
    r.toolName = tool ?: @"";
    r.targetPath = target ?: @"";
    r.reason = reason ?: @"";
    return r;
}
@end

@interface LASandboxFileTools ()
// .gitignore 规则缓存：相对 pattern 行。
@property (nonatomic, copy) NSArray<NSString *> *gitignorePatterns;
@property (nonatomic, copy, nullable) NSString *gitignoreLoadedForRoot;
@end

@implementation LASandboxFileTools

#pragma mark - 沙盒根与授权判定

// 沙盒根：Documents 与 Documents/Projects。
+ (NSArray<NSString *> *)sandboxRoots {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (!docs) { return @[]; }
    return @[docs, [docs stringByAppendingPathComponent:@"Projects"]];
}

// 路径标准化：去 ~ / .. / 符号链接前缀（不触碰文件系统，仅字符串规范化）。
- (NSString *)standardizedPath:(NSString *)path {
    if (!path) { return @""; }
    NSString *p = [path stringByExpandingTildeInPath];
    if (![p isAbsolutePath]) {
        // 相对路径一律视为相对 Documents/Projects。
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *base = docs ? [docs stringByAppendingPathComponent:@"Projects"] : NSTemporaryDirectory();
        p = [base stringByAppendingPathComponent:p];
    }
    return [p stringByStandardizingPath];
}

// 是否落在沙盒或已授权外部目录内。
- (BOOL)isPathInsideAllowedScope:(NSString *)stdPath {
    for (NSString *root in [[self class] sandboxRoots]) {
        NSString *s = [root stringByStandardizingPath];
        if ([stdPath isEqualToString:s] || [stdPath hasPrefix:[s stringByAppendingString:@"/"]]) { return YES; }
    }
    for (NSString *dir in self.authorizedExternalDirectories ?: [NSSet set]) {
        NSString *s = [dir stringByStandardizingPath];
        if ([stdPath isEqualToString:s] || [stdPath hasPrefix:[s stringByAppendingString:@"/"]]) { return YES; }
    }
    return NO;
}

// 越界门禁：范围内直接 YES；越界走 ask 回调，通过则 YES，否则写 error 返回 NO。
- (BOOL)gatePath:(NSString *)stdPath tool:(NSString *)tool error:(NSError **)error {
    if ([self isPathInsideAllowedScope:stdPath]) { return YES; }
    LAPermissionDecision decision = LAPermissionDecisionDeny;
    if (self.permissionCenter) {
        LAPermissionRequest *req = [LAPermissionRequest requestWithTool:tool
                                                                target:stdPath
                                                                reason:@"目标超出 App 沙盒与已授权目录，需经权限卡确认（spec：external_directory 越界 SHALL 触发 ask）。"];
        decision = [self.permissionCenter askPermission:req];
    }
    if (decision != LAPermissionDecisionAllow) {
        if (error) {
            BOOL asked = (self.permissionCenter != nil);
            *error = [NSError errorWithDomain:LAFileToolsErrorDomain
                                         code:(asked ? LAFileToolsErrorPermissionDenied : LAFileToolsErrorOutsideSandbox)
                                     userInfo:@{NSLocalizedDescriptionKey: @"路径越界：未获 picker/权限卡授权，已拒绝访问。"}];
        }
        return NO;
    }
    return YES;
}

#pragma mark - .gitignore 语义（轻量子集）

// 加载项目根 .gitignore：支持 # 注释、! 取反忽略（本实现取反仅用于不过滤）、目录前缀与 fnmatch。
- (void)reloadGitignoreIfNeeded {
    NSString *root = self.projectRoot;
    if (!root) { self.gitignorePatterns = @[]; return; }
    if ([root isEqualToString:self.gitignoreLoadedForRoot]) { return; }
    self.gitignoreLoadedForRoot = [root copy];
    NSString *ignoreFile = [root stringByAppendingPathComponent:@".gitignore"];
    NSString *content = [NSString stringWithContentsOfFile:ignoreFile encoding:NSUTF8StringEncoding error:nil];
    if (!content) { self.gitignorePatterns = @[]; return; }
    NSMutableArray<NSString *> *rules = [NSMutableArray array];
    for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length == 0 || [t hasPrefix:@"#"]) { continue; } // 空行与注释
        if ([t hasPrefix:@"!"]) { continue; }                 // 取反：轻量子集暂不展开，按不过滤处理
        [rules addObject:t];
    }
    self.gitignorePatterns = [rules copy];
}

// 相对 projectRoot 的路径是否被忽略。
- (BOOL)isIgnoredRelativePath:(NSString *)relPath isDirectory:(BOOL)isDir {
    [self reloadGitignoreIfNeeded];
    if (self.gitignorePatterns.count == 0) { return NO; }
    for (NSString *rule in self.gitignorePatterns) {
        NSString *pat = rule;
        BOOL dirOnly = [pat hasSuffix:@"/"]; // 目录规则
        if (dirOnly) {
            NSString *trim = [pat substringToIndex:pat.length - 1];
            if ([relPath isEqualToString:trim] || [relPath hasPrefix:[trim stringByAppendingString:@"/"]]) { return YES; }
            continue;
        }
        // 无斜杠规则同时匹配 basename（git 语义）。
        if ([pat rangeOfString:@"/"].location == NSNotFound) {
            NSString *base = [relPath lastPathComponent];
            if (fnmatch([pat UTF8String], [base UTF8String], 0) == 0) { return YES; }
            continue;
        }
        NSString *p = pat;
        if ([p hasPrefix:@"/"]) { p = [p substringFromIndex:1]; } // 锚定根
        int flags = FNM_PATHNAME;
#ifdef FNM_PERIOD
        flags |= FNM_PERIOD;
#endif
        if (fnmatch([p UTF8String], [relPath UTF8String], flags) == 0) { return YES; }
        // ** 前缀的简化兼容：**/X 同时试 X。
        if ([p hasPrefix:@"**/"]) {
            NSString *tail = [p substringFromIndex:3];
            if (fnmatch([tail UTF8String], [relPath UTF8String], flags) == 0) { return YES; }
        }
        if (isDir) {
            // 目录本身命中则其下全部忽略（调用方展开时配合）。
            if ([relPath hasPrefix:p]) { return YES; }
        }
    }
    return NO;
}

#pragma mark - iCloud 与二进制判定

// iCloud 未下载判定：NSUbiquitousItemDownloadingStatusKey 非 Current 即视为未下载，返回明确错误。
- (BOOL)checkUbiquitousDownloaded:(NSString *)stdPath error:(NSError **)error {
    NSError *attrErr = nil;
    NSDictionary *values = [[NSFileManager defaultManager] attributesOfItemAtPath:stdPath error:&attrErr];
    (void)values; // 仅探活，状态走 NSURL 资源值
    NSURL *url = [NSURL fileURLWithPath:stdPath];
    NSString *status = nil;
    NSError *rvErr = nil;
    BOOL ok = [url getResourceValue:&status forKey:NSURLUbiquitousItemDownloadingStatusKey error:&rvErr];
    if (ok && status) {
        if (![status isEqualToString:NSURLUbiquitousItemDownloadingStatusCurrent]) {
            if (error) {
                *error = [NSError errorWithDomain:LAFileToolsErrorDomain
                                             code:LAFileToolsErrorNotDownloaded
                                         userInfo:@{NSLocalizedDescriptionKey: @"iCloud 文件尚未下载到本地，请先在“文件”App 中下载后再读取（未发起下载以避免卡死）。"}];
            }
            return NO;
        }
    }
    return YES;
}

// 二进制嗅探：前 N 字节含 NUL 即判二进制。
- (BOOL)isBinaryFileAtPath:(NSString *)stdPath {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:stdPath];
    if (!fh) { return NO; }
    NSData *head = [fh readDataOfLength:kLASniffLength];
    [fh closeFile];
    const uint8_t *bytes = head.bytes;
    for (NSUInteger i = 0; i < head.length; i++) {
        if (bytes[i] == 0x00) { return YES; }
    }
    return NO;
}

#pragma mark - read / write / edit / list

- (nullable NSString *)readFileAtPath:(NSString *)path encoding:(NSStringEncoding)encoding error:(NSError **)error {
    if (!path || path.length == 0) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorInvalidArgument userInfo:@{NSLocalizedDescriptionKey: @"路径为空。"}]; }
        return nil;
    }
    NSString *std = [self standardizedPath:path];
    if (![self gatePath:std tool:@"read" error:error]) { return nil; }
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:std isDirectory:&isDir]) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorNotFound userInfo:@{NSLocalizedDescriptionKey: @"文件不存在。"}]; }
        return nil;
    }
    if (isDir) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorIsDirectory userInfo:@{NSLocalizedDescriptionKey: @"目标是目录，请使用 list。"}]; }
        return nil;
    }
    if (![self checkUbiquitousDownloaded:std error:error]) { return nil; }
    if ([self isBinaryFileAtPath:std]) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorIsBinary userInfo:@{NSLocalizedDescriptionKey: @"二进制文件不支持按文本读取。"}]; }
        return nil;
    }
    NSError *readErr = nil;
    NSString *content = [NSString stringWithContentsOfFile:std encoding:encoding error:&readErr];
    if (!content && error) { *error = readErr; }
    return content;
}

- (BOOL)writeFileAtPath:(NSString *)path content:(NSString *)content encoding:(NSStringEncoding)encoding error:(NSError **)error {
    if (!path || path.length == 0 || !content) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorInvalidArgument userInfo:@{NSLocalizedDescriptionKey: @"路径或内容为空。"}]; }
        return NO;
    }
    NSString *std = [self standardizedPath:path];
    if (![self gatePath:std tool:@"write" error:error]) { return NO; }
    NSString *parent = [std stringByDeletingLastPathComponent];
    NSError *mkErr = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&mkErr]) {
        if (error) { *error = mkErr; }
        return NO;
    }
    NSError *wErr = nil;
    BOOL ok = [content writeToFile:std atomically:YES encoding:encoding error:&wErr];
    if (!ok && error) { *error = wErr; }
    return ok;
}

- (BOOL)editFileAtPath:(NSString *)path oldString:(NSString *)oldString newString:(NSString *)newString replaceAll:(BOOL)replaceAll error:(NSError **)error {
    if (!path || !oldString || !newString || oldString.length == 0) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorInvalidArgument userInfo:@{NSLocalizedDescriptionKey: @"edit 参数非法：路径/旧串/新串不可为空。"}]; }
        return NO;
    }
    // 精确字符串替换：先读原文（复用门禁与二进制/iCloud 检查）。
    NSError *readErr = nil;
    NSString *original = [self readFileAtPath:path encoding:NSUTF8StringEncoding error:&readErr];
    if (!original) { if (error) { *error = readErr; } return NO; }
    // 计数匹配次数（逐字节精确，不做大小写/空白归一）。
    NSUInteger count = 0;
    NSRange search = NSMakeRange(0, original.length);
    while (YES) {
        NSRange f = [original rangeOfString:oldString options:0 range:search];
        if (f.location == NSNotFound) { break; }
        count++;
        NSUInteger next = f.location + f.length;
        if (next >= original.length) { break; }
        search = NSMakeRange(next, original.length - next);
        if (!replaceAll && count > 1) { break; } // 早停即可判定歧义
    }
    if (count == 0) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorEditNoMatch userInfo:@{NSLocalizedDescriptionKey: @"edit 未找到精确匹配的 oldString，未做任何修改。"}]; }
        return NO;
    }
    if (count > 1 && !replaceAll) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorEditAmbiguous userInfo:@{NSLocalizedDescriptionKey: @"edit 有多处精确匹配，请扩大上下文使 oldString 唯一，或使用 replaceAll。"}]; }
        return NO;
    }
    NSString *updated = replaceAll
        ? [original stringByReplacingOccurrencesOfString:oldString withString:newString]
        : [original stringByReplacingOccurrencesOfString:oldString withString:newString options:0 range:[original rangeOfString:oldString]];
    if ([updated isEqualToString:original]) { return YES; } // 等价替换视为成功
    return [self writeFileAtPath:path content:updated encoding:NSUTF8StringEncoding error:error];
}

- (nullable NSArray<NSString *> *)listDirectoryAtPath:(NSString *)path error:(NSError **)error {
    NSString *std = [self standardizedPath:path ?: @""];
    if (![self gatePath:std tool:@"list" error:error]) { return nil; }
    NSError *listErr = nil;
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:std error:&listErr];
    if (!names) { if (error) { *error = listErr; } return nil; }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *full = [std stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir];
        NSString *rel = full;
        if (self.projectRoot && [full hasPrefix:[self.projectRoot stringByAppendingString:@"/"]]) {
            rel = [full substringFromIndex:self.projectRoot.length + 1];
        }
        if (self.projectRoot && [self isIgnoredRelativePath:rel isDirectory:isDir]) { continue; } // 尊重 .gitignore
        [out addObject:full];
    }
    return [out copy];
}

#pragma mark - glob / grep

- (nullable NSArray<NSString *> *)globWithPattern:(NSString *)pattern basePath:(nullable NSString *)basePath error:(NSError **)error {
    if (!pattern || pattern.length == 0) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorInvalidArgument userInfo:@{NSLocalizedDescriptionKey: @"glob pattern 为空。"}]; }
        return nil;
    }
    NSString *base = [self standardizedPath:basePath ?: self.projectRoot ?: [[[self class] sandboxRoots] firstObject]];
    if (![self gatePath:base tool:@"glob" error:error]) { return nil; }
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:base];
    if (!enumerator) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorNotFound userInfo:@{NSLocalizedDescriptionKey: @"基目录不存在。"}]; }
        return nil;
    }
    // pattern 可能是绝对或相对：统一转相对 base 的匹配串。
    NSString *pat = pattern;
    if ([pat isAbsolutePath]) {
        if ([pat hasPrefix:[base stringByAppendingString:@"/"]]) {
            pat = [pat substringFromIndex:base.length + 1];
        } else {
            // 绝对 pattern 越界同样走门禁。
            NSString *stdPat = [pat stringByStandardizingPath];
            if (![self gatePath:stdPat tool:@"glob" error:error]) { return nil; }
            pat = [stdPat lastPathComponent];
        }
    }
    if ([pat hasPrefix:@"/"]) { pat = [pat substringFromIndex:1]; }
    int flags = FNM_PATHNAME;
#ifdef FNM_PERIOD
    flags |= FNM_PERIOD;
#endif
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSString *rel = nil;
    while ((rel = [enumerator nextObject])) {
        NSString *full = [base stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir];
        if ([self isIgnoredRelativePath:rel isDirectory:isDir]) { continue; } // 尊重 .gitignore
        if (isDir) { continue; } // glob 仅返回文件
        BOOL hit = (fnmatch([pat UTF8String], [rel UTF8String], flags) == 0);
        if (!hit && [pat hasPrefix:@"**/"]) {
            // **/ 前缀兼容：同时匹配去掉前缀后的 basename 串。
            NSString *tail = [pat substringFromIndex:3];
            hit = (fnmatch([tail UTF8String], [rel UTF8String], flags) == 0)
               || (fnmatch([tail UTF8String], [[rel lastPathComponent] UTF8String], 0) == 0);
        }
        if (!hit && [pat rangeOfString:@"/"].location == NSNotFound) {
            hit = (fnmatch([pat UTF8String], [[rel lastPathComponent] UTF8String], 0) == 0);
        }
        if (hit) { [out addObject:full]; }
    }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

- (nullable NSArray<LAGrepMatch *> *)grepWithRegex:(NSString *)regex basePath:(NSString *)basePath includeGlobs:(nullable NSArray<NSString *> *)includeGlobs skippedPaths:(NSArray<NSString *> * _Nullable * _Nullable)skippedPaths error:(NSError **)error {
    if (!regex || regex.length == 0 || !basePath) {
        if (error) { *error = [NSError errorWithDomain:LAFileToolsErrorDomain code:LAFileToolsErrorInvalidArgument userInfo:@{NSLocalizedDescriptionKey: @"grep 正则或基目录为空。"}]; }
        return nil;
    }
    NSError *reErr = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:regex options:0 error:&reErr];
    if (!re) { if (error) { *error = reErr; } return nil; }
    NSString *base = [self standardizedPath:basePath];
    if (![self gatePath:base tool:@"grep" error:error]) { return nil; }
    // 先用 glob 展开候选：无 includeGlobs 则全量枚举。
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (includeGlobs.count == 0 || !includeGlobs) {
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:base];
        NSString *rel = nil;
        while ((rel = [enumerator nextObject])) {
            NSString *full = [base stringByAppendingPathComponent:rel];
            BOOL isDir = NO;
            [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir];
            if (isDir) { continue; }
            if ([self isIgnoredRelativePath:rel isDirectory:NO]) { continue; }
            [candidates addObject:full];
        }
    } else {
        for (NSString *g in includeGlobs) {
            NSError *gErr = nil;
            NSArray<NSString *> *hits = [self globWithPattern:g basePath:base error:&gErr];
            if (hits) { [candidates addObjectsFromArray:hits]; }
        }
    }
    NSMutableArray<LAGrepMatch *> *out = [NSMutableArray array];
    NSMutableArray<NSString *> *skipped = [NSMutableArray array];
    for (NSString *file in candidates) {
        if (![self checkUbiquitousDownloaded:file error:nil]) { [skipped addObject:file]; continue; }
        if ([self isBinaryFileAtPath:file]) { [skipped addObject:file]; continue; }
        NSError *rErr = nil;
        NSString *content = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:&rErr];
        if (!content) { [skipped addObject:file]; continue; }
        __block NSInteger lineNo = 0;
        [content enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            lineNo++;
            NSRange range = NSMakeRange(0, line.length);
            if ([re firstMatchInString:line options:0 range:range]) {
                LAGrepMatch *m = [[LAGrepMatch alloc] init];
                m.filePath = file;
                m.line = lineNo;
                m.preview = line.length > kLAMaxPreviewLength ? [[line substringToIndex:kLAMaxPreviewLength] stringByAppendingString:@"…"] : line;
                [out addObject:m];
            }
        }];
    }
    if (skippedPaths) { *skippedPaths = [skipped copy]; }
    return [out copy];
}

#pragma mark - 授权目录管理

- (void)addAuthorizedExternalDirectory:(NSString *)path {
    if (!path.length) { return; }
    NSString *std = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
    NSMutableSet *set = [NSMutableSet setWithSet:self.authorizedExternalDirectories ?: [NSSet set]];
    [set addObject:std];
    self.authorizedExternalDirectories = [set copy];
    // picker 授权目录同样可作为 .gitignore 根的补充：此处不自动切换 projectRoot，由调用方决定。
}

- (void)removeAuthorizedExternalDirectory:(NSString *)path {
    if (!path.length) { return; }
    NSString *std = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
    NSMutableSet *set = [NSMutableSet setWithSet:self.authorizedExternalDirectories ?: [NSSet set]];
    [set removeObject:std];
    self.authorizedExternalDirectories = [set copy];
}

@end
