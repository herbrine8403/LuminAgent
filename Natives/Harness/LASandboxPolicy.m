#import "LASandboxPolicy.h"

NSString *const LASandboxPolicyErrorDomain = @"com.luminagent.harness.sandbox";

@implementation LASandboxResolution
@end

@implementation LASandboxPolicy
- (instancetype)initWithDeploymentDefault:(LASandboxTier)tier helperServiceName:(nullable NSString *)service {
    if (self = [super init]) {
        _deploymentDefault = tier;
        _helperServiceName = [service copy];
    }
    return self;
}

- (LASandboxResolution *)resolveWithExplicitTier:(NSInteger)explicitTier sessionTier:(NSInteger)sessionTier {
    LASandboxResolution *r = [[LASandboxResolution alloc] init];
    // 优先级：显式覆盖 > 会话事件 > 部署默认。
    if (explicitTier != LA_SANDBOX_TIER_UNSET) {
        r.tier = (LASandboxTier)explicitTier;
        r.source = @"override";
    } else if (sessionTier != LA_SANDBOX_TIER_UNSET) {
        r.tier = (LASandboxTier)sessionTier;
        r.source = @"session";
    } else {
        r.tier = self.deploymentDefault;
        r.source = @"default";
    }
    r.needsAudit = (r.tier == LASandboxTierDangerFull);
    r.backendAvailable = YES; // 实际可用性由 authorize 调用方传入后端探针结果
    return r;
}

- (BOOL)authorizeResolution:(LASandboxResolution *)resolution
           backendAvailable:(BOOL)available
                      error:(NSError **)error {
    resolution.backendAvailable = available;
    // 只读永可：无后端也可读（App 沙盒内读）。
    if (resolution.tier == LASandboxTierReadOnly) return YES;
    // 需写而无后端：fail-closed 中止，不降级裸执行。
    if (!available) {
        if (error) {
            *error = [NSError errorWithDomain:LASandboxPolicyErrorDomain
                                         code:LASandboxPolicyErrorNoBackend
                                     userInfo:@{NSLocalizedDescriptionKey: @"沙盒后端不可用，已中止写文件（未降级裸执行）"}];
        }
        return NO;
    }
    return YES;
}

- (NSString *)intensityLabelForTier:(LASandboxTier)tier {
    switch (tier) {
        case LASandboxTierReadOnly: return @"只读（无文件效应）";
        case LASandboxTierWorkspace: return @"工作区写（App 沙盒 + 后端临时）";
        case LASandboxTierDangerFull: return @"全访问（已审计，请确认签核）";
    }
    return @"未知";
}

- (NSDictionary *)auditPayloadForTool:(NSString *)tool
                               target:(NSString *)target
                               reason:(NSString *)reason
                         sourcePlugin:(NSString *)sourcePlugin {
    return @{
        @"tool": tool ?: @"",
        @"target": target ?: @"",
        @"reason": reason ?: @"",
        @"sourcePlugin": sourcePlugin ?: @"unknown",
        @"helper": self.helperServiceName ?: @"app-sandbox",
        @"tier": @"danger-full-access",
    };
}
@end
