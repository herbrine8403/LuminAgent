// LAMCPManager.m
// 中文注释：MCP 服务管理的占位实现（无真实网络/OAuth 调用，纯本地状态机 + 配置持久化）。

#import "LAMCPManager.h"

NSString *const LAMCPErrorDomain = @"org.luminagent.mcp";

/* 持久化 key（仅存配置快照，headers 只存 key 名，不存 value） */
static NSString *const kLAMCPStoreKey = @"LuminAgent.MCP.Servers.v1";

#pragma mark - LAMCPServer

@implementation LAMCPServer

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithName:(NSString *)name type:(LAMCPServerType)type {
    if (self = [super init]) {
        _serverId = [[NSUUID UUID] UUIDString];
        _name = [name copy] ?: @"";
        _type = type;
        _enabled = YES;
        _connectionState = LAMCPConnectionStateUnknown;
        _tools = @[];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _serverId = [coder decodeObjectOfClass:[NSString class] forKey:@"serverId"];
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _type = [coder decodeIntegerForKey:@"type"];
        _command = [coder decodeObjectOfClass:[NSString class] forKey:@"command"];
        _args = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSArray class], [NSString class]]] forKey:@"args"];
        _url = [coder decodeObjectOfClass:[NSString class] forKey:@"url"];
        // 注意：headers 的 value 不做持久化，此处仅恢复 key 名占位
        NSArray *headerKeys = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSArray class], [NSString class]]] forKey:@"headerKeys"];
        if (headerKeys.count > 0) {
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            for (NSString *k in headerKeys) { d[k] = @"***"; }
            _headers = [d copy];
        }
        _enabled = [coder decodeBoolForKey:@"enabled"];
        _connectionState = [coder decodeIntegerForKey:@"connectionState"];
        _lastErrorMessage = [coder decodeObjectOfClass:[NSString class] forKey:@"lastErrorMessage"];
        _tools = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSArray class], [NSString class]]] forKey:@"tools"] ?: @[];
        _highToken = [coder decodeBoolForKey:@"highToken"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.serverId forKey:@"serverId"];
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.command forKey:@"command"];
    [coder encodeObject:self.args forKey:@"args"];
    [coder encodeObject:self.url forKey:@"url"];
    // 仅持久化 headers 的 key 名，不持久化 value（密钥隔离）
    [coder encodeObject:(self.headers.allKeys ?: @[]) forKey:@"headerKeys"];
    [coder encodeBool:self.enabled forKey:@"enabled"];
    [coder encodeInteger:self.connectionState forKey:@"connectionState"];
    [coder encodeObject:self.lastErrorMessage forKey:@"lastErrorMessage"];
    [coder encodeObject:self.tools forKey:@"tools"];
    [coder encodeBool:self.highToken forKey:@"highToken"];
}

- (id)copyWithZone:(NSZone *)zone {
    LAMCPServer *c = [[LAMCPServer allocWithZone:zone] initWithName:self.name type:self.type];
    c.serverId = self.serverId;
    c.command = self.command;
    c.args = self.args;
    c.url = self.url;
    c.headers = self.headers;
    c.enabled = self.enabled;
    c.connectionState = self.connectionState;
    c.lastErrorMessage = self.lastErrorMessage;
    c.tools = self.tools;
    c.highToken = self.highToken;
    return c;
}

- (NSDictionary *)debugDictionarySanitized {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"serverId"] = self.serverId ?: @"";
    d[@"name"] = self.name ?: @"";
    d[@"type"] = (self.type == LAMCPServerTypeLocal) ? @"local" : @"remote";
    d[@"enabled"] = @(self.isEnabled);
    d[@"connectionState"] = @(self.connectionState);
    d[@"lastErrorMessage"] = self.lastErrorMessage ?: @"";
    d[@"tools"] = self.tools ?: @[];
    d[@"highToken"] = @(self.isHighToken);
    if (self.type == LAMCPServerTypeLocal) {
        d[@"command"] = self.command ?: @"";
        d[@"args"] = self.args ?: @[];
    } else {
        d[@"url"] = self.url ?: @"";
        // headers 只暴露 key 名，value 统一脱敏为 ***（永不打印密钥）
        NSMutableArray *keys = [NSMutableArray array];
        for (NSString *k in self.headers.allKeys) { [keys addObject:@{@"key": k, @"value": @"***"}]; }
        d[@"headers"] = [keys copy];
    }
    return [d copy];
}

- (NSString *)description {
    // 重写 description，避免意外打印 headers 明文
    return [NSString stringWithFormat:@"<LAMCPServer %@ name=%@ state=%ld tools=%lu>",
            self.serverId, self.name, (long)self.connectionState, (unsigned long)self.tools.count];
}

@end

#pragma mark - LAMCPManager

@interface LAMCPManager ()
// serverId -> LAMCPServer
@property (nonatomic, strong) NSMutableDictionary<NSString *, LAMCPServer *> *store;
@property (nonatomic, strong) dispatch_queue_t syncQueue;
@end

@implementation LAMCPManager

+ (instancetype)sharedManager {
    static LAMCPManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[LAMCPManager alloc] initPrivate]; });
    return s;
}

- (instancetype)initPrivate {
    if (self = [super init]) {
        _store = [NSMutableDictionary dictionary];
        _syncQueue = dispatch_queue_create("org.luminagent.mcp.sync", DISPATCH_QUEUE_SERIAL);
        NSError *e = nil;
        [self reloadWithError:&e]; // 首次加载失败则视为空配置，不抛错
    }
    return self;
}

- (instancetype)init {
    // 强制走单例，避免多实例写坏配置
    return [[self class] sharedManager];
}

#pragma mark 白名单

+ (NSSet<NSString *> *)defaultLocalCommandWhitelist {
    // 默认仅允许无副作用查询类命令（读/检索/诊断），禁止 shell/写/删/网络外发。
    // 如需扩展，必须走设置页人工审核开启，不可代码写死高危命令。
    return [NSSet setWithArray:@[
        @"mcp-fs-read",      // 受限文件读取（沙盒内、只读）
        @"mcp-docs-fetch",   // 文档抓取（只读摘要）
        @"mcp-lsp-symbols",  // 轻量符号查询（只读诊断）
        @"mcp-git-status",   // git 状态查询（只读，不含 checkout/reset）
    ]];
}

+ (BOOL)isAllowedLocalCommand:(NSString *)command {
    if (command.length == 0) { return NO; }
    return [[self defaultLocalCommandWhitelist] containsObject:command];
}

#pragma mark 增删改查

- (BOOL)fillError:(NSError **)error code:(LAMCPErrorCode)code desc:(NSString *)desc {
    if (error) {
        *error = [NSError errorWithDomain:LAMCPErrorDomain code:code
                                 userInfo:@{NSLocalizedDescriptionKey: desc ?: @"MCP 操作失败"}];
    }
    return NO;
}

- (nullable LAMCPServer *)addLocalServerWithName:(NSString *)name
                                         command:(NSString *)command
                                            args:(NSArray<NSString *> *)args
                                           error:(NSError **)error {
    if (name.length == 0 || command.length == 0) {
        [self fillError:error code:LAMCPErrorCodeInvalidArgument desc:@"local 服务 name/command 不能为空"];
        return nil;
    }
    if (![[self class] isAllowedLocalCommand:command]) {
        [self fillError:error code:LAMCPErrorCodeNotAllowed desc:@"该 local 命令不在白名单内（仅允许无副作用查询类）"];
        return nil;
    }
    __block LAMCPServer *s = nil;
    dispatch_sync(self.syncQueue, ^{
        s = [[LAMCPServer alloc] initWithName:name type:LAMCPServerTypeLocal];
        s.command = command;
        s.args = [args copy] ?: @[];
        s.connectionState = LAMCPConnectionStateUnknown;
        self.store[s.serverId] = s;
    });
    [self saveWithError:NULL];
    return s;
}

- (nullable LAMCPServer *)addRemoteServerWithName:(NSString *)name
                                              url:(NSString *)url
                                          headers:(NSDictionary<NSString *,NSString *> *)headers
                                            error:(NSError **)error {
    if (name.length == 0 || url.length == 0) {
        [self fillError:error code:LAMCPErrorCodeInvalidArgument desc:@"remote 服务 name/url 不能为空"];
        return nil;
    }
    NSURL *u = [NSURL URLWithString:url];
    NSString *scheme = u.scheme.lowercaseString;
    if (!u || (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])) {
        [self fillError:error code:LAMCPErrorCodeInvalidArgument desc:@"remote url 必须为 http/https"];
        return nil;
    }
    __block LAMCPServer *s = nil;
    dispatch_sync(self.syncQueue, ^{
        s = [[LAMCPServer alloc] initWithName:name type:LAMCPServerTypeRemote];
        s.url = url;
        s.headers = [headers copy] ?: @{};
        // 占位：不发起真实连通性检测，状态置为 Connecting，待联调时再翻转为 Connected/NeedAuth
        s.connectionState = LAMCPConnectionStateConnecting;
        self.store[s.serverId] = s;
    });
    [self saveWithError:NULL];
    return s;
}

- (BOOL)removeServerWithId:(NSString *)serverId error:(NSError **)error {
    if (serverId.length == 0) { return [self fillError:error code:LAMCPErrorCodeInvalidArgument desc:@"serverId 不能为空"]; }
    __block BOOL found = NO;
    dispatch_sync(self.syncQueue, ^{ found = (self.store[serverId] != nil); [self.store removeObjectForKey:serverId]; });
    if (!found) { return [self fillError:error code:LAMCPErrorCodeNotFound desc:@"指定的 MCP 服务不存在"]; }
    [self saveWithError:NULL];
    return YES;
}

- (nullable LAMCPServer *)serverWithId:(NSString *)serverId {
    if (serverId.length == 0) { return nil; }
    __block LAMCPServer *s = nil;
    dispatch_sync(self.syncQueue, ^{ s = [self.store[serverId] copy]; });
    return s;
}

- (NSArray<LAMCPServer *> *)listServers {
    __block NSArray *arr = nil;
    dispatch_sync(self.syncQueue, ^{ arr = [self.store.allValues copy]; });
    return [arr sortedArrayUsingComparator:^NSComparisonResult(LAMCPServer *a, LAMCPServer *b) {
        return [a.name compare:b.name];
    }];
}

- (BOOL)setEnabled:(BOOL)enabled forServerWithId:(NSString *)serverId error:(NSError **)error {
    __block LAMCPServer *s = nil;
    dispatch_sync(self.syncQueue, ^{ s = self.store[serverId]; });
    if (!s) { return [self fillError:error code:LAMCPErrorCodeNotFound desc:@"指定的 MCP 服务不存在"]; }
    dispatch_sync(self.syncQueue, ^{
        s.enabled = enabled;
        s.connectionState = enabled ? LAMCPConnectionStateUnknown : LAMCPConnectionStateDisabled;
        if (!enabled) { s.lastErrorMessage = @"已停用（保留配置）"; }
    });
    [self saveWithError:NULL];
    return YES;
}

- (BOOL)markAuthCheckedForServerWithId:(NSString *)serverId needAuth:(BOOL)needAuth error:(NSError **)error {
    __block LAMCPServer *s = nil;
    dispatch_sync(self.syncQueue, ^{ s = self.store[serverId]; });
    if (!s) { return [self fillError:error code:LAMCPErrorCodeNotFound desc:@"指定的 MCP 服务不存在"]; }
    dispatch_sync(self.syncQueue, ^{
        if (needAuth) {
            s.connectionState = LAMCPConnectionStateNeedAuth;
            s.lastErrorMessage = @"需要重新授权（401 映射），不展示 token";
        } else if (s.connectionState == LAMCPConnectionStateNeedAuth) {
            s.connectionState = LAMCPConnectionStateUnknown;
            s.lastErrorMessage = nil;
        }
    });
    [self saveWithError:NULL];
    return YES;
}

- (BOOL)logoutServerWithId:(NSString *)serverId error:(NSError **)error {
    // 本管理器只清理展示态；Keychain 中的真实 token 由 LAMCPOAuth 清除（调用方需同时调用）。
    __block LAMCPServer *s = nil;
    dispatch_sync(self.syncQueue, ^{ s = self.store[serverId]; });
    if (!s) { return [self fillError:error code:LAMCPErrorCodeNotFound desc:@"指定的 MCP 服务不存在"]; }
    dispatch_sync(self.syncQueue, ^{
        s.connectionState = s.isEnabled ? LAMCPConnectionStateUnknown : LAMCPConnectionStateDisabled;
        s.lastErrorMessage = @"已登出展示态（token 请走 LAMCPOAuth 清除）";
    });
    [self saveWithError:NULL];
    return YES;
}

- (NSArray<NSDictionary *> *)debugInfoSanitized {
    NSArray *all = [self listServers];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:all.count];
    for (LAMCPServer *s in all) { [out addObject:[s debugDictionarySanitized]]; }
    return [out copy];
}

- (BOOL)updateConnectionState:(LAMCPConnectionState)state
              forServerWithId:(NSString *)serverId
                 errorMessage:(NSString *)errorMessage
                        error:(NSError **)error {
    __block LAMCPServer *s = nil;
    dispatch_sync(self.syncQueue, ^{ s = self.store[serverId]; });
    if (!s) { return [self fillError:error code:LAMCPErrorCodeNotFound desc:@"指定的 MCP 服务不存在"]; }
    dispatch_sync(self.syncQueue, ^{
        // 停用中的服务不接受外部置为 Connected，避免可用集误注入
        if (!s.isEnabled && state == LAMCPConnectionStateConnected) {
            s.connectionState = LAMCPConnectionStateDisabled;
            s.lastErrorMessage = @"服务已停用，拒绝置为已连接";
        } else {
            s.connectionState = state;
            s.lastErrorMessage = [errorMessage copy];
        }
    });
    [self saveWithError:NULL];
    return YES;
}

- (BOOL)setTools:(NSArray<NSString *> *)tools forServerWithId:(NSString *)serverId error:(NSError **)error {
    __block LAMCPServer *s = nil;
    dispatch_sync(self.syncQueue, ^{ s = self.store[serverId]; });
    if (!s) { return [self fillError:error code:LAMCPErrorCodeNotFound desc:@"指定的 MCP 服务不存在"]; }
    dispatch_sync(self.syncQueue, ^{ s.tools = [tools copy] ?: @[]; });
    [self saveWithError:NULL];
    return YES;
}

#pragma mark 可用集

- (NSArray<NSString *> *)availableToolNamesGlobal {
    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    for (LAMCPServer *s in [self listServers]) {
        if (!s.isEnabled) { continue; }
        if (s.connectionState != LAMCPConnectionStateConnected) { continue; }
        for (NSString *t in s.tools) { if (t.length > 0) { [set addObject:t]; } }
    }
    return [[set array] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSString *> *)availableToolNamesForSessionEnabledServerIds:(NSSet<NSString *> *)sessionEnabledIds {
    NSArray *global = [self availableToolNamesGlobal];
    if (sessionEnabledIds == nil) { return global; } // nil 表示不做会话级过滤
    // 仅保留会话启用集内服务的 tools
    NSMutableDictionary<NSString *, NSString *> *toolToServer = [NSMutableDictionary dictionary];
    for (LAMCPServer *s in [self listServers]) {
        for (NSString *t in s.tools) { toolToServer[t] = s.serverId; }
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *t in global) {
        NSString *sid = toolToServer[t];
        if (sid && [sessionEnabledIds containsObject:sid]) { [out addObject:t]; }
    }
    return [out copy];
}

#pragma mark 持久化

- (BOOL)saveWithError:(NSError **)error {
    __block NSArray *all = nil;
    dispatch_sync(self.syncQueue, ^{ all = [self.store.allValues copy]; });
    NSError *archErr = nil;
    NSData *data = nil;
    // 使用旧 API 做一次性归档以保持 iOS15 兼容（仅配置快照，不涉及密钥）
    @try {
        data = [NSKeyedArchiver archivedDataWithRootObject:[all copy] requiringSecureCoding:YES error:&archErr];
    } @catch (NSException *ex) {
        archErr = [NSError errorWithDomain:LAMCPErrorDomain code:LAMCPErrorCodeInvalidArgument
                                  userInfo:@{NSLocalizedDescriptionKey: @"MCP 配置归档失败"}];
    }
    if (archErr) {
        if (error) { *error = archErr; }
        return NO;
    }
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:kLAMCPStoreKey];
    return YES;
}

- (BOOL)reloadWithError:(NSError **)error {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kLAMCPStoreKey];
    if (!data) { return YES; } // 无存档视为首次启动
    NSError *unarchErr = nil;
    NSSet *classes = [NSSet setWithArray:@[[NSArray class], [LAMCPServer class], [NSString class], [NSNumber class]]];
    NSArray *arr = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&unarchErr];
    if (unarchErr) {
        if (error) { *error = unarchErr; }
        return NO;
    }
    dispatch_sync(self.syncQueue, ^{
        [self.store removeAllObjects];
        for (LAMCPServer *s in arr) {
            if ([s isKindOfClass:[LAMCPServer class]] && s.serverId.length > 0) {
                self.store[s.serverId] = s;
            }
        }
    });
    return YES;
}

@end
