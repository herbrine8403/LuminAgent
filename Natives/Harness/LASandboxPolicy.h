#ifndef LA_SANDBOX_POLICY_H
#define LA_SANDBOX_POLICY_H

#import <Foundation/Foundation.h>

// 沙盒 per-call 解析：显式覆盖 > 会话事件 > 部署默认。
// 文件效应仅三档：read-only / workspace-write（工作区+后端临时）/ danger-full-access。
// iOS 用 App 沙盒 + XPC helper 实现；无可用后端 fail-closed 抛错中止，禁静默裸跑，
// 并如实上报执行强度。

NS_ASSUME_NONNULL_BEGIN

// 未设定哨兵（per-call 解析时表示“本层无声明”）。
#define LA_SANDBOX_TIER_UNSET (-1)

// 文件效应三档。
typedef NS_ENUM(NSInteger, LASandboxTier) {
    LASandboxTierReadOnly    = 0, // 只读：禁一切写
    LASandboxTierWorkspace   = 1, // 工作区写：App 沙盒工作区 + 后端临时目录
    LASandboxTierDangerFull  = 2, // 全访问：绕过并审计（须签核 + 记轨迹）
};

// 单次解析结果（含审计标记与执行强度）。
@interface LASandboxResolution : NSObject
@property (nonatomic, assign) LASandboxTier tier;   // 最终档位
@property (nonatomic, copy) NSString *source;       // 来源：override/session/default
@property (nonatomic, assign) BOOL backendAvailable;// 后端是否可用
@property (nonatomic, assign) BOOL needsAudit;      // danger 档恒为 YES
@end

@interface LASandboxPolicy : NSObject
// 部署默认档（安装/远端配置下发）；XPC helper 服务名（iOS 侧执行后端标识）。
@property (nonatomic, assign) LASandboxTier deploymentDefault;
@property (nonatomic, copy, nullable) NSString *helperServiceName;
- (instancetype)initWithDeploymentDefault:(LASandboxTier)tier
                       helperServiceName:(nullable NSString *)service;
// per-call 解析：explicit > session > 部署默认（各层取 LA_SANDBOX_TIER_UNSET 表示无声明）。
- (LASandboxResolution *)resolveWithExplicitTier:(NSInteger)explicitTier
                                    sessionTier:(NSInteger)sessionTier;
// 授权执行：无可用后端需写文件时 fail-closed 抛错（error 非空），绝不静默裸跑。
- (BOOL)authorizeResolution:(LASandboxResolution *)resolution
           backendAvailable:(BOOL)available
                      error:(NSError **)error;
// 执行强度上报（UI 明示通道用中文标签）。
- (NSString *)intensityLabelForTier:(LASandboxTier)tier;
// danger 档审计载荷（来源插件 + 目标 + 原因，供 trajectory 记录）。
- (NSDictionary *)auditPayloadForTool:(NSString *)tool
                               target:(NSString *)target
                               reason:(NSString *)reason
                         sourcePlugin:(NSString *)sourcePlugin;
@end

FOUNDATION_EXPORT NSString *const LASandboxPolicyErrorDomain;
typedef NS_ENUM(NSInteger, LASandboxPolicyErrorCode) {
    LASandboxPolicyErrorNoBackend = 9001, // 无沙盒后端且需写文件（fail-closed 中止）
    LASandboxPolicyErrorTierDenied = 9002, // 档位拒绝本次写效应
};

NS_ASSUME_NONNULL_END

#endif /* LA_SANDBOX_POLICY_H */
