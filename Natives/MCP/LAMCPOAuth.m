// LAMCPOAuth.m
// 中文注释：OAuth/Keychain/通配权限/高 token 开关的占位实现；永不打印密钥，不做真实网络验证。

#import "LAMCPOAuth.h"
#import <Security/Security.h>

NSString *const LAMCPOAuthErrorDomain = @"org.luminagent.mcp.oauth";

/* Keychain 服务名前缀（按 serverId 拼装 account，避免与他组 LAKeychainStore 冲突） */
static NSString *const kLAMCPKeychainService = @"org.luminagent.mcp.token";

#pragma mark - LAMCPOAuthContext

@implementation LAMCPOAuthContext

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _serverId = [coder decodeObjectOfClass:[NSString class] forKey:@"serverId"];
        _clientId = [coder decodeObjectOfClass:[NSString class] forKey:@"clientId"];
        _scope = [coder decodeObjectOfClass:[NSString class] forKey:@"scope"];
        _authorizeURL = [coder decodeObjectOfClass:[NSString class] forKey:@"authorizeURL"];
        _redirectScheme = [coder decodeObjectOfClass:[NSString class] forKey:@"redirectScheme"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.serverId forKey:@"serverId"];
    [coder encodeObject:self.clientId forKey:@"clientId"];
    [coder encodeObject:self.scope forKey:@"scope"];
    [coder encodeObject:self.authorizeURL forKey:@"authorizeURL"];
    [coder encodeObject:self.redirectScheme forKey:@"redirectScheme"];
}

- (NSString *)description {
    // 占位上下文可打印（不含 token），但 clientId 仍做截断，避免泄露配置细节
    NSString *cid = self.clientId.length > 4
        ? [NSString stringWithFormat:@"%@…(len=%lu)", [self.clientId substringToIndex:4], (unsigned long)self.clientId.length]
        : @"(empty)";
    return [NSString stringWithFormat:@"<LAMCPOAuthContext server=%@ client=%@ scope=%@>",
            self.serverId, cid, self.scope];
}

@end

#pragma mark - LAMCPOAuth

@interface LAMCPOAuth ()
// serverId -> @(YES/NO) 高 token 标记
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *highTokenFlags;
// sessionId -> { serverId } 高 token 按需启用集
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *sessionGrants;
// serverId -> @(AuthState) 401 过期标记（内存态，重启后以 Keychain 有无为准）
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *expiredMarks;
@property (nonatomic, strong) dispatch_queue_t syncQueue;
@end

@implementation LAMCPOAuth

+ (instancetype)sharedOAuth {
    static LAMCPOAuth *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[LAMCPOAuth alloc] initPrivate]; });
    return s;
}

- (instancetype)initPrivate {
    if (self = [super init]) {
        _highTokenFlags = [NSMutableDictionary dictionary];
        _sessionGrants = [NSMutableDictionary dictionary];
        _expiredMarks = [NSMutableDictionary dictionary];
        _syncQueue = dispatch_queue_create("org.luminagent.mcp.oauth.sync", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (instancetype)init { return [[self class] sharedOAuth]; }

- (BOOL)fillError:(NSError **)error code:(LAMCPOAuthErrorCode)code desc:(NSString *)desc {
    if (error) {
        *error = [NSError errorWithDomain:LAMCPOAuthErrorDomain code:code
                                 userInfo:@{NSLocalizedDescriptionKey: desc ?: @"OAuth 操作失败"}];
    }
    return NO;
}

#pragma mark 占位上下文

- (nullable LAMCPOAuthContext *)makeOAuthContextForServerId:(NSString *)serverId
                                                   clientId:(NSString *)clientId
                                                      scope:(NSString *)scope
                                               authorizeURL:(NSString *)authorizeURL
                                             redirectScheme:(NSString *)redirectScheme
                                                      error:(NSError **)error {
    if (serverId.length == 0 || clientId.length == 0 || authorizeURL.length == 0 || redirectScheme.length == 0) {
        [self fillError:error code:LAMCPOAuthErrorCodeInvalidArgument desc:@"OAuth 参数不完整（serverId/clientId/authorizeURL/redirectScheme 均不能为空）"];
        return nil;
    }
    // 仅做占位拼装：不校验端点可达性，不发起网络请求
    LAMCPOAuthContext *ctx = [[LAMCPOAuthContext alloc] init];
    ctx.serverId = serverId;
    ctx.clientId = clientId;
    ctx.scope = scope ?: @"";
    ctx.authorizeURL = authorizeURL;
    ctx.redirectScheme = redirectScheme;
    return ctx;
}

- (void)startAuthenticationSessionPlaceholder:(LAMCPOAuthContext *)context
                                   completion:(void (^)(BOOL, NSError *))completion {
    // ASWebAuthenticationSession 占位接口说明（iOS15+ API，仅封装不真调）：
    // 真机联调时的真实实现应为：
    //   ASWebAuthenticationSession *s = [[ASWebAuthenticationSession alloc]
    //       initWithURL:authURL callbackScheme:context.redirectScheme
    //       completionHandler:^(NSURL *url, NSError *err) { …解析 code…换 token…存 Keychain… }];
    //   s.presentationContextProvider = <当前窗口的 provider>;
    //   [s start];
    // 当前占位实现：不断言、不弹窗、不请求网络，直接回失败，调用方据此走“待联调”分支。
    // 注意：此处刻意不 import <AuthenticationServices/AuthenticationServices.h>，
    // 以避免在 CI 占位阶段链接系统鉴权 UI；联调时取消本注释并补齐 import 即可。
    if (!context) {
        if (completion) {
            NSError *e = [NSError errorWithDomain:LAMCPOAuthErrorDomain code:LAMCPOAuthErrorCodeInvalidArgument
                                         userInfo:@{NSLocalizedDescriptionKey: @"OAuth 上下文为空（占位实现未调起系统浏览器）"}];
            completion(NO, e);
        }
        return;
    }
    if (completion) {
        NSError *e = [NSError errorWithDomain:LAMCPOAuthErrorDomain code:LAMCPOAuthErrorCodeNotAuthorized
                                     userInfo:@{NSLocalizedDescriptionKey: @"占位实现：未调起 ASWebAuthenticationSession，需真机联调补齐"}];
        completion(NO, e);
    }
}

#pragma mark Keychain（token 隔离）

- (NSDictionary *)keychainQueryForServerId:(NSString *)serverId {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kLAMCPKeychainService,
        (__bridge id)kSecAttrAccount: serverId,
    };
}

- (BOOL)saveToken:(NSString *)token forServerId:(NSString *)serverId error:(NSError **)error {
    if (token.length == 0 || serverId.length == 0) {
        return [self fillError:error code:LAMCPOAuthErrorCodeInvalidArgument desc:@"token/serverId 不能为空"];
    }
    NSData *data = [token dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *query = [[self keychainQueryForServerId:serverId] mutableCopy];
    OSStatus exists = SecItemCopyMatching((__bridge CFDictionaryRef)@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kLAMCPKeychainService,
        (__bridge id)kSecAttrAccount: serverId,
        (__bridge id)kSecReturnData: @NO,
    }, NULL);
    OSStatus st;
    if (exists == errSecSuccess) {
        st = SecItemUpdate((__bridge CFDictionaryRef)query,
                           (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
    } else {
        NSMutableDictionary *add = [query mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        // 仅本设备可读，iTunes 备份不迁移（MCP token 安全等级）
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
        st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
    if (st != errSecSuccess) {
        return [self fillError:error code:LAMCPOAuthErrorCodeKeychainFailed
                          desc:[NSString stringWithFormat:@"Keychain 保存失败（os=%d），未打印 token", (int)st]];
    }
    // 保存成功后清除过期标记
    dispatch_sync(self.syncQueue, ^{ [self.expiredMarks removeObjectForKey:serverId]; });
    return YES;
}

- (BOOL)hasTokenForServerId:(NSString *)serverId {
    if (serverId.length == 0) { return NO; }
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kLAMCPKeychainService,
        (__bridge id)kSecAttrAccount: serverId,
        (__bridge id)kSecReturnData: @NO,
    }, NULL);
    return st == errSecSuccess;
}

- (nullable NSString *)loadTokenForServerId:(NSString *)serverId error:(NSError **)error {
    if (serverId.length == 0) {
        [self fillError:error code:LAMCPOAuthErrorCodeInvalidArgument desc:@"serverId 不能为空"];
        return nil;
    }
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kLAMCPKeychainService,
        (__bridge id)kSecAttrAccount: serverId,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    }, &out);
    if (st != errSecSuccess) {
        [self fillError:error code:LAMCPOAuthErrorCodeNotAuthorized desc:@"无有效授权（Keychain 内无 token）"];
        return nil;
    }
    NSData *data = (__bridge_transfer NSData *)out;
    NSString *token = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!token) {
        [self fillError:error code:LAMCPOAuthErrorCodeKeychainFailed desc:@"Keychain 数据解码失败"];
        return nil;
    }
    return token; // 调用方负责将 token 仅放入 Authorization 头，禁止 NSLog/上报
}

- (BOOL)clearTokenForServerId:(NSString *)serverId error:(NSError **)error {
    if (serverId.length == 0) {
        return [self fillError:error code:LAMCPOAuthErrorCodeInvalidArgument desc:@"serverId 不能为空"];
    }
    OSStatus st = SecItemDelete((__bridge CFDictionaryRef)[self keychainQueryForServerId:serverId]);
    if (st != errSecSuccess && st != errSecItemNotFound) {
        return [self fillError:error code:LAMCPOAuthErrorCodeKeychainFailed
                          desc:[NSString stringWithFormat:@"Keychain 清除失败（os=%d）", (int)st]];
    }
    dispatch_sync(self.syncQueue, ^{ [self.expiredMarks removeObjectForKey:serverId]; });
    return YES;
}

- (LAMCPAuthState)authStateForServerId:(NSString *)serverId isLocal:(BOOL)isLocal {
    if (isLocal) { return LAMCPAuthStateUnknown; } // local 白名单命令无需 OAuth
    __block BOOL expired = NO;
    dispatch_sync(self.syncQueue, ^{ expired = [self.expiredMarks[serverId] boolValue]; });
    if (expired) { return LAMCPAuthStateExpired; }
    return [self hasTokenForServerId:serverId] ? LAMCPAuthStateAuthorized : LAMCPAuthStateNotAuthorized;
}

- (BOOL)handleHTTPStatus:(NSInteger)statusCode forServerId:(NSString *)serverId {
    if (statusCode != 401 || serverId.length == 0) { return NO; }
    // 标记过期（不清 token，待用户重登后覆盖），触发回调提示重新授权
    dispatch_sync(self.syncQueue, ^{ self.expiredMarks[serverId] = @YES; });
    LAMCPReauthHandler h = self.onNeedReauth;
    if (h) { h(serverId); } // 只传 serverId，不传 token；UI 层据此弹授权页
    return YES;
}

#pragma mark 通配权限匹配（mcp_*）

+ (BOOL)toolName:(NSString *)toolName matchesPattern:(NSString *)pattern {
    if (!toolName || !pattern) { return NO; }
    if (pattern.length == 0 || toolName.length == 0) { return NO; }
    // 将 glob（* / ?）转正则：其余字符全转义；* -> .*，? -> .
    NSMutableString *re = [NSMutableString stringWithString:@"^"];
    for (NSUInteger i = 0; i < pattern.length; i++) {
        unichar c = [pattern characterAtIndex:i];
        if (c == '*') { [re appendString:@".*"]; }
        else if (c == '?') { [re appendString:@"."]; }
        else { [re appendFormat:@"\\%C", c]; }
    }
    [re appendString:@"$"];
    NSError *e = nil;
    NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:re options:0 error:&e];
    if (!rx || e) { return NO; }
    NSRange r = NSMakeRange(0, toolName.length);
    return [rx firstMatchInString:toolName options:0 range:r] != nil;
}

+ (BOOL)toolName:(NSString *)toolName matchesAnyPatternIn:(NSArray<NSString *> *)patterns {
    for (NSString *p in patterns) {
        if ([self toolName:toolName matchesPattern:p]) { return YES; }
    }
    return NO;
}

#pragma mark 高 token 治理

- (void)setHighToken:(BOOL)highToken forServerId:(NSString *)serverId {
    if (serverId.length == 0) { return; }
    dispatch_sync(self.syncQueue, ^{ self.highTokenFlags[serverId] = @(highToken); });
}

- (BOOL)isHighTokenServer:(NSString *)serverId {
    if (serverId.length == 0) { return NO; }
    __block BOOL v = NO;
    dispatch_sync(self.syncQueue, ^{ v = [self.highTokenFlags[serverId] boolValue]; });
    return v;
}

- (void)setHighTokenServer:(NSString *)serverId enabled:(BOOL)enabled forSessionId:(NSString *)sessionId {
    if (serverId.length == 0 || sessionId.length == 0) { return; }
    dispatch_sync(self.syncQueue, ^{
        NSMutableSet *set = self.sessionGrants[sessionId];
        if (!set) { set = [NSMutableSet set]; self.sessionGrants[sessionId] = set; }
        if (enabled) { [set addObject:serverId]; }
        else { [set removeObject:serverId]; }
    });
}

- (BOOL)isHighTokenServer:(NSString *)serverId enabledForSession:(NSString *)sessionId {
    if (serverId.length == 0 || sessionId.length == 0) { return NO; }
    // 非高 token 服务不受此开关约束（由 LAMCPManager 的 enabled/Connected 决定）
    if (![self isHighTokenServer:serverId]) { return YES; }
    // 高 token 服务：默认禁用，按会话按需启用
    __block BOOL v = NO;
    dispatch_sync(self.syncQueue, ^{ v = [self.sessionGrants[sessionId] containsObject:serverId]; });
    return v;
}

- (NSSet<NSString *> *)enabledHighTokenServerIdsForSession:(NSString *)sessionId {
    if (sessionId.length == 0) { return [NSSet set]; }
    __block NSSet *s = nil;
    dispatch_sync(self.syncQueue, ^{ s = [self.sessionGrants[sessionId] copy] ?: [NSSet set]; });
    return s;
}

@end
