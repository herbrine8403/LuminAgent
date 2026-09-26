#ifndef LA_COMPACTION_H
#define LA_COMPACTION_H

/* 压缩与摘要记忆：上下文超限自动触发 + /compact 手动触发；
 * 裁剪旧工具输出但 skill 输出（neverTrim）永不裁剪；
 * 摘要正文由 Provider 回填（本组不做网络），本模块负责阈值判定与本地裁剪。 */

#import <Foundation/Foundation.h>

@class LAMessage;
@class LATodo;

/* 默认上下文上限 100k token，阈值比例 0.8，尾部保留 4 条消息 */
extern const long long LACompactionDefaultTokenLimit;
extern const double LACompactionDefaultThresholdRatio;
extern const NSUInteger LACompactionDefaultRecentKept;

@interface LACompaction : NSObject

@property (nonatomic, assign) long long tokenLimit;     /* 上下文上限 */
@property (nonatomic, assign) double thresholdRatio;    /* 触发比例 */
@property (nonatomic, assign) NSUInteger recentKept;    /* 尾部保留消息数 */

- (instancetype)init;
- (instancetype)initWithTokenLimit:(long long)tokenLimit
                    thresholdRatio:(double)ratio
                        recentKept:(NSUInteger)recentKept;

/* 是否需要压缩（含阈值判定） */
- (BOOL)needsCompactionForTokenCount:(long long)tokenCount;

/* 会话累计 token（消息 parts 求和） */
- (long long)tokenCountForMessages:(NSArray<LAMessage *> *)messages;

/* 生成压缩提示词：调用方将返回的摘要正文交 Provider 生成后调 apply（本组不做网络） */
- (NSString *)buildCompactionPromptForMessages:(NSArray<LAMessage *> *)messages
                                         todos:(NSArray<LATodo *> *)todos;

/* 应用摘要：头部插入 Summary 消息，裁剪旧工具输出（neverTrim 永不裁剪，
 * 尾部 recentKept 条原样保留）；返回裁剪后的新数组 */
- (NSArray<LAMessage *> *)applySummary:(NSString *)summary
                             toMessages:(NSArray<LAMessage *> *)messages;

/* /compact 手动入口：等价于 applySummary（摘要正文由调用方传入） */
- (NSArray<LAMessage *> *)compactManuallyWithMessages:(NSArray<LAMessage *> *)messages
                                              summary:(NSString *)summary;

@end

#endif /* LA_COMPACTION_H */
