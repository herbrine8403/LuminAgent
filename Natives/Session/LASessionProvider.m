#import "LASessionProvider.h"

/* 网关模型实现：纯数据载体，无网络代码（网络由 Provider 组实现） */

@implementation LAProviderRequest

+ (instancetype)requestWithProvider:(NSString *)provider
                               model:(NSString *)model
                            messages:(NSArray<NSDictionary *> *)messages {
    LAProviderRequest *request = [[LAProviderRequest alloc] init];
    request.provider = [provider copy] ?: @"zen";
    request.model = [model copy] ?: @"zen-default";
    request.messages = [messages copy] ?: @[];
    request.timeout = 60;
    return request;
}

@end

@implementation LAProviderResponse
@end
