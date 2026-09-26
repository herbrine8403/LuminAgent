// LAMultiSession.m
// 中文注释：多会话拓扑 + 分享三档 + 脱敏导入导出的占位实现；不触网，不碰真实消息存储。

#import "LAMultiSession.h"

NSString *const LAMultiSessionErrorDomain = @"org.luminagent.multisession";

#pragma mark - LAMSessionNode

@implementation LAMSessionNode

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _sessionId = [coder decodeObjectOfClass:[NSString class] forKey:@"sessionId"];
        _projectId = [coder decodeObjectOfClass:[NSString class] forKey:@"projectId"];
        _parentSessionId = [coder decodeObjectOfClass:[NSString class] forKey:@"parentSessionId"];
        _concern = [coder decodeObjectOfClass:[NSString class] forKey:@"concern"];
        _createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.sessionId forKey:@"sessionId"];
    [coder encodeObject:self.projectId forKey:@"projectId"];
    [coder encodeObject:self.parentSessionId forKey:@"parentSessionId"];
    [coder encodeObject:self.concern forKey:@"concern"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
}

- (id)copyWithZone:(NSZone *)zone {
    LAMSessionNode *c = [[LAMSessionNode allocWithZone:zone] init];
    c.sessionId = self.sessionId;
    c.projectId = self.projectId;
    c.parentSessionId = self.parentSessionId;
    c.concern = self.concern;
    c.createdAt = self.createdAt;
    return c;
}

@end

#pragma mark - LAMShareRecord

@implementation LAMShareRecord

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _sessionId = [coder decodeObjectOfClass:[NSString class] forKey:@"sessionId"];
        _shareToken = [coder decodeObjectOfClass:[NSString class] forKey:@"shareToken"];
        _shareURL = [coder decodeObjectOfClass:[NSString class] forKey:@"shareURL"];
        _createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
        _revoked = [coder decodeBoolForKey:@"revoked"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.sessionId forKey:@"sessionId"];
    [coder encodeObject:self.shareToken forKey:@"shareToken"];
    [coder encodeObject:self.shareURL forKey:@"shareURL"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
    [coder encodeBool:self.revoked forKey:@"revoked"];
}

- (id)copyWithZone:(NSZone *)zone {
    LAMShareRecord *c = [[LAMShareRecord allocWithZone:zone] init];
    c.sessionId = self.sessionId;
    c.shareToken = self.shareToken;
    c.shareURL = self.shareURL;
    c.createdAt = self.createdAt;
    c.revoked = self.revoked;
    return c;
}

@end

#pragma mark - LAMultiSession

@interface LAMultiSession ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, LAMSessionNode *> *nodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, LAMShareRecord *> *shares; // sessionId -> record
@property (nonatomic, strong) NSMutableSet<NSString *> *disabledProjects;
@property (nonatomic, copy, nullable) NSString *activeSessionId;
@property (nonatomic, strong) dispatch_queue_t syncQueue;
@end

@implementation LAMultiSession

+ (instancetype)sharedInstance {
    static LAMultiSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[LAMultiSession alloc] initPrivate]; });
    return s;
}

- (instancetype)initPrivate {
    if (self = [super init]) {
        _nodes = [NSMutableDictionary dictionary];
        _shares = [NSMutableDictionary dictionary];
        _disabledProjects = [NSMutableSet set];
        _syncQueue = dispatch_queue_create("org.luminagent.multisession.sync", DISPATCH_QUEUE_SERIAL);
        _shareMode = LAMShareModeManual; // 默认 manual
    }
    return self;
}

- (instancetype)init { return [[self class] sharedInstance]; }

- (BOOL)fillError:(NSError **)error code:(LAMultiSessionErrorCode)code desc:(NSString *)desc {
    if (error) {
        *error = [NSError errorWithDomain:LAMultiSessionErrorDomain code:code
                                 userInfo:@{NSLocalizedDescriptionKey: desc ?: @"多会话操作失败"}];
    }
    return NO;
}

#pragma mark 项目级禁用

- (void)setShareDisabled:(BOOL)disabled forProjectId:(NSString *)projectId {
    if (projectId.length == 0) { return; }
    dispatch_sync(self.syncQueue, ^{
        if (disabled) { [self.disabledProjects addObject:projectId]; }
        else { [self.disabledProjects removeObject:projectId]; }
    });
}

- (BOOL)isShareDisabledForProjectId:(NSString *)projectId {
    if (projectId.length == 0) { return NO; }
    __block BOOL v = NO;
    dispatch_sync(self.syncQueue, ^{ v = [self.disabledProjects containsObject:projectId]; });
    return v;
}

- (BOOL)shareAllowedForProject:(NSString *)projectId error:(NSError **)error {
    if (self.shareMode == LAMShareModeDisabled) {
        [self fillError:error code:LAMultiSessionErrorCodeShareDisabled desc:@"分享已被全局禁用（合规模式），拒绝外发"];
        return NO;
    }
    if (projectId.length > 0 && [self isShareDisabledForProjectId:projectId]) {
        [self fillError:error code:LAMultiSessionErrorCodeShareDisabled desc:@"该项目已被强制禁用分享，拒绝外发"];
        return NO;
    }
    return YES;
}

#pragma mark 多会话

- (nullable LAMSessionNode *)createSessionInProject:(NSString *)projectId
                                            concern:(NSString *)concern
                                              error:(NSError **)error {
    if (projectId.length == 0 || concern.length == 0) {
        [self fillError:error code:LAMultiSessionErrorCodeInvalidArgument desc:@"projectId/concern 不能为空"];
        return nil;
    }
    __block LAMSessionNode *n = nil;
    dispatch_sync(self.syncQueue, ^{
        n = [[LAMSessionNode alloc] init];
        n.sessionId = [[NSUUID UUID] UUIDString];
        n.projectId = projectId;
        n.parentSessionId = nil;
        n.concern = concern;
        n.createdAt = [NSDate date];
        self.nodes[n.sessionId] = n;
        self.activeSessionId = n.sessionId;
    });
    // auto 模式：建会即分享（占位：本地生成链接，不外发网络；联调后才对接自托管服务）
    if (self.shareMode == LAMShareModeAuto) {
        NSError *se = nil;
        [self shareSession:n.sessionId error:&se]; // auto 下分享失败不阻塞建会
    }
    return [n copy];
}

- (nullable LAMSessionNode *)forkSession:(NSString *)sourceSessionId
                             newConcern:(NSString *)concern
                                  error:(NSError **)error {
    if (sourceSessionId.length == 0 || concern.length == 0) {
        [self fillError:error code:LAMultiSessionErrorCodeInvalidArgument desc:@"sourceSessionId/newConcern 不能为空"];
        return nil;
    }
    __block LAMSessionNode *src = nil;
    dispatch_sync(self.syncQueue, ^{ src = self.nodes[sourceSessionId]; });
    if (!src) {
        [self fillError:error code:LAMultiSessionErrorCodeNotFound desc:@"源会话不存在，无法 fork"];
        return nil;
    }
    __block LAMSessionNode *n = nil;
    dispatch_sync(self.syncQueue, ^{
        n = [[LAMSessionNode alloc] init];
        n.sessionId = [[NSUUID UUID] UUIDString];
        n.projectId = src.projectId;
        n.parentSessionId = src.sessionId; // parent-child 关联
        n.concern = concern;
        n.createdAt = [NSDate date];
        self.nodes[n.sessionId] = n;
        self.activeSessionId = n.sessionId;
    });
    return [n copy];
}

- (BOOL)removeSession:(NSString *)sessionId error:(NSError **)error {
    if (sessionId.length == 0) {
        return [self fillError:error code:LAMultiSessionErrorCodeInvalidArgument desc:@"sessionId 不能为空"];
    }
    __block BOOL found = NO;
    dispatch_sync(self.syncQueue, ^{
        found = (self.nodes[sessionId] != nil);
        [self.nodes removeObjectForKey:sessionId];
        [self.shares removeObjectForKey:sessionId];
        if ([self.activeSessionId isEqualToString:sessionId]) { self.activeSessionId = nil; }
    });
    if (!found) { return [self fillError:error code:LAMultiSessionErrorCodeNotFound desc:@"会话不存在"]; }
    return YES;
}

- (nullable LAMSessionNode *)nodeForSession:(NSString *)sessionId {
    if (sessionId.length == 0) { return nil; }
    __block LAMSessionNode *n = nil;
    dispatch_sync(self.syncQueue, ^{ n = [self.nodes[sessionId] copy]; });
    return n;
}

- (NSArray<LAMSessionNode *> *)listSessionsInProject:(NSString *)projectId {
    __block NSArray *all = nil;
    dispatch_sync(self.syncQueue, ^{ all = [self.nodes.allValues copy]; });
    NSMutableArray *out = [NSMutableArray array];
    for (LAMSessionNode *n in all) {
        if (projectId.length == 0 || [n.projectId isEqualToString:projectId]) { [out addObject:[n copy]]; }
    }
    return [out sortedArrayUsingComparator:^NSComparisonResult(LAMSessionNode *a, LAMSessionNode *b) {
        return [a.createdAt compare:b.createdAt];
    }];
}

- (NSArray<LAMSessionNode *> *)childrenOfSession:(NSString *)sessionId {
    __block NSArray *all = nil;
    dispatch_sync(self.syncQueue, ^{ all = [self.nodes.allValues copy]; });
    NSMutableArray *out = [NSMutableArray array];
    for (LAMSessionNode *n in all) {
        if ([n.parentSessionId isEqualToString:sessionId]) { [out addObject:[n copy]]; }
    }
    return [out copy];
}

- (nullable LAMSessionNode *)parentOfSession:(NSString *)sessionId {
    LAMSessionNode *n = [self nodeForSession:sessionId];
    if (!n.parentSessionId) { return nil; }
    return [self nodeForSession:n.parentSessionId];
}

- (nullable LAMSessionNode *)switchToSession:(NSString *)sessionId error:(NSError **)error {
    LAMSessionNode *n = [self nodeForSession:sessionId];
    if (!n) {
        [self fillError:error code:LAMultiSessionErrorCodeNotFound desc:@"目标会话不存在，无法切换"];
        return nil;
    }
    dispatch_sync(self.syncQueue, ^{ self.activeSessionId = sessionId; });
    return n;
}

- (nullable LAMSessionNode *)activeSession {
    __block NSString *aid = nil;
    dispatch_sync(self.syncQueue, ^{ aid = [self.activeSessionId copy]; });
    return aid ? [self nodeForSession:aid] : nil;
}

#pragma mark 分享

- (NSString *)shareBaseURL {
    NSString *base = self.selfHostedShareBaseURL.length > 0 ? self.selfHostedShareBaseURL : @"https://opncd.ai";
    // 去掉末尾斜杠，统一拼 /s/<token>
    while ([base hasSuffix:@"/"] && base.length > 1) { base = [base substringToIndex:base.length - 1]; }
    return base;
}

- (nullable LAMShareRecord *)shareSession:(NSString *)sessionId error:(NSError **)error {
    LAMSessionNode *n = [self nodeForSession:sessionId];
    if (!n) {
        [self fillError:error code:LAMultiSessionErrorCodeNotFound desc:@"会话不存在，无法分享"];
        return nil;
    }
    if (![self shareAllowedForProject:n.projectId error:error]) { return nil; }
    // 幂等：未撤销的分享直接返回（避免重复生成链接）
    __block LAMShareRecord *existing = nil;
    dispatch_sync(self.syncQueue, ^{ existing = self.shares[sessionId]; });
    if (existing && !existing.revoked) { return [existing copy]; }
    // 本地生成 token（占位，未真上传；联调后才 POST 自托管服务）
    NSString *token = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    LAMShareRecord *r = [[LAMShareRecord alloc] init];
    r.sessionId = sessionId;
    r.shareToken = token;
    r.shareURL = [NSString stringWithFormat:@"%@/s/%@", [self shareBaseURL], token];
    r.createdAt = [NSDate date];
    r.revoked = NO;
    dispatch_sync(self.syncQueue, ^{ self.shares[sessionId] = r; });
    return [r copy];
}

- (BOOL)unshareSession:(NSString *)sessionId error:(NSError **)error {
    if (sessionId.length == 0) {
        return [self fillError:error code:LAMultiSessionErrorCodeInvalidArgument desc:@"sessionId 不能为空"];
    }
    __block LAMShareRecord *r = nil;
    dispatch_sync(self.syncQueue, ^{ r = self.shares[sessionId]; });
    if (!r) { return [self fillError:error code:LAMultiSessionErrorCodeNotFound desc:@"该会话无分享记录"]; }
    dispatch_sync(self.syncQueue, ^{ r.revoked = YES; });
    return YES;
}

- (BOOL)isSessionShared:(NSString *)sessionId {
    __block LAMShareRecord *r = nil;
    dispatch_sync(self.syncQueue, ^{ r = self.shares[sessionId]; });
    return (r != nil && !r.revoked);
}

#pragma mark 导入导出（脱敏）

+ (NSSet<NSString *> *)credentialKeyHints {
    // 疑似凭证的键名片段（小写匹配）：命中即视为凭证
    return [NSSet setWithArray:@[
        @"apikey", @"api_key", @"api-key",
        @"token", @"accesstoken", @"refreshtoken",
        @"secret", @"clientsecret",
        @"authorization", @"auth",
        @"password", @"passwd",
        @"headers", // 整组 headers 一律视为敏感（value 永不外发）
        @"cookie", @"set-cookie",
    ]];
}

+ (BOOL)keyLooksLikeCredential:(NSString *)key {
    if (key.length == 0) { return NO; }
    NSString *lower = key.lowercaseString;
    // 去掉下划线/中划线后匹配，提高命中率
    NSString *flat = [[[lower stringByReplacingOccurrencesOfString:@"_" withString:@""]
                        stringByReplacingOccurrencesOfString:@"-" withString:@""]
                        stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *hint in [self credentialKeyHints]) {
        NSString *fh = [[[hint.lowercaseString stringByReplacingOccurrencesOfString:@"_" withString:@""]
                          stringByReplacingOccurrencesOfString:@"-" withString:@""]
                          stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([flat containsString:fh]) { return YES; }
    }
    return NO;
}

+ (id)sanitizedObject:(id)obj {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        for (id k in (NSDictionary *)obj) {
            if (![k isKindOfClass:[NSString class]]) { continue; }
            NSString *ks = (NSString *)k;
            id v = ((NSDictionary *)obj)[k];
            if ([self keyLooksLikeCredential:ks]) {
                out[ks] = @"***REDACTED***"; // 剥离凭证，只留占位
            } else {
                out[ks] = [self sanitizedObject:v];
            }
        }
        return [out copy];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id e in (NSArray *)obj) { [out addObject:[self sanitizedObject:e]]; }
        return [out copy];
    }
    return obj;
}

+ (NSDictionary *)sanitizedSnapshot:(NSDictionary *)snapshot {
    if (![snapshot isKindOfClass:[NSDictionary class]]) { return @{}; }
    id clean = [self sanitizedObject:snapshot];
    return [clean isKindOfClass:[NSDictionary class]] ? clean : @{};
}

+ (BOOL)snapshotContainsCredentialValue:(id)obj {
    // 深搜：任一凭证键的值不是 ***REDACTED*** 即视为含真实凭证
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            if (![k isKindOfClass:[NSString class]]) { continue; }
            id v = ((NSDictionary *)obj)[k];
            if ([self keyLooksLikeCredential:(NSString *)k]) {
                if ([v isKindOfClass:[NSString class]]) {
                    if (![(NSString *)v isEqualToString:@"***REDACTED***"] && [(NSString *)v length] > 0) { return YES; }
                } else if (v && ![v isKindOfClass:[NSNull class]]) {
                    return YES; // 非字符串凭证值一律视为敏感
                }
            } else if ([self snapshotContainsCredentialValue:v]) { return YES; }
        }
        return NO;
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) { if ([self snapshotContainsCredentialValue:e]) { return YES; } }
    }
    return NO;
}

+ (BOOL)snapshotContainsCredential:(NSDictionary *)snapshot {
    if (![snapshot isKindOfClass:[NSDictionary class]]) { return NO; }
    return [self snapshotContainsCredentialValue:snapshot];
}

- (BOOL)exportSession:(NSString *)sessionId
               toFile:(NSString *)filePath
             sanitize:(BOOL)sanitize
        fetchSnapshot:(NSDictionary * (^)(NSString *))fetchSnapshot
                error:(NSError **)error {
    LAMSessionNode *n = [self nodeForSession:sessionId];
    if (!n) {
        return [self fillError:error code:LAMultiSessionErrorCodeNotFound desc:@"会话不存在，无法导出"];
    }
    if (![self shareAllowedForProject:n.projectId error:error]) { return NO; }
    if (filePath.length == 0 || !fetchSnapshot) {
        return [self fillError:error code:LAMultiSessionErrorCodeInvalidArgument desc:@"导出路径与快照回调不能为空"];
    }
    NSDictionary *raw = fetchSnapshot(sessionId) ?: @{};
    NSDictionary *payload = nil;
    if (sanitize) {
        payload = [[self class] sanitizedSnapshot:raw]; // export --sanitize：强制脱敏后离线流转
    } else {
        // 非脱敏导出：若含疑似凭证直接拒绝，避免无意泄露
        if ([[self class] snapshotContainsCredential:raw]) {
            return [self fillError:error code:LAMultiSessionErrorCodeSanitizeFailed
                              desc:@"快照含疑似凭证，请使用 sanitize=YES（export --sanitize）后导出"];
        }
        payload = raw;
    }
    NSDictionary *envelope = @{
        @"kind": @"luminagent.session-export",
        @"version": @1,
        @"exportedAt": @([[NSDate date] timeIntervalSince1970]),
        @"sanitized": @(sanitize),
        @"node": @{
            @"sessionId": n.sessionId ?: @"",
            @"projectId": n.projectId ?: @"",
            @"concern": n.concern ?: @"",
            @"parentSessionId": n.parentSessionId ?: @"",
        },
        @"snapshot": payload,
    };
    NSError *jsonErr = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:envelope options:NSJSONWritingSortedKeys error:&jsonErr];
    if (!data || jsonErr) {
        if (error) { *error = jsonErr; }
        return NO;
    }
    NSError *ioErr = nil;
    BOOL ok = [data writeToFile:filePath options:NSDataWritingAtomic error:&ioErr];
    if (!ok) {
        if (error) { *error = ioErr; }
        return [self fillError:error code:LAMultiSessionErrorCodeIOFailed desc:@"导出文件写入失败"];
    }
    return YES;
}

- (nullable LAMSessionNode *)importSessionFromFile:(NSString *)filePath
                                         projectId:(NSString *)projectId
                                             error:(NSError **)error {
    if (filePath.length == 0 || projectId.length == 0) {
        [self fillError:error code:LAMultiSessionErrorCodeInvalidArgument desc:@"文件路径/projectId 不能为空"];
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) {
        [self fillError:error code:LAMultiSessionErrorCodeIOFailed desc:@"导入文件读取失败"];
        return nil;
    }
    NSError *jsonErr = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
    if (!obj || jsonErr) {
        if (error) { *error = jsonErr; }
        return nil;
    }
    if (![obj isKindOfClass:[NSDictionary class]]) {
        [self fillError:error code:LAMultiSessionErrorCodeInvalidArgument desc:@"导入文件格式非法（非 JSON 对象）"];
        return nil;
    }
    NSDictionary *env = (NSDictionary *)obj;
    id snapshot = env[@"snapshot"];
    // 文件中若含密钥字段则拒绝恢复（交接无密钥泄露）
    if ([snapshot isKindOfClass:[NSDictionary class]] &&
        [[self class] snapshotContainsCredential:snapshot]) {
        [self fillError:error code:LAMultiSessionErrorCodeSanitizeFailed desc:@"导入文件含疑似凭证，已拒绝恢复（请先脱敏）"];
        return nil;
    }
    NSString *concern = @"imported";
    id node = env[@"node"];
    if ([node isKindOfClass:[NSDictionary class]] && [node[@"concern"] isKindOfClass:[NSString class]]) {
        concern = [NSString stringWithFormat:@"imported-%@", node[@"concern"]];
    }
    // 导入即新建拓扑（新 sessionId，避免与原会话冲突；消息恢复由调用方经 LASessionManager 完成）
    return [self createSessionInProject:projectId concern:concern error:error];
}

@end
