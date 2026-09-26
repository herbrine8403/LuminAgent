#import "LAProviderGateway.h"

// 网关实现：NSURLSession + header 注入 + 双端点 + /models 拉取。

NSString *const LAProviderGatewayErrorDomain = @"ai.luminagent.provider";

// 默认超时与默认 provider。
static const NSTimeInterval kLADefaultTimeout = 60.0;
static NSString *const kLADefaultProvider = @"zen";

#pragma mark - LARequestOptions

@implementation LARequestOptions
- (instancetype)init {
    if (self = [super init]) {
        _endpointKind = LAEndpointKindChatCompletions;
        _timeoutOverride = 0;
    }
    return self;
}
@end

#pragma mark - LAProviderConfig

@implementation LAProviderConfig

// 通用构造。
+ (instancetype)configWithID:(NSString *)pid baseURL:(NSString *)url {
    LAProviderConfig *c = [[LAProviderConfig alloc] init];
    c.providerID = pid;
    c.baseURL = url;
    c.timeout = kLADefaultTimeout;
    return c;
}

// Ollama 本地预设。
+ (instancetype)ollamaLocalConfig {
    return [self configWithID:@"ollama" baseURL:@"http://localhost:11434/v1"];
}

// LM Studio 本地预设。
+ (instancetype)lmStudioLocalConfig {
    return [self configWithID:@"lmstudio" baseURL:@"http://localhost:1234/v1"];
}

// 通用 OpenAI-compatible 预设。
+ (instancetype)openAICompatibleConfigWithBaseURL:(NSString *)baseURL providerID:(NSString *)providerID {
    NSString *pid = providerID.length > 0 ? providerID : @"custom";
    NSString *url = baseURL.length > 0 ? baseURL : @"http://localhost:1234/v1";
    return [self configWithID:pid baseURL:url];
}

// Zen 默认预设。
+ (instancetype)zenDefaultConfig {
    return [self configWithID:@"zen" baseURL:@"https://opencode.ai/zen/v1"];
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    LAProviderConfig *c = [[[self class] alloc] init];
    c.providerID = [self.providerID copy];
    c.baseURL = [self.baseURL copy];
    c.timeout = self.timeout;
    c.extraHeaders = [self.extraHeaders copy];
    return c;
}
@end

#pragma mark - LAProviderGateway

@interface LAProviderGateway ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, LAProviderConfig *> *providerTable;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) dispatch_queue_t syncQueue;
@end

@implementation LAProviderGateway

// 初始化：建表 + 共享 session（defaultSessionConfiguration，ATS 默认生效）。
- (instancetype)initWithProviders:(NSArray<LAProviderConfig *> *)providers {
    if (self = [super init]) {
        _providerTable = [NSMutableDictionary dictionary];
        for (LAProviderConfig *c in providers) {
            if (c.providerID.length > 0) { _providerTable[c.providerID] = [c copy]; }
        }
        NSURLSessionConfiguration *conf = [NSURLSessionConfiguration defaultSessionConfiguration];
        conf.timeoutIntervalForRequest = kLADefaultTimeout;
        conf.timeoutIntervalForResource = kLADefaultTimeout * 3;
        _session = [NSURLSession sessionWithConfiguration:conf];
        _syncQueue = dispatch_queue_create("ai.luminagent.provider", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// 快捷构造。
+ (instancetype)gatewayWithProviders:(NSArray<LAProviderConfig *> *)providers {
    return [[self alloc] initWithProviders:providers];
}

// 注册/更新。
- (void)upsertProvider:(LAProviderConfig *)config {
    if (config.providerID.length == 0) { return; }
    dispatch_sync(self.syncQueue, ^{
        self.providerTable[config.providerID] = [config copy];
    });
}

// 移除。
- (void)removeProviderWithID:(NSString *)providerID {
    if (providerID.length == 0) { return; }
    dispatch_sync(self.syncQueue, ^{
        [self.providerTable removeObjectForKey:providerID];
    });
}

// 查询（返回拷贝，防外部篡改）。
- (nullable LAProviderConfig *)configForProvider:(NSString *)providerID {
    __block LAProviderConfig *found = nil;
    dispatch_sync(self.syncQueue, ^{
        found = self.providerTable[providerID];
    });
    return [found copy];
}

// 构造 NSError。
- (NSError *)errorWithCode:(LAProviderGatewayErrorCode)code
                statusCode:(NSInteger)status
               description:(NSString *)desc
             underlyingErr:(nullable NSError *)under {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey : desc ?: @"Provider 请求失败"} mutableCopy];
    if (status > 0) { info[@"statusCode"] = @(status); }
    if (under) { info[NSUnderlyingErrorKey] = under; }
    return [NSError errorWithDomain:LAProviderGatewayErrorDomain code:code userInfo:info];
}

// 解析 provider/model（首个斜杠切分；无斜杠归默认 provider）。
- (BOOL)parseModelIdentifier:(NSString *)identifier
                   provider:(NSString * _Nullable * _Nullable)providerOut
                      model:(NSString * _Nullable * _Nullable)modelOut
                      error:(NSError **)error {
    NSString *trimmed = [identifier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (error) { *error = [self errorWithCode:LAProviderGatewayErrorBadIdentifier statusCode:0 description:@"模型标识为空" underlyingErr:nil]; }
        return NO;
    }
    NSRange slash = [trimmed rangeOfString:@"/"];
    NSString *provider = nil, *model = nil;
    if (slash.location == NSNotFound) {
        provider = kLADefaultProvider; // 裸 model 归 zen
        model = trimmed;
    } else {
        provider = [trimmed substringToIndex:slash.location];
        model = [trimmed substringFromIndex:slash.location + 1];
    }
    provider = [provider stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    model = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (provider.length == 0 || model.length == 0) {
        if (error) { *error = [self errorWithCode:LAProviderGatewayErrorBadIdentifier statusCode:0 description:@"模型标识须为 provider/model 形状" underlyingErr:nil]; }
        return NO;
    }
    if (providerOut) { *providerOut = provider; }
    if (modelOut) { *modelOut = model; }
    return YES;
}

// 是否 localhost（允许 HTTP 例外；其余一律 HTTPS）。
- (BOOL)isLocalhostURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString;
    return [host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"::1"];
}

// 校验基地址：仅 http/https；非 localhost 的 http 拒绝（ATS）。
- (nullable NSURL *)validatedBaseURL:(NSString *)raw error:(NSError **)error {
    NSURL *url = [NSURL URLWithString:raw];
    if (url == nil || url.scheme.length == 0 || url.host.length == 0) {
        if (error) { *error = [self errorWithCode:LAProviderGatewayErrorBadURL statusCode:0 description:@"baseURL 非法" underlyingErr:nil]; }
        return nil;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) {
        if (error) { *error = [self errorWithCode:LAProviderGatewayErrorBadURL statusCode:0 description:@"baseURL 仅支持 http/https" underlyingErr:nil]; }
        return nil;
    }
    if ([scheme isEqualToString:@"http"] && ![self isLocalhostURL:url]) {
        if (error) { *error = [self errorWithCode:LAProviderGatewayErrorInsecure statusCode:0 description:@"非本地端点须使用 HTTPS（ATS）" underlyingErr:nil]; }
        return nil;
    }
    return url;
}

// 拼 endpoint 路径。
- (NSString *)pathForEndpoint:(LAEndpointKind)kind {
    return kind == LAEndpointKindResponses ? @"responses" : @"chat/completions";
}

// 聊天调用。
- (void)chatWithIdentifier:(NSString *)identifier
                  messages:(NSArray<NSDictionary *> *)messages
                   options:(nullable LARequestOptions *)options
                    apiKey:(nullable NSString *)apiKey
                completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    // 同步参数校验（解析失败直接回调，不发起网络）。
    NSString *provider = nil, *model = nil;
    NSError *parseErr = nil;
    if (![self parseModelIdentifier:identifier provider:&provider model:&model error:&parseErr]) {
        if (completion) { completion(nil, parseErr); }
        return;
    }
    LAProviderConfig *cfg = [self configForProvider:provider];
    if (cfg == nil) {
        if (completion) { completion(nil, [self errorWithCode:LAProviderGatewayErrorNoProvider statusCode:0 description:[NSString stringWithFormat:@"未注册的 provider：%@", provider] underlyingErr:nil]); }
        return;
    }
    // 生效覆盖：baseURL/timeout/headers。
    NSString *base = options.baseURLOverride.length > 0 ? options.baseURLOverride : cfg.baseURL;
    NSTimeInterval timeout = (options && options.timeoutOverride > 0) ? options.timeoutOverride : cfg.timeout;
    if (timeout <= 0) { timeout = kLADefaultTimeout; }
    LAEndpointKind kind = options ? options.endpointKind : LAEndpointKindChatCompletions;
    NSError *urlErr = nil;
    NSURL *baseURL = [self validatedBaseURL:base error:&urlErr];
    if (baseURL == nil) {
        if (completion) { completion(nil, urlErr); }
        return;
    }
    NSString *urlStr = [NSString stringWithFormat:@"%@/%@",
                        [baseURL.absoluteString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]],
                        [self pathForEndpoint:kind]];
    NSURL *url = [NSURL URLWithString:urlStr];
    // 请求体（双端点形状）。
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"] = model;
    if (kind == LAEndpointKindResponses) {
        body[@"input"] = messages; // responses 端点用 input 承载消息
    } else {
        body[@"messages"] = messages; // chat/completions 端点
    }
    if (options.reasoningEffort.length > 0) {
        body[@"reasoning"] = @{@"effort" : options.reasoningEffort};
    }
    NSError *jsonErr = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (bodyData == nil) {
        if (completion) { completion(nil, [self errorWithCode:LAProviderGatewayErrorBadPayload statusCode:0 description:@"请求体序列化失败" underlyingErr:jsonErr]); }
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = timeout;
    req.HTTPBody = bodyData;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    // 固定附加头（provider 配置）。
    [cfg.extraHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        (void)stop;
        if ([k isKindOfClass:[NSString class]] && [v isKindOfClass:[NSString class]]) {
            [req setValue:v forHTTPHeaderField:k];
        }
    }];
    // 单次覆盖头。
    [options.headersOverride enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        (void)stop;
        if ([k isKindOfClass:[NSString class]] && [v isKindOfClass:[NSString class]]) {
            [req setValue:v forHTTPHeaderField:k];
        }
    }];
    // API Key 经 header 注入：拷贝一份局部变量，用后立即置 nil（最短持有）。
    NSString *keyCopy = [apiKey copy];
    if (keyCopy.length > 0) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", keyCopy] forHTTPHeaderField:@"Authorization"];
    }
    keyCopy = nil; // 最短持有：注入后即释放
    apiKey = nil;
    // 发起请求。
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
                                                 completionHandler:^(NSData *data, NSURLResponse *resp, NSError *netErr) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (netErr) {
            if (completion) { completion(nil, [strongSelf errorWithCode:LAProviderGatewayErrorNetwork statusCode:0 description:@"网络传输失败" underlyingErr:netErr]); }
            return;
        }
        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        if (status == 401) {
            // 401 触发重登回调（UI 组实现弹登录），此处仅通知 + 回传错误。
            if (strongSelf.onUnauthorized) { strongSelf.onUnauthorized(provider); }
            if (completion) { completion(nil, [strongSelf errorWithCode:LAProviderGatewayErrorUnauthorized statusCode:401 description:@"未授权（401），请重新登录" underlyingErr:nil]); }
            return;
        }
        if (status < 200 || status >= 300) {
            if (completion) { completion(nil, [strongSelf errorWithCode:LAProviderGatewayErrorHTTP statusCode:status description:[NSString stringWithFormat:@"HTTP 错误：%ld", (long)status] underlyingErr:nil]); }
            return;
        }
        NSError *parseError = nil;
        id obj = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError] : @{};
        if (parseError) {
            if (completion) { completion(nil, [strongSelf errorWithCode:LAProviderGatewayErrorBadPayload statusCode:status description:@"响应 JSON 解析失败" underlyingErr:parseError]); }
            return;
        }
        NSDictionary *result = [obj isKindOfClass:[NSDictionary class]] ? obj : @{@"data" : obj};
        if (completion) { completion(result, nil); }
    }];
    [task resume];
}

// 拉取 /models。
- (void)fetchModelsForProvider:(NSString *)providerID
                        apiKey:(nullable NSString *)apiKey
                    completion:(void (^)(NSArray<NSDictionary *> * _Nullable, NSError * _Nullable))completion {
    LAProviderConfig *cfg = [self configForProvider:providerID];
    if (cfg == nil) {
        if (completion) { completion(nil, [self errorWithCode:LAProviderGatewayErrorNoProvider statusCode:0 description:[NSString stringWithFormat:@"未注册的 provider：%@", providerID] underlyingErr:nil]); }
        return;
    }
    NSError *urlErr = nil;
    NSURL *baseURL = [self validatedBaseURL:cfg.baseURL error:&urlErr];
    if (baseURL == nil) {
        if (completion) { completion(nil, urlErr); }
        return;
    }
    NSString *urlStr = [NSString stringWithFormat:@"%@/models",
                        [baseURL.absoluteString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = cfg.timeout > 0 ? cfg.timeout : kLADefaultTimeout;
    NSString *keyCopy = [apiKey copy];
    if (keyCopy.length > 0) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", keyCopy] forHTTPHeaderField:@"Authorization"];
    }
    keyCopy = nil; // 最短持有
    apiKey = nil;
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
                                                 completionHandler:^(NSData *data, NSURLResponse *resp, NSError *netErr) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (netErr) {
            if (completion) { completion(nil, [strongSelf errorWithCode:LAProviderGatewayErrorNetwork statusCode:0 description:@"网络传输失败" underlyingErr:netErr]); }
            return;
        }
        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        if (status == 401) {
            if (strongSelf.onUnauthorized) { strongSelf.onUnauthorized(providerID); }
            if (completion) { completion(nil, [strongSelf errorWithCode:LAProviderGatewayErrorUnauthorized statusCode:401 description:@"未授权（401），请重新登录" underlyingErr:nil]); }
            return;
        }
        if (status < 200 || status >= 300) {
            if (completion) { completion(nil, [strongSelf errorWithCode:LAProviderGatewayErrorHTTP statusCode:status description:[NSString stringWithFormat:@"HTTP 错误：%ld", (long)status] underlyingErr:nil]); }
            return;
        }
        NSError *parseError = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&parseError];
        if (parseError) {
            if (completion) { completion(nil, [strongSelf errorWithCode:LAProviderGatewayErrorBadPayload statusCode:status description:@"/models 响应解析失败" underlyingErr:parseError]); }
            return;
        }
        NSArray *arr = nil;
        if ([obj isKindOfClass:[NSArray class]]) { arr = obj; }
        else if ([obj isKindOfClass:[NSDictionary class]] && [obj[@"data"] isKindOfClass:[NSArray class]]) { arr = obj[@"data"]; }
        else {
            if (completion) { completion(nil, [strongSelf errorWithCode:LAProviderGatewayErrorBadPayload statusCode:status description:@"/models 响应缺少 data 数组" underlyingErr:nil]); }
            return;
        }
        if (completion) { completion(arr, nil); }
    }];
    [task resume];
}

@end
