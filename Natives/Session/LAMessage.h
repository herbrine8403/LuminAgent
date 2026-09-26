#ifndef LA_MESSAGE_H
#define LA_MESSAGE_H

/* 消息模型：一条消息归属一个会话，携带多个 part，
 * token/费用为其下 part 汇总；reverted 标记回滚状态。 */

#import <Foundation/Foundation.h>

@class LAMessagePart;

/* 消息角色 */
typedef NS_ENUM(NSInteger, LAMessageRole) {
    LAMessageRoleUser,      /* 用户输入 */
    LAMessageRoleAssistant, /* 助手回复 */
    LAMessageRoleTool,      /* 工具结果 */
    LAMessageRoleSystem,    /* 系统提示 */
};

@interface LAMessage : NSObject

@property (nonatomic, copy) NSString *messageID;   /* 消息唯一标识 */
@property (nonatomic, copy) NSString *sessionID;   /* 所属会话标识 */
@property (nonatomic, assign) LAMessageRole role;  /* 角色 */
@property (nonatomic, assign) NSTimeInterval createdAt; /* 创建时间戳（秒） */
@property (nonatomic, strong) NSMutableArray<LAMessagePart *> *parts; /* part 列表 */
@property (nonatomic, assign) BOOL reverted;       /* YES=已被 revert 回滚 */

+ (instancetype)messageWithSessionID:(NSString *)sessionID role:(LAMessageRole)role;

/* 追加 part */
- (void)appendPart:(LAMessagePart *)part;

/* 汇总：下属 part 的 token/费用求和 */
- (long long)totalTokens;
- (long long)totalCostMicro;

/* 角色与字符串互转 */
+ (NSString *)stringForRole:(LAMessageRole)role;
+ (LAMessageRole)roleForString:(NSString *)string;

/* 序列化 */
- (NSDictionary *)toDictionary;
- (instancetype)initWithDictionary:(NSDictionary *)dict sessionID:(NSString *)sessionID;

@end

#endif /* LA_MESSAGE_H */
