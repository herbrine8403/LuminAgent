#import "LAPermissionCenter.h"
#import "LAErrors.h"
#include <fnmatch.h>

/* 权限中心实现：fnmatch glob（系统 POSIX，非第三方）+ 默认策略表 + 三连计数 */

@implementation LAPermissionRule

+ (instancetype)ruleWithToolPattern:(NSString *)toolPattern
                           pathGlob:(NSString *)pathGlob
                      commandPrefix:(NSString *)commandPrefix
                           decision:(LAPermissionDecision)decision {
    LAPermissionRule *rule = [[LAPermissionRule alloc] init];
    rule.toolPattern = [toolPattern copy] ?: @"";
    rule.pathGlob = [pathGlob copy];
    rule.commandPrefix = [commandPrefix copy];
    rule.decision = decision;
    return rule;
}

- (id)copyWithZone:(NSZone *)zone {
    LAPermissionRule *copy = [[[self class] allocWithZone:zone] init];
    copy.toolPattern = [self.toolPattern copy];
    copy.pathGlob = [self.pathGlob copy];
    copy.commandPrefix = [self.commandPrefix copy];
    copy.decision = self.decision;
    return copy;
}

/* glob 匹配：pattern 为空视为通配 */
+ (BOOL)glob:(NSString *)pattern matches:(NSString *)value {
    if (pattern == nil || pattern.length == 0) {
        return YES;
    }
    if (value == nil) {
        return NO;
    }
    return fnmatch([pattern UTF8String], [value UTF8String], 0) == 0;
}

- (BOOL)matchesTool:(NSString *)tool path:(NSString *)path command:(NSString *)command {
    if (![[self class] glob:self.toolPattern matches:tool]) {
        return NO;
    }
    if (self.pathGlob.length > 0 && ![[self class] glob:self.pathGlob matches:path]) {
        return NO;
    }
    if (self.commandPrefix.length > 0) {
        if (command == nil || ![command hasPrefix:self.commandPrefix]) {
            return NO;
        }
    }
    return YES;
}

@end

@implementation LAPermissionCenter {
    NSMutableArray<LAPermissionRule *> *_rules;
    /* doom_loop 指纹：tool + arguments 连续命中计数 */
    NSString *_lastFingerprint;
    NSInteger _repeatCount;
}

- (instancetype)initWithSandboxRoot:(NSString *)sandboxRoot {
    self = [super init];
    if (self) {
        _sandboxRoot = [sandboxRoot copy];
        _rules = [NSMutableArray array];
    }
    return self;
}

- (instancetype)init {
    return [self initWithSandboxRoot:nil];
}

- (void)addRule:(LAPermissionRule *)rule {
    if (rule) {
        [_rules addObject:rule];
    }
}

- (void)removeAllRules {
    [_rules removeAllObjects];
}

- (NSArray<LAPermissionRule *> *)allRules {
    return [_rules copy];
}

+ (NSArray<NSString *> *)sensitivePathGlobs {
    /* Keychain / provisioning / 私钥默认 ask */
    return @[
        @"*.keychain*",
        @"*Keychain*",
        @"*.mobileprovision*",
        @"*.pem",
        @"*.p12",
        @"*.pfx",
        @"*id_rsa*",
        @"*id_ed25519*",
        @"*.key",
        @"*Secrets*",
    ];
}

/* 路径是否落在沙盒根内 */
- (BOOL)isPathOutsideSandbox:(NSString *)path {
    if (path == nil || path.length == 0) {
        return NO;
    }
    if (self.sandboxRoot == nil || self.sandboxRoot.length == 0) {
        return YES;
    }
    NSString *root = [self.sandboxRoot stringByStandardizingPath];
    NSString *target = [path stringByStandardizingPath];
    if ([target isEqualToString:root]) {
        return NO;
    }
    return ![target hasPrefix:[root stringByAppendingString:@"/"]];
}

/* 是否命中敏感路径 */
- (BOOL)isSensitivePath:(NSString *)path {
    if (path == nil) {
        return NO;
    }
    for (NSString *glob in [[self class] sensitivePathGlobs]) {
        if (fnmatch([glob UTF8String], [path UTF8String], 0) == 0) {
            return YES;
        }
        /* 文件名维度再匹配一次（全路径 glob 漏网时兜底） */
        NSString *fileName = [path lastPathComponent];
        if (fnmatch([glob UTF8String], [fileName UTF8String], 0) == 0) {
            return YES;
        }
    }
    return NO;
}

/* 默认策略：只读工具 allow，高危/外联 ask，无规则兜底 ask */
- (LAPermissionDecision)defaultDecisionForTool:(NSString *)tool {
    NSString *lower = [[tool lowercaseString] stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([lower isEqualToString:@"read"] ||
        [lower isEqualToString:@"glob"] ||
        [lower isEqualToString:@"grep"] ||
        [lower isEqualToString:@"list"]) {
        return LAPermissionDecisionAllow;
    }
    return LAPermissionDecisionAsk;
}

/* LAPermissionAsking 同步快路径：仅走规则/沙盒/敏感预检，不弹卡 */
- (LAPermissionDecision)askPermission:(LAPermissionRequest *)request {
    return [self decisionForTool:request.toolName path:request.targetPath command:nil];
}

- (LAPermissionDecision)decisionForTool:(NSString *)tool
                                   path:(NSString *)path
                                command:(NSString *)command {
    NSString *safeTool = tool ?: @"";
    /* 越界一律 ask（覆盖 allow 规则） */
    if ([self isPathOutsideSandbox:path]) {
        return LAPermissionDecisionAsk;
    }
    /* 规则倒序匹配，后加优先 */
    for (NSInteger i = (NSInteger)_rules.count - 1; i >= 0; i--) {
        LAPermissionRule *rule = _rules[(NSUInteger)i];
        if ([rule matchesTool:safeTool path:path command:command]) {
            /* 越界已在上拦截；敏感路径的 allow 规则降级为 ask */
            if (rule.decision == LAPermissionDecisionAllow && [self isSensitivePath:path]) {
                return LAPermissionDecisionAsk;
            }
            return rule.decision;
        }
    }
    /* 敏感路径默认 ask */
    if ([self isSensitivePath:path]) {
        return LAPermissionDecisionAsk;
    }
    return [self defaultDecisionForTool:safeTool];
}

- (void)requestDecisionForTool:(NSString *)tool
                          path:(NSString *)path
                       command:(NSString *)command
                    completion:(void (^)(LAPermissionDecision decision))completion {
    LAPermissionDecision fast = [self decisionForTool:tool path:path command:command];
    if (fast != LAPermissionDecisionAsk) {
        if (completion) {
            completion(fast);
        }
        return;
    }
    id<LAPermissionCenterDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(permissionCenter:needsDecisionForTool:path:command:completion:)]) {
        [delegate permissionCenter:self needsDecisionForTool:tool ?: @""
                              path:path command:command completion:^(LAPermissionDecision decision) {
            if (decision == LAPermissionDecisionDeny) {
                [self notifyDenyForTool:tool ?: @"" reason:@"用户拒绝权限确认"];
            }
            if (completion) {
                completion(decision);
            }
        }];
    } else {
        /* 无 UI 代理时 Ask 视为拒绝并记录取消事件 */
        [self notifyDenyForTool:tool ?: @"" reason:@"无确认通道，默认拒绝"];
        if (completion) {
            completion(LAPermissionDecisionDeny);
        }
    }
}

- (void)notifyDenyForTool:(NSString *)tool reason:(NSString *)reason {
    id<LAPermissionCenterDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(permissionCenter:didDenyTool:reason:)]) {
        [delegate permissionCenter:self didDenyTool:tool reason:reason];
    }
}

#pragma mark - doom_loop 三连拦截

- (NSString *)fingerprintForTool:(NSString *)tool arguments:(NSString *)argumentsJSON {
    return [NSString stringWithFormat:@"%@\n%@", tool ?: @"", argumentsJSON ?: @""];
}

- (void)noteToolCallWithTool:(NSString *)tool arguments:(NSString *)argumentsJSON {
    NSString *fingerprint = [self fingerprintForTool:tool arguments:argumentsJSON];
    if ([fingerprint isEqualToString:_lastFingerprint]) {
        _repeatCount++;
    } else {
        _lastFingerprint = [fingerprint copy];
        _repeatCount = 1;
    }
}

- (BOOL)shouldInterveneForTool:(NSString *)tool arguments:(NSString *)argumentsJSON {
    NSString *fingerprint = [self fingerprintForTool:tool arguments:argumentsJSON];
    if ([fingerprint isEqualToString:_lastFingerprint] && _repeatCount >= 3) {
        _repeatCount = 0;
        id<LAPermissionCenterDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(permissionCenter:didTriggerDoomLoopForTool:arguments:)]) {
            [delegate permissionCenter:self didTriggerDoomLoopForTool:tool ?: @""
                             arguments:argumentsJSON ?: @""];
        }
        return YES;
    }
    return NO;
}

- (void)resetDoomLoopState {
    _lastFingerprint = nil;
    _repeatCount = 0;
}

@end
