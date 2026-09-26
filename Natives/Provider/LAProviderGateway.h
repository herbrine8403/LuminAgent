#ifndef LA_PROVIDER_GATEWAY_H
#define LA_PROVIDER_GATEWAY_H

#import <Foundation/Foundation.h>

// 统一 provider/model 寻址网关：baseURL/timeout/headers 覆盖、双端点适配、/models 刷新、本地模型接入。
// 网络经 NSURLSession（默认 HTTPS，ATS 合规）；API Key 经 HTTP header 注入，内存最短持有。
// 401 触发 onUnauthorized 回调（重登流程由 UI 组实现，此处仅回调通知）。
NS_ASSUME_NONNULL_BEGIN

// 端点类型：chat/completions 与 responses 双适配。
typedef NS_ENUM(NSInteger, LAEndpointKind) {
    LAEndpointKindChatCompletions = 0, // POST {baseURL}/chat/completions
    LAEndpointKindResponses       = 1, // POST {baseURL}/responses
};

// 單次请求可覆盖项（baseURL/timeout/headers/endpoint）。
@interface LARequestOptions : NSObject
@property (nonatomic, copy, nullable) NSString *baseURLOverride;   // 为空则用 provider 配置
@property (nonatomic, assign) NSTimeInterval timeoutOverride;      // <=0 表示用 provider 配置
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *headersOverride; // 合并覆盖
@property (nonatomic, assign) LAEndpointKind endpointKind;          // 默认 ChatCompletions
@property (nonatomic, copy, nullable) NSString *reasoningEffort;   // low/medium/high（可选透传）
@end

// Provider 配置：每个 provider 一份，支持本地模型预设。
@interface LAProviderConfig : NSObject <NSCopying>
@property (nonatomic, copy) NSString *providerID;                  // 如 zen/openai/ollama
@property (nonatomic, copy) NSString *baseURL;                     // 如 https://opencode.ai/zen/v1
@property (nonatomic, assign) NSTimeInterval timeout;              // 默认 60s
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *extraHeaders; // 固定附加头
// 本地 Ollama 预设：http://localhost:11434/v1（localhost 例外允许 HTTP）。
+ (instancetype)ollamaLocalConfig;
// 本地 LM Studio 预设：http://localhost:1234/v1。
+ (instancetype)lmStudioLocalConfig;
// 通用 OpenAI-compatible 预设（需调用方传入 baseURL）。
+ (instancetype)openAICompatibleConfigWithBaseURL:(NSString *)baseURL providerID:(NSString *)providerID;
// Zen 预设（默认基地址 + 60s 超时）。
+ (instancetype)zenDefaultConfig;
@end

@interface LAProviderGateway : NSObject

// 401 回调：参数为 providerID，UI 组据此弹重登流程。
@property (nonatomic, copy, nullable) void (^onUnauthorized)(NSString *providerID);

// 初始化：providers 为 LAProviderConfig 数组；默认超时 60s。
- (instancetype)initWithProviders:(NSArray<LAProviderConfig *> *)providers;
+ (instancetype)gatewayWithProviders:(NSArray<LAProviderConfig *> *)providers;

// 注册/更新单个 provider 配置（同 ID 覆盖）。
- (void)upsertProvider:(LAProviderConfig *)config;
// 移除 provider。
- (void)removeProviderWithID:(NSString *)providerID;
// 查询 provider 配置；不存在返回 nil。
- (nullable LAProviderConfig *)configForProvider:(NSString *)providerID;

// 解析 "provider/model"：providerOut/modelOut 二者至少其一非空才返回 YES。
// 无斜杠时视为裸 model，归属默认 provider（zen）。
// 失败经 error 回传（LAProviderGatewayErrorBadIdentifier）。
- (BOOL)parseModelIdentifier:(NSString *)identifier
                   provider:(NSString * _Nullable * _Nullable)providerOut
                      model:(NSString * _Nullable * _Nullable)modelOut
                      error:(NSError **)error;

// 聊天调用（双端点适配）：messages 为 OpenAI 形状数组（role/content）。
// apiKey 仅本次持有：方法内拷贝注入 header 后立即置 nil，绝不缓存、不打印。
// 401 时触发 onUnauthorized 回调并经 completion 回传 LAProviderGatewayErrorUnauthorized。
- (void)chatWithIdentifier:(NSString *)identifier
                  messages:(NSArray<NSDictionary *> *)messages
                   options:(nullable LARequestOptions *)options
                    apiKey:(nullable NSString *)apiKey
                completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

// 拉取 /models 并刷新：GET {baseURL}/models，返回原始字典数组（data 内元素）。
// 本地/远端统一走此入口；HTTP 错误与 JSON 解析失败经 completion 回传。
- (void)fetchModelsForProvider:(NSString *)providerID
                        apiKey:(nullable NSString *)apiKey
                    completion:(void (^)(NSArray<NSDictionary *> * _Nullable models, NSError * _Nullable error))completion;

@end

// 错误域与错误码。
FOUNDATION_EXPORT NSString *const LAProviderGatewayErrorDomain;
typedef NS_ENUM(NSInteger, LAProviderGatewayErrorCode) {
    LAProviderGatewayErrorBadIdentifier = 3001, // provider/model 解析失败
    LAProviderGatewayErrorNoProvider    = 3002, // 未注册的 provider
    LAProviderGatewayErrorBadURL        = 3003, // baseURL 非法（非 http/https）
    LAProviderGatewayErrorInsecure      = 3004, // 非 localhost 的 HTTP 被 ATS 策略拒绝
    LAProviderGatewayErrorUnauthorized  = 3005, // 401，需重登
    LAProviderGatewayErrorHTTP          = 3006, // 其他 HTTP 错误（userInfo[@"statusCode"]）
    LAProviderGatewayErrorNetwork       = 3007, // NSURLSession 传输错误
    LAProviderGatewayErrorBadPayload    = 3008, // 响应 JSON 解析失败
};

NS_ASSUME_NONNULL_END

#endif /* LA_PROVIDER_GATEWAY_H */
