#import "LAKeychainStore.h"
#import <Security/Security.h>

// Keychain 实现：service 隔离 + kSecAttrAccessibleWhenUnlockedThisDeviceOnly。
// 中文注释；全程 NSError** 回传；绝不写文件。

NSString *const LAKeychainErrorDomain = @"ai.luminagent.keychain";

// Keychain service 前缀（API Key 与 OAuth 分 service 存放，便于分别清理）。
static NSString *const kLAAPIKeyService = @"ai.luminagent.providers.apikey";
static NSString *const kLAOAuthService  = @"ai.luminagent.providers.oauth";

// 分享剥离敏感键集合（小写比较）。
static NSSet<NSString *> *LASensitiveKeys(void) {
    static NSSet<NSString *> *sKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sKeys = [NSSet setWithObjects:@"apikey", @"api_key", @"api-key",
                 @"token", @"access_token", @"access-token", @"refresh_token",
                 @"refresh-token", @"authorization", @"secret", @"password",
                 @"client_secret", nil];
    });
    return sKeys;
}

@implementation LAKeychainStore

// 获取单例。
+ (instancetype)sharedStore {
    static LAKeychainStore *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[LAKeychainStore alloc] init];
    });
    return shared;
}

// 构造通用查询字典。
- (NSMutableDictionary *)queryForService:(NSString *)service account:(NSString *)account {
    return [@{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service,
        (__bridge id)kSecAttrAccount : account,
    } mutableCopy];
}

// 由 OSStatus 构造 NSError。
- (NSError *)errorWithCode:(LAKeychainErrorCode)code osStatus:(OSStatus)st description:(NSString *)desc {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey : desc ?: @"Keychain 操作失败"} mutableCopy];
    if (st != noErr) { info[@"OSStatus"] = @(st); }
    return [NSError errorWithDomain:LAKeychainErrorDomain code:code userInfo:info];
}

// 保存通用字符串到 Keychain（存在则更新，不存在则添加）。
- (BOOL)saveString:(NSString *)value
          service:(NSString *)service
          account:(NSString *)account
            error:(NSError **)error {
    if (service.length == 0 || account.length == 0 || value.length == 0) {
        if (error) { *error = [self errorWithCode:LAKeychainErrorInvalidParam osStatus:noErr description:@"参数非法：service/account/value 不能为空"]; }
        return NO;
    }
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *query = [self queryForService:service account:account];
    // 先尝试更新。
    NSDictionary *attrs = @{
        (__bridge id)kSecValueData : data,
        (__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attrs);
    if (st == errSecItemNotFound) {
        // 不存在则添加。
        NSMutableDictionary *add = [query mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
        st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
    if (st != noErr) {
        if (error) { *error = [self errorWithCode:LAKeychainErrorOSStatus osStatus:st description:@"Keychain 写入失败"]; }
        return NO;
    }
    return YES;
}

// 读取通用字符串。
- (nullable NSString *)loadStringForService:(NSString *)service
                                    account:(NSString *)account
                                      error:(NSError **)error {
    if (service.length == 0 || account.length == 0) {
        if (error) { *error = [self errorWithCode:LAKeychainErrorInvalidParam osStatus:noErr description:@"参数非法：service/account 不能为空"]; }
        return nil;
    }
    NSMutableDictionary *query = [self queryForService:service account:account];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (st == errSecItemNotFound) {
        if (error) { *error = [self errorWithCode:LAKeychainErrorNotFound osStatus:st description:@"Keychain 中无此凭证"]; }
        return nil;
    }
    if (st != noErr) {
        if (error) { *error = [self errorWithCode:LAKeychainErrorOSStatus osStatus:st description:@"Keychain 读取失败"]; }
        return nil;
    }
    NSData *data = (__bridge_transfer NSData *)result;
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (value == nil && error) {
        *error = [self errorWithCode:LAKeychainErrorOSStatus osStatus:noErr description:@"凭证数据解码失败"];
    }
    return value;
}

// 删除通用记录（不存在视为成功，保证幂等）。
- (BOOL)deleteForService:(NSString *)service account:(NSString *)account error:(NSError **)error {
    if (service.length == 0 || account.length == 0) {
        if (error) { *error = [self errorWithCode:LAKeychainErrorInvalidParam osStatus:noErr description:@"参数非法：service/account 不能为空"]; }
        return NO;
    }
    NSMutableDictionary *query = [self queryForService:service account:account];
    OSStatus st = SecItemDelete((__bridge CFDictionaryRef)query);
    if (st != noErr && st != errSecItemNotFound) {
        if (error) { *error = [self errorWithCode:LAKeychainErrorOSStatus osStatus:st description:@"Keychain 删除失败"]; }
        return NO;
    }
    return YES;
}

#pragma mark - API Key

// 保存 API Key。
- (BOOL)saveAPIKey:(NSString *)apiKey forProvider:(NSString *)providerID error:(NSError **)error {
    return [self saveString:apiKey service:kLAAPIKeyService account:providerID error:error];
}

// 读取 API Key。
- (nullable NSString *)loadAPIKeyForProvider:(NSString *)providerID error:(NSError **)error {
    return [self loadStringForService:kLAAPIKeyService account:providerID error:error];
}

// 删除 API Key。
- (BOOL)deleteAPIKeyForProvider:(NSString *)providerID error:(NSError **)error {
    return [self deleteForService:kLAAPIKeyService account:providerID error:error];
}

#pragma mark - OAuth

// 保存 OAuth（access 与 refresh 以 \n 分隔打包，读取时取第一段）。
- (BOOL)saveOAuthAccessToken:(NSString *)accessToken
               refreshToken:(nullable NSString *)refreshToken
                forProvider:(NSString *)providerID
                      error:(NSError **)error {
    if (accessToken.length == 0) {
        if (error) { *error = [self errorWithCode:LAKeychainErrorInvalidParam osStatus:noErr description:@"参数非法：accessToken 不能为空"]; }
        return NO;
    }
    // 打包格式：access \n refresh（refresh 可空）。
    NSString *packed = refreshToken.length > 0
        ? [NSString stringWithFormat:@"%@\n%@", accessToken, refreshToken]
        : accessToken;
    BOOL ok = [self saveString:packed service:kLAOAuthService account:providerID error:error];
    return ok;
}

// 读取 OAuth accessToken（仅返回第一段）。
- (nullable NSString *)loadOAuthAccessTokenForProvider:(NSString *)providerID error:(NSError **)error {
    NSString *packed = [self loadStringForService:kLAOAuthService account:providerID error:error];
    if (packed == nil) { return nil; }
    NSRange r = [packed rangeOfString:@"\n"];
    if (r.location == NSNotFound) { return packed; }
    return [packed substringToIndex:r.location];
}

// 删除 OAuth 记录。
- (BOOL)deleteOAuthTokenForProvider:(NSString *)providerID error:(NSError **)error {
    return [self deleteForService:kLAOAuthService account:providerID error:error];
}

// 是否存在任意凭证（不向外返回错误，避免登录态判断打扰调用方）。
- (BOOL)hasCredentialForProvider:(NSString *)providerID {
    NSError *e1 = nil, *e2 = nil;
    NSString *k1 = [self loadStringForService:kLAAPIKeyService account:providerID error:&e1];
    if (k1.length > 0) { return YES; }
    NSString *k2 = [self loadStringForService:kLAOAuthService account:providerID error:&e2];
    return k2.length > 0;
}

#pragma mark - 分享剥离

// 判断单个键是否为敏感键。
+ (BOOL)isSensitiveKey:(NSString *)key {
    if (key.length == 0) { return NO; }
    NSString *lower = key.lowercaseString;
    if ([LASensitiveKeys() containsObject:lower]) { return YES; }
    return NO;
}

// 判断值是否像密钥（sk- 开头且较长），用于兜底剥离。
+ (BOOL)valueLooksLikeSecret:(id)value {
    if (![value isKindOfClass:[NSString class]]) { return NO; }
    NSString *s = (NSString *)value;
    return [s hasPrefix:@"sk-"] && s.length >= 12;
}

// 字典剥离：移除敏感键与疑似密钥值，递归处理嵌套字典/数组。
+ (NSDictionary *)sanitizedDictionaryByStrippingSecrets:(NSDictionary *)source {
    if (![source isKindOfClass:[NSDictionary class]]) { return @{}; }
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:source.count];
    [source enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        NSString *k = [key isKindOfClass:[NSString class]] ? key : [key description];
        if ([self isSensitiveKey:k] || [self valueLooksLikeSecret:obj]) {
            return; // 剥离，不写入
        }
        if ([obj isKindOfClass:[NSDictionary class]]) {
            out[key] = [self sanitizedDictionaryByStrippingSecrets:obj];
        } else if ([obj isKindOfClass:[NSArray class]]) {
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:[obj count]];
            for (id item in obj) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [arr addObject:[self sanitizedDictionaryByStrippingSecrets:item]];
                } else if (![self valueLooksLikeSecret:item]) {
                    [arr addObject:item];
                }
            }
            out[key] = [arr copy];
        } else {
            out[key] = obj;
        }
    }];
    return [out copy];
}

// 数组批量剥离。
+ (NSArray<NSDictionary *> *)sanitizedArrayByStrippingSecrets:(NSArray<NSDictionary *> *)source {
    if (![source isKindOfClass:[NSArray class]]) { return @[]; }
    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:source.count];
    for (id item in source) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            [out addObject:[self sanitizedDictionaryByStrippingSecrets:item]];
        }
    }
    return [out copy];
}

@end
