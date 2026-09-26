#ifndef LA_AGENT_LOOP_H
#define LA_AGENT_LOOP_H

#import <Foundation/Foundation.h>

// 可替换 AgentLoop 协议与四模式实现（Standard/Code/Minimal/Creator）。
// 约定：Loop 只消费他组头文件契约（Session/Provider/Tools/MCP），此处一律前向声明，
// 不重复定义 Session/Provider 类型；换 loop 不改壳（经 LALoopFactory 整行替换）。

NS_ASSUME_NONNULL_BEGIN

// 他组类型前向声明（本文件不定义、不导入他组头）。
@class LATrajectoryStore;
@class LAProviderGateway;
@class LARequestOptions;
@class LASubagentBroker;
@class LASandboxPolicy;
@protocol LAPermissionAsking;

// Loop 四模式（与 harness-plugins 规格一致）。
typedef NS_ENUM(NSInteger, LALoopKind) {
    LALoopKindStandard = 0, // 全工具 ReAct：prompt→tools→verify
    LALoopKindCode     = 1, // 组合规划器 + 远端网关执行（本机不 eval）
    LALoopKindMinimal  = 2, // 仅 editor + 受限 shell 声明（可复现基准）
    LALoopKindCreator  = 3, // 插件巡检 + 生成向导
};

// Loop 运行上下文：壳只组装此对象，执行策略全在 Loop 插件内。
@interface LALoopContext : NSObject
@property (nonatomic, copy) NSString *sessionID;      // 所属会话
@property (nonatomic, copy) NSString *presetID;       // Preset 隔离域
@property (nonatomic, copy) NSString *modelIdentifier;// "provider/model" 寻址
@property (nonatomic, assign) NSInteger stepBudget;   // steps 上限（<=0 视为默认 20）
@property (nonatomic, copy, nullable) NSString *taskPrompt; // 本轮任务描述
@property (nonatomic, strong, nullable) LATrajectoryStore *trajectory; // 同流日志
@property (nonatomic, strong, nullable) LASandboxPolicy *sandbox;      // 沙盒声明
@property (nonatomic, strong, nullable) LASubagentBroker *subagents;   // 外部编排
@end

// Loop 运行结果。
@interface LALoopResult : NSObject
@property (nonatomic, assign) BOOL finished;          // 是否正常结束（非超限/中断）
@property (nonatomic, assign) NSInteger stepsUsed;    // 实际消耗 steps
@property (nonatomic, copy, nullable) NSString *summary; // 中文小结
@property (nonatomic, strong, nullable) NSError *error;  // 失败原因（可空）
+ (instancetype)resultWithFinished:(BOOL)finished steps:(NSInteger)steps summary:(nullable NSString *)summary error:(nullable NSError *)error;
@end

// 可替换 Loop 协议：一切执行差异收敛于此，壳只依赖协议。
@protocol LAAgentLoop <NSObject>
@required
// 本插件归属 Loop 种类与插件 ID（记入 trajectory 来源标注）。
- (LALoopKind)loopKind;
- (NSString *)loopPluginID;
// 本模式声明可用工具名（Minimal 仅两类，供基准可复现审计）。
- (NSArray<NSString *> *)supportedToolNames;
// 运行一轮（同步骨架：远端调用由实现方经 Provider 网关异步桥接，steps 受 context.stepBudget 约束）。
- (LALoopResult *)runWithContext:(LALoopContext *)context;
@end

// Loop 工厂：注册替换只换映射表，不改壳。
@interface LALoopFactory : NSObject
// 注册/覆盖某 Kind 的实现类（须遵守 LAAgentLoop）；传 nil 恢复内置默认。
+ (void)registerLoopClass:(nullable Class)cls forKind:(LALoopKind)kind;
// 取某 Kind 的 Loop 实例（未注册则返回内置默认）。
+ (id<LAAgentLoop>)loopForKind:(LALoopKind)kind;
// 当前可用 Kind 列表（NSNumber 包装 LALoopKind）。
+ (NSArray<NSNumber *> *)availableKinds;
@end

// 四模式内置实现（默认注册，可被 registerLoopClass 整行替换）。
@interface LAStandardLoop : NSObject <LAAgentLoop>
@end

@interface LACodeLoop : NSObject <LAAgentLoop>
// 远端网关标识（SSH/容器 HTTP 由 Tools 组实现，此处仅存标识透传）。
@property (nonatomic, copy, nullable) NSString *remoteGatewayID;
@end

@interface LAMinimalLoop : NSObject <LAAgentLoop>
@end

@interface LACreatorLoop : NSObject <LAAgentLoop>
@end

// Loop 错误域与错误码。
FOUNDATION_EXPORT NSString *const LALoopErrorDomain;
typedef NS_ENUM(NSInteger, LALoopErrorCode) {
    LALoopErrorStepBudgetExceeded = 7001, // steps 超限（含 verify 未通过）
    LALoopErrorVerifyFailed       = 7002, // verify 环节失败
    LALoopErrorRemoteUnavailable  = 7003, // Code 远端网关不可用（fail-closed）
    LALoopErrorToolNotAllowed     = 7004, // 工具不在本模式声明内
};

NS_ASSUME_NONNULL_END

#endif /* LA_AGENT_LOOP_H */
