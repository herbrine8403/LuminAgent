#ifndef LAUSAGESTATS_H
#define LAUSAGESTATS_H

/* 用量与成本统计占位。
 * 约定：按会话与全局统计 tokens（input/output/cache）与费用；
 * Zen 免费档一律记 0；/stats 输出分模型/分工具/分项目耗时耗 token 矩阵；
 * 超预算告警并建议暂停高耗调用（本文件只做阈值判断与文案，不做真实拦截）。
 * 中文注释；可失败接口均使用 NSError**；纯本地计算，无网络。 */

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const LAUsageStatsErrorDomain;
typedef NS_ENUM(NSInteger, LAUsageStatsErrorCode) {
    LAUsageStatsErrorCodeInvalidArgument = 4001, /* 参数非法 */
};

/* 单条用量记录（append-only，调用方每次模型/工具调用后记一条） */
@interface LAUsageRecord : NSObject <NSSecureCoding, NSCopying>
@property (nonatomic, copy) NSString *sessionId;  /* 所属会话 */
@property (nonatomic, copy) NSString *projectId;  /* 所属项目（按项目对账） */
@property (nonatomic, copy) NSString *model;      /* 模型名，如 zen-big-pickle（免费档记 0） */
@property (nonatomic, copy) NSString *tool;       /* 工具名，如 mcp_search:query / read（可为空表示纯对话） */
@property (nonatomic, assign) long long inputTokens;
@property (nonatomic, assign) long long outputTokens;
@property (nonatomic, assign) long long cacheTokens; /* 缓存命中 tokens（单独列，不计费或按折扣由调用方折算后传入 cost） */
@property (nonatomic, assign) double cost;           /* 本条费用（货币单位由上层约定；免费档强制 0） */
@property (nonatomic, assign) double latencySeconds; /* 本条耗时（秒） */
@property (nonatomic, strong) NSDate *createdAt;
@end

/* 聚合行：/stats 矩阵的一行 */
@interface LAUsageMatrixRow : NSObject
@property (nonatomic, copy) NSString *key; /* 维度值：模型名 / 工具名 / 项目名 */
@property (nonatomic, assign) long long inputTokens;
@property (nonatomic, assign) long long outputTokens;
@property (nonatomic, assign) long long cacheTokens;
@property (nonatomic, assign) double cost;
@property (nonatomic, assign) double latencySeconds;
@property (nonatomic, assign) NSUInteger calls; /* 调用次数 */
@end

/* 超预算回调：reason 仅含维度与阈值，不含任何密钥 */
typedef void (^LAUsageBudgetHandler)(NSString *scopeKey, double currentCost, double budgetLimit);

@interface LAUsageStats : NSObject

+ (instancetype)sharedStats;

/* 免费名单：Zen 免费档（与任务 3.3 对齐）；名单内模型 cost 强制记 0 */
+ (NSSet<NSString *> *)freeModelNames;
+ (BOOL)isFreeModel:(NSString *)model;

/* 记录一条用量（cost 若与免费名单冲突则强制归 0；tokens 负值拒绝） */
- (BOOL)recordUsageForSession:(NSString *)sessionId
                      project:(NSString *)projectId
                        model:(NSString *)model
                         tool:(nullable NSString *)tool
                  inputTokens:(long long)inputTokens
                 outputTokens:(long long)outputTokens
                  cacheTokens:(long long)cacheTokens
                         cost:(double)cost
              latencySeconds:(double)latencySeconds
                       error:(NSError **)error;

/* 会话级 / 全局聚合（tokens + 费用，返回字典：input/output/cache/cost/calls/latency） */
- (NSDictionary *)statsForSession:(NSString *)sessionId;
- (NSDictionary *)globalStats;

/* /stats 矩阵：分模型 / 分工具 / 分项目（按 cost 降序） */
- (NSArray<LAUsageMatrixRow *> *)matrixByModel;
- (NSArray<LAUsageMatrixRow *> *)matrixByTool;
- (NSArray<LAUsageMatrixRow *> *)matrixByProject;
/* 按会话查上周（近 7 天）矩阵：复用 matrixBy*，但先按时间过滤 */
- (NSArray<LAUsageMatrixRow *> *)matrixByModelForSession:(NSString *)sessionId sinceLastWeek:(BOOL)lastWeekOnly;

/* /stats 文案：本会话 + 累计费用及模型明细（纯文本，供命令层直接展示） */
- (NSString *)formattedStatsStringForSession:(nullable NSString *)sessionId;

/* 预算：全局预算上限（<=0 表示不限）；超预算告警阈值比例（默认 0.8 预警，1.0 熔断建议） */
@property (nonatomic, assign) double budgetLimit;
@property (nonatomic, assign) double warningRatio;
@property (nonatomic, copy, nullable) LAUsageBudgetHandler onBudgetWarning;
@property (nonatomic, copy, nullable) LAUsageBudgetHandler onBudgetExceeded;
/* 检查预算：返回 YES 表示已超限（调用方应暂停高耗调用）；预警/超限分别触发对应回调 */
- (BOOL)checkBudgetWithCurrentCost:(double *)outCost;
/* 清空全部记录（测试/重置用） */
- (void)resetAll;

@end

#endif /* LAUSAGESTATS_H */
