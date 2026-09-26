#ifndef LA_SESSION_PROVIDER_H
#define LA_SESSION_PROVIDER_H

/* Session 侧网关契约：网络实现归 Provider 组（LAProviderGateway 类），
 * 本组不做网络，此处仅保留轻量请求/响应模型与最小协议，
 * Harness 层负责将本协议适配到实际网关类。 */

#import <Foundation/Foundation.h>

/* 请求（Foundation 类型承载，他组映射为 chat/completions 与 responses 双格式） */
@interface LAProviderRequest : NSObject

@property (nonatomic, copy) NSString *provider;   /* 提供方标识，如 zen */
@property (nonatomic, copy) NSString *model;      /* 模型标识，如 zen-default */
@property (nonatomic, strong) NSArray<NSDictionary *> *messages; /* role/content 字典数组 */
@property (nonatomic, assign) NSTimeInterval timeout; /* 超时（秒，0=默认 60） */

+ (instancetype)requestWithProvider:(NSString *)provider
                               model:(NSString *)model
                            messages:(NSArray<NSDictionary *> *)messages;

@end

/* 响应 */
@interface LAProviderResponse : NSObject

@property (nonatomic, copy) NSString *text;       /* 主文本 */
@property (nonatomic, copy) NSString *reasoning;  /* 推理文本，可空 */
@property (nonatomic, assign) long long tokensIn;
@property (nonatomic, assign) long long tokensOut;
@property (nonatomic, assign) long long costMicro; /* 费用微单位，免费记 0 */

@end

/* Session 侧最小网关协议：实际由 Provider 组网关经适配器实现 */
@protocol LASessionProviderGateway <NSObject>

@required
/* 聊天补全：completion 在后台队列回调 */
- (void)fetchCompletionWithRequest:(LAProviderRequest *)request
                         completion:(void (^)(LAProviderResponse *response,
                                              NSError *error))completion;

@optional
/* 取消在途请求 */
- (void)cancelAllRequests;

@end

#endif /* LA_SESSION_PROVIDER_H */
