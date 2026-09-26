#ifndef LA_AGENT_H
#define LA_AGENT_H

/* 双主 Agent 与子 Agent：Build（全工具，默认）/ Plan（只读规划）双主，
 * General（多步）/ Explore（只读检索）子代理；
 * 支持 Tab 与 @mention 切换，subagent_depth 上限约束。 */

#import <Foundation/Foundation.h>

/* 代理种类 */
typedef NS_ENUM(NSInteger, LAAgentKind) {
    LAAgentKindBuild,   /* 主：全工具，默认 */
    LAAgentKindPlan,    /* 主：只读规划，write/edit/bash 默认拒绝 */
    LAAgentKindGeneral, /* 子：多步通用，可写（受权限中心约束） */
    LAAgentKindExplore, /* 子：只读检索，edit/write/bash 拒绝 */
};

/* 子代理嵌套层数上限（根为 0，超过则拒绝派生） */
extern const NSInteger kLAMaxSubagentDepth;

/* @mention 名称 */
extern NSString * const LAAgentMentionBuild;
extern NSString * const LAAgentMentionPlan;
extern NSString * const LAAgentMentionGeneral;
extern NSString * const LAAgentMentionExplore;

@interface LAAgent : NSObject

@property (nonatomic, assign, readonly) LAAgentKind kind;  /* 种类 */
@property (nonatomic, assign, readonly) NSInteger depth;   /* 嵌套深度（根为 0） */
@property (nonatomic, copy, readonly) NSString *sessionID; /* 归属会话，可空 */

/* 子代理判定：General/Explore 为 YES */
- (BOOL)isSubagent;

/* 展示名：build/plan/general/explore */
- (NSString *)name;

/* 以种类与深度构造；depth 超限经 error 回传 nil */
- (instancetype)initWithKind:(LAAgentKind)kind
                       depth:(NSInteger)depth
                   sessionID:(NSString *)sessionID
                       error:(NSError **)error;

/* 工具准入（模式级粗筛，细则仍由权限中心裁决）：
 * Plan 主代理拒绝 write/edit/bash；Explore 拒绝 edit/write/bash；
 * 拒绝时经 error 回传取消说明并返回 NO。 */
- (BOOL)canUseTool:(NSString *)toolName error:(NSError **)error;

/* 派生子代理：depth+1，超限返回 nil；Explore 不可再派生可写代理 */
- (LAAgent *)spawnSubagentWithKind:(LAAgentKind)kind error:(NSError **)error;

/* Tab 切换：0=Build，1=Plan；越界返回 Build */
+ (LAAgentKind)kindForTabIndex:(NSUInteger)index;

/* @mention 解析：@build/@plan/@general/@explore；未知返回 NO */
+ (BOOL)kindForMention:(NSString *)mention outKind:(LAAgentKind *)outKind;

/* 种类对应 mention 字符串 */
+ (NSString *)mentionForKind:(LAAgentKind)kind;

/* 展示名映射 */
+ (NSString *)displayNameForKind:(LAAgentKind)kind;

@end

#endif /* LA_AGENT_H */
