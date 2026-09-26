#ifndef LA_TRAJECTORY_STORE_H
#define LA_TRAJECTORY_STORE_H

#import <Foundation/Foundation.h>

// Trajectory 可审计日志：append-only 类型化事件流（12 类核心事件，插件可声明扩展合并）。
// 约定：LLM 历史只从本日志投影（Model-visible means logged）；
// resume/fork/replay 全基于同一流；每步标注来源插件，UI 可点查。

NS_ASSUME_NONNULL_BEGIN

// 12 类核心事件：turn 起止(2) + step 起止(2) + user/assistant 消息与 attempt(3)
// + tool call/result(2) + request 上下文(1) + session 结束种子(1) + 插件扩展(1)。
typedef NS_ENUM(NSInteger, LATrajectoryEventType) {
    LATrajectoryEventTurnStart     = 0, // turn 开始
    LATrajectoryEventTurnEnd       = 1, // turn 结束
    LATrajectoryEventStepStart     = 2, // step 开始
    LATrajectoryEventStepEnd       = 3, // step 结束
    LATrajectoryEventUserMessage   = 4, // 用户消息
    LATrajectoryEventAssistantMsg  = 5, // 助手消息
    LATrajectoryEventAttempt       = 6, // 重试 attempt（含失败重试全过程）
    LATrajectoryEventToolCall      = 7, // 工具调用
    LATrajectoryEventToolResult    = 8, // 工具结果
    LATrajectoryEventRequestCtx    = 9, // request 上下文（模型/网关/注入快照）
    LATrajectoryEventSessionSeed   = 10, // session 结束种子（回放/恢复锚点）
    LATrajectoryEventPluginExt     = 11, // 插件声明扩展事件（合并入流）
};

// 事件模型：seq（单调递增）+ type + payload + sourcePlugin（缺一不可）。
@interface LATrajectoryEvent : NSObject <NSCopying>
@property (nonatomic, assign, readonly) uint64_t seq;              // 流内序号
@property (nonatomic, assign, readonly) LATrajectoryEventType type;// 事件类型
@property (nonatomic, copy, readonly) NSDictionary *payload;       // 类型化载荷
@property (nonatomic, copy, readonly) NSString *sourcePlugin;      // 来源插件 ID
@property (nonatomic, strong, readonly) NSDate *timestamp;         // 落点时间
@property (nonatomic, copy, readonly) NSString *sessionID;         // 所属会话
- (instancetype)initWithSeq:(uint64_t)seq
                       type:(LATrajectoryEventType)type
                    payload:(NSDictionary *)payload
               sourcePlugin:(NSString *)sourcePlugin
                  sessionID:(NSString *)sessionID;
// 事件类型 ↔ 字符串（导出/回放/点查用）。
+ (NSString *)stringFromType:(LATrajectoryEventType)type;
+ (LATrajectoryEventType)typeFromString:(NSString *)string;
@end

@interface LATrajectoryStore : NSObject
// 初始化：sessionID 绑定一条流（fork 时派生新 ID，老流只读保留）。
- (instancetype)initWithSessionID:(NSString *)sessionID;
@property (nonatomic, copy, readonly) NSString *sessionID;

// 追加事件（append-only，无删除/修改接口）；返回落点事件（含 seq）。
- (LATrajectoryEvent *)appendEventOfType:(LATrajectoryEventType)type
                                 payload:(NSDictionary *)payload
                            sourcePlugin:(NSString *)sourcePlugin
                               sessionID:(nullable NSString *)sessionID;
// 插件扩展事件追加（type 固定为 PluginExt，payload 须含 extKind）。
- (nullable LATrajectoryEvent *)appendPluginEventWithKind:(NSString *)extKind
                                                 payload:(NSDictionary *)payload
                                            sourcePlugin:(NSString *)sourcePlugin;

// 查询：seq 之后事件（含 fork 继承段）；按类型过滤；按来源插件过滤。
- (NSArray<LATrajectoryEvent *> *)eventsSinceSeq:(uint64_t)seq;
- (NSArray<LATrajectoryEvent *> *)eventsOfType:(LATrajectoryEventType)type;
- (NSArray<LATrajectoryEvent *> *)eventsFromPlugin:(NSString *)sourcePlugin;
// 全文搜索（payload 描述/原文快照 substring 匹配，供回放定位）。
- (NSArray<LATrajectoryEvent *> *)search:(NSString *)keyword;

// LLM 历史投影：只从日志生成 messages 数组（role/content），保证可见即已记。
- (NSArray<NSDictionary *> *)projectModelHistory;

// resume：返回可继续的 store（同 sessionID，seq 连续）；
// fork：派生新 sessionID（继承全流为只读前缀）；
// replay：按流重演（含失败重试），逐事件回调，返 NO 即停。
- (LATrajectoryStore *)resumedStore;
- (LATrajectoryStore *)forkedStoreWithNewSessionID:(NSString *)newSessionID;
- (void)replayWithHandler:(BOOL (^)(LATrajectoryEvent *event))handler;

// 导出 JSON 数组（审计/dump 用）；事件数。
- (NSArray<NSDictionary *> *)exportJSON;
- (NSUInteger)eventCount;
@end

FOUNDATION_EXPORT NSString *const LATrajectoryErrorDomain;

NS_ASSUME_NONNULL_END

#endif /* LA_TRAJECTORY_STORE_H */
