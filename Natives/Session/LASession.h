#ifndef LA_SESSION_H
#define LA_SESSION_H

/* 会话模型：AI 对话的基本组织单元；子会话经 parentID 关联父会话；
 * 主模式仅 Build/Plan 两种（子代理归 LAAgent 管理）。 */

#import <Foundation/Foundation.h>

/* 双主模式 */
typedef NS_ENUM(NSInteger, LAAgentMainMode) {
    LAAgentMainModeBuild, /* 全工具，默认 */
    LAAgentMainModePlan,  /* 只读规划：write/edit/bash 默认拒绝 */
};

/* 图片归一化默认上限：2000px / 5MB（可配） */
extern const double LAAgentDefaultImageMaxDimension;
extern const long long LAAgentDefaultImageMaxBytes;

@interface LASession : NSObject

@property (nonatomic, copy) NSString *sessionID;    /* 会话唯一标识 */
@property (nonatomic, copy) NSString *parentID;     /* 父会话标识，根会话为 nil */
@property (nonatomic, copy) NSString *title;        /* 会话标题 */
@property (nonatomic, assign) LAAgentMainMode mainMode; /* 主模式 */
@property (nonatomic, assign) NSTimeInterval createdAt; /* 创建时间戳（秒） */
@property (nonatomic, assign) NSTimeInterval updatedAt; /* 更新时间戳（秒） */
@property (nonatomic, assign) BOOL snapshotEnabled; /* 快照开关（NO=关闭 Git 快照，仅回滚消息） */
@property (nonatomic, assign) long long tokenLimit; /* 上下文 token 上限（0=使用压缩器默认） */
@property (nonatomic, assign) double imageMaxDimension; /* 图片最长边上限（像素） */
@property (nonatomic, assign) long long imageMaxBytes;  /* 图片体积上限（字节） */

+ (instancetype)sessionWithTitle:(NSString *)title
                       parentID:(NSString *)parentID
                           mode:(LAAgentMainMode)mode;

/* 图片归一化字节级守卫：超限返回 NO 并经 error 说明需下采样；
 * 像素级下采样由调用方经 UIImage 重绘后再次传入。 */
+ (BOOL)checkImageData:(NSData *)data
         maxDimension:(double)maxDimension
             maxBytes:(long long)maxBytes
                error:(NSError **)error;

/* 序列化 */
- (NSDictionary *)toDictionary;
- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end

#endif /* LA_SESSION_H */
