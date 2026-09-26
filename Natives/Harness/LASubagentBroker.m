#import "LASubagentBroker.h"
#import "LATrajectoryStore.h"

NSString *const LASubagentBrokerErrorDomain = @"com.luminagent.harness.subagent";

@implementation LASubagentHandle
- (instancetype)initWithSessionID:(NSString *)sessionID pluginID:(NSString *)pluginID {
    if (self = [super init]) {
        _durableSessionID = [sessionID copy] ?: @"";
        _pluginID = [pluginID copy] ?: @"";
        _liveActive = YES;
        _inbox = @[];
    }
    return self;
}
@end

@interface LASubagentBroker ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, id<LASubagentPlugin>> *plugins;
@property (nonatomic, strong) NSMutableDictionary<NSString *, LASubagentHandle *> *liveByPlugin;
@property (nonatomic, weak, nullable) LATrajectoryStore *trajectory;
@property (nonatomic, strong) NSLock *lock;
@end

@implementation LASubagentBroker
- (instancetype)initWithTrajectory:(nullable LATrajectoryStore *)trajectory {
    if (self = [super init]) {
        _plugins = [NSMutableDictionary dictionary];
        _liveByPlugin = [NSMutableDictionary dictionary];
        _trajectory = trajectory;
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)registerPlugin:(id<LASubagentPlugin>)plugin {
    if (!plugin.pluginID.length) return;
    [self.lock lock];
    self.plugins[plugin.pluginID] = plugin;
    [self.lock unlock];
}
- (void)unregisterPluginWithID:(NSString *)pluginID {
    [self.lock lock];
    [self.plugins removeObjectForKey:pluginID ?: @""];
    [self.lock unlock];
}
- (nullable id<LASubagentPlugin>)pluginWithID:(NSString *)pluginID {
    [self.lock lock];
    id<LASubagentPlugin> p = self.plugins[pluginID ?: @""];
    [self.lock unlock];
    return p;
}

- (NSError *)err:(LASubagentBrokerErrorCode)code desc:(NSString *)desc {
    return [NSError errorWithDomain:LASubagentBrokerErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: desc}];
}

// 能力缺失大声失败：requireCaps 任一不在 capabilities 即报错返回。
- (nullable NSError *)checkCaps:(nullable NSArray<NSString *> *)caps ofPlugin:(id<LASubagentPlugin>)plugin {
    if (!caps.count) return nil;
    NSSet *have = [NSSet setWithArray:plugin.capabilities ?: @[]];
    for (NSString *c in caps) {
        if (![have containsObject:c]) {
            return [self err:LASubagentBrokerErrorCapabilityMissing desc:[NSString stringWithFormat:@"插件 %@ 缺失能力 %@（已大声失败，未降级）", plugin.pluginID, c]];
        }
    }
    return nil;
}

- (nullable NSString *)authorizeChildOfParentSession:(NSString *)parentSessionID
                                        parentDepth:(NSInteger)parentDepth
                                         childDepth:(NSInteger)childDepth
                                              error:(NSError **)error {
    // 父子仅一跳：childDepth 必须 == parentDepth + 1。
    if (childDepth != parentDepth + 1) {
        if (error) *error = [self err:LASubagentBrokerErrorDepthExceeded desc:@"subagent 只允许父子一跳授权（层级越界）"];
        return nil;
    }
    return [NSString stringWithFormat:@"%@:%ld→%ld", parentSessionID ?: @"", (long)parentDepth, (long)childDepth];
}

- (void)invokeOneShotWithPluginID:(NSString *)pluginID
                           prompt:(NSString *)prompt
                      requireCaps:(nullable NSArray<NSString *> *)caps
                        sessionID:(NSString *)sessionID
                       completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    id<LASubagentPlugin> p = [self pluginWithID:pluginID];
    if (!p) { if (completion) completion(nil, [self err:LASubagentBrokerErrorPluginNotFound desc:@"未注册的 subagent 插件"]); return; }
    NSError *capErr = [self checkCaps:caps ofPlugin:p];
    if (capErr) { if (completion) completion(nil, capErr); return; }
    if (![p supportsMode:LASubagentModeOneShot]) { if (completion) completion(nil, [self err:LASubagentBrokerErrorModeUnsupported desc:@"该插件不支持 one-shot"]); return; }
    [self.trajectory appendEventOfType:LATrajectoryEventToolCall payload:@{@"subagent": pluginID, @"mode": @"one-shot", @"prompt": prompt ?: @""} sourcePlugin:pluginID sessionID:sessionID];
    NSString *token = [NSString stringWithFormat:@"oneshot:%@", sessionID ?: @""];
    [p oneShotWithPrompt:prompt ?: @"" authToken:token completion:^(NSString *fused, NSError *err) {
        [self.trajectory appendEventOfType:LATrajectoryEventToolResult payload:@{@"subagent": pluginID, @"ok": @(err == nil)} sourcePlugin:pluginID sessionID:sessionID];
        if (completion) completion(fused, err);
    }];
}

- (void)spawnContinuableWithPluginID:(NSString *)pluginID
                              prompt:(NSString *)prompt
                         requireCaps:(nullable NSArray<NSString *> *)caps
                           sessionID:(NSString *)sessionID
                          completion:(void (^)(LASubagentHandle * _Nullable, NSError * _Nullable))completion {
    id<LASubagentPlugin> p = [self pluginWithID:pluginID];
    if (!p) { if (completion) completion(nil, [self err:LASubagentBrokerErrorPluginNotFound desc:@"未注册的 subagent 插件"]); return; }
    NSError *capErr = [self checkCaps:caps ofPlugin:p];
    if (capErr) { if (completion) completion(nil, capErr); return; }
    if (![p supportsMode:LASubagentModeContinuable]) { if (completion) completion(nil, [self err:LASubagentBrokerErrorModeUnsupported desc:@"该插件不支持 continuable"]); return; }
    [self.trajectory appendEventOfType:LATrajectoryEventToolCall payload:@{@"subagent": pluginID, @"mode": @"continuable-spawn"} sourcePlugin:pluginID sessionID:sessionID];
    NSString *token = [NSString stringWithFormat:@"continuable:%@", sessionID ?: @""];
    [p spawnSessionWithPrompt:prompt ?: @"" authToken:token completion:^(LASubagentHandle *handle, NSError *err) {
        if (!err && handle) {
            // 单 live 仲裁：同插件旧 live 自动挂起（liveActive=NO），新会话独占。
            [self.lock lock];
            LASubagentHandle *old = self.liveByPlugin[pluginID];
            if (old && old != handle) old.liveActive = NO;
            handle.liveActive = YES;
            self.liveByPlugin[pluginID] = handle;
            [self.lock unlock];
        }
        [self.trajectory appendEventOfType:LATrajectoryEventToolResult payload:@{@"subagent": pluginID, @"ok": @(err == nil)} sourcePlugin:pluginID sessionID:sessionID];
        if (completion) completion(handle, err);
    }];
}

- (void)queueInboxMessage:(NSString *)message forHandle:(LASubagentHandle *)handle {
    // inbox 排队：非 live 也可排队，激活后按序转向消费。
    handle.inbox = [handle.inbox arrayByAddingObject:message ?: @""];
    [self.trajectory appendEventOfType:LATrajectoryEventPluginExt payload:@{@"extKind": @"inbox-queue", @"durable": handle.durableSessionID} sourcePlugin:handle.pluginID sessionID:handle.durableSessionID];
}

- (void)steerHandle:(LASubagentHandle *)handle
        withMessage:(NSString *)message
         completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    if (!handle.liveActive) { if (completion) completion(nil, [self err:LASubagentBrokerErrorNoLiveActive desc:@"该会话无 live 激活，不可转向（先排队或重激活）"]); return; }
    id<LASubagentPlugin> p = [self pluginWithID:handle.pluginID];
    if (!p) { if (completion) completion(nil, [self err:LASubagentBrokerErrorPluginNotFound desc:@"未注册的 subagent 插件"]); return; }
    [p steerSession:handle withMessage:message ?: @"" completion:^(NSString *fused, NSError *err) {
        [self.trajectory appendEventOfType:LATrajectoryEventToolResult payload:@{@"subagent": handle.pluginID, @"phase": @"steer", @"ok": @(err == nil)} sourcePlugin:handle.pluginID sessionID:handle.durableSessionID];
        if (completion) completion(fused, err);
    }];
}

- (void)interruptHandle:(LASubagentHandle *)handle
             completion:(void (^)(BOOL, NSError * _Nullable))completion {
    id<LASubagentPlugin> p = [self pluginWithID:handle.pluginID];
    if (!p) { if (completion) completion(NO, [self err:LASubagentBrokerErrorPluginNotFound desc:@"未注册的 subagent 插件"]); return; }
    [p interruptSession:handle completion:^(BOOL ok, NSError *err) {
        if (ok) {
            handle.liveActive = NO;
            [self.lock lock];
            if (self.liveByPlugin[handle.pluginID] == handle) [self.liveByPlugin removeObjectForKey:handle.pluginID];
            [self.lock unlock];
        }
        [self.trajectory appendEventOfType:LATrajectoryEventPluginExt payload:@{@"extKind": @"interrupt", @"ok": @(ok)} sourcePlugin:handle.pluginID sessionID:handle.durableSessionID];
        if (completion) completion(ok, err);
    }];
}
@end
