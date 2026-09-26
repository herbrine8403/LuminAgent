#ifndef LA_SUBAGENT_BROKER_H
#define LA_SUBAGENT_BROKER_H

#import <Foundation/Foundation.h>

// 外部 Subagent 编排：远端 Claude/Codex 等统一视为 subagent 插件，
// 经注册表编排调用。双态：one-shot（一次结算）与 continuable
// （durable 会话 + 单 live 激活 + inbox 排队/转向/中断，父子仅一跳授权）。
// 能力缺失大声失败（NSError 明确报错，不静默降级）；委派全程记入 trajectory。

NS_ASSUME_NONNULL_BEGIN

// 他组类型前向声明（不重复定义 Session/Provider 类型）。
@class LATrajectoryStore;

// subagent 形态。
typedef NS_ENUM(NSInteger, LASubagentMode) {
    LASubagentModeOneShot     = 0, // 一次结算
    LASubagentModeContinuable = 1, // durable 会话，可多轮转向
};

// continuable 会话句柄：durable 会话 + 单 live 激活 + inbox。
@interface LASubagentHandle : NSObject
@property (nonatomic, copy, readonly) NSString *durableSessionID; // 持久会话 ID
@property (nonatomic, copy, readonly) NSString *pluginID;         // 承接插件
@property (nonatomic, assign) BOOL liveActive;                    // 单 live 激活位
@property (nonatomic, copy) NSArray<NSString *> *inbox;           // 排队/转向消息
- (instancetype)initWithSessionID:(NSString *)sessionID pluginID:(NSString *)pluginID;
@end

// subagent 插件协议（外部 Claude/Codex 即实现此协议的插件）。
@protocol LASubagentPlugin <NSObject>
@required
- (NSString *)pluginID;                          // 如 @"claude-remote" / @"codex-remote"
- (NSString *)displayName;                       // 中文展示名
- (NSArray<NSString *> *)capabilities;           // 能力名（如 code/review）；缺失即大声失败
- (BOOL)supportsMode:(LASubagentMode)mode;       // 是否支持某形态
// one-shot 调用：prompt + 授权 token（父子一跳），completion 回 fused 结果。
- (void)oneShotWithPrompt:(NSString *)prompt
                authToken:(NSString *)authToken
               completion:(void (^)(NSString * _Nullable fusedText, NSError * _Nullable error))completion;
// continuable：建 durable 会话 / 转向 / 中断（单 live 由 Broker 仲裁）。
- (void)spawnSessionWithPrompt:(NSString *)prompt
                     authToken:(NSString *)authToken
                    completion:(void (^)(LASubagentHandle * _Nullable handle, NSError * _Nullable error))completion;
- (void)steerSession:(LASubagentHandle *)handle
         withMessage:(NSString *)message
          completion:(void (^)(NSString * _Nullable fusedText, NSError * _Nullable error))completion;
- (void)interruptSession:(LASubagentHandle *)handle
              completion:(void (^)(BOOL ok, NSError * _Nullable error))completion;
@end

@interface LASubagentBroker : NSObject
- (instancetype)initWithTrajectory:(nullable LATrajectoryStore *)trajectory;
// 注册/注销 subagent 插件。
- (void)registerPlugin:(id<LASubagentPlugin>)plugin;
- (void)unregisterPluginWithID:(NSString *)pluginID;
- (nullable id<LASubagentPlugin>)pluginWithID:(NSString *)pluginID;
// 父子一跳授权：仅允许 parentDepth+1（否则大声失败）；返回单次 token。
- (nullable NSString *)authorizeChildOfParentSession:(NSString *)parentSessionID
                                        parentDepth:(NSInteger)parentDepth
                                         childDepth:(NSInteger)childDepth
                                              error:(NSError **)error;
// one-shot 委派（含能力检查 + trajectory 记录）。
- (void)invokeOneShotWithPluginID:(NSString *)pluginID
                           prompt:(NSString *)prompt
                      requireCaps:(nullable NSArray<NSString *> *)caps
                        sessionID:(NSString *)sessionID
                       completion:(void (^)(NSString * _Nullable fusedText, NSError * _Nullable error))completion;
// continuable：建会话（仲裁单 live：同插件旧 live 自动挂起）/ inbox 排队 / 转向 / 中断。
- (void)spawnContinuableWithPluginID:(NSString *)pluginID
                              prompt:(NSString *)prompt
                         requireCaps:(nullable NSArray<NSString *> *)caps
                           sessionID:(NSString *)sessionID
                          completion:(void (^)(LASubagentHandle * _Nullable handle, NSError * _Nullable error))completion;
- (void)queueInboxMessage:(NSString *)message forHandle:(LASubagentHandle *)handle;
- (void)steerHandle:(LASubagentHandle *)handle
        withMessage:(NSString *)message
         completion:(void (^)(NSString * _Nullable fusedText, NSError * _Nullable error))completion;
- (void)interruptHandle:(LASubagentHandle *)handle
             completion:(void (^)(BOOL ok, NSError * _Nullable error))completion;
@end

FOUNDATION_EXPORT NSString *const LASubagentBrokerErrorDomain;
typedef NS_ENUM(NSInteger, LASubagentBrokerErrorCode) {
    LASubagentBrokerErrorPluginNotFound   = 8001, // 未注册的 subagent 插件
    LASubagentBrokerErrorCapabilityMissing = 8002, // 能力缺失（大声失败）
    LASubagentBrokerErrorModeUnsupported  = 8003, // 形态不支持
    LASubagentBrokerErrorDepthExceeded    = 8004, // 父子超一跳
    LASubagentBrokerErrorNoLiveActive     = 8005, // 无 live 激活可转向
};

NS_ASSUME_NONNULL_END

#endif /* LA_SUBAGENT_BROKER_H */
