#ifndef LA_KEYCHAIN_STORE_H
#define LA_KEYCHAIN_STORE_H

#import <Foundation/Foundation.h>

// Keychain 凭证隔离存储：API Key / OAuth Token 仅存 Keychain，永不写文件。
// 跨组契约：Provider 网关与 MCP OAuth 经此类读写凭证；分享/导出前调用剥离方法。
@interface LAKeychainStore : NSObject

// 单例入口。
+ (instancetype)sharedStore;

// 保存指定供应商的 API Key（覆盖已存在项）。key 为 nil/空时返回 NO。
// service 固定为 @"ai.luminagent.providers"，account 为 providerID。
// key 仅在本次调用栈持有，方法返回后调用方应尽快置 nil。
- (BOOL)saveAPIKey:(NSString *)apiKey
       forProvider:(NSString *)providerID
             error:(NSError **)error;

// 读取指定供应商的 API Key；不存在时返回 nil（error 置 LAKeychainErrorNotFound）。
- (nullable NSString *)loadAPIKeyForProvider:(NSString *)providerID
                                       error:(NSError **)error;

// 删除指定供应商的 API Key；不存在视为成功（幂等）。
- (BOOL)deleteAPIKeyForProvider:(NSString *)providerID
                          error:(NSError **)error;

// 保存 OAuth Token（accessToken + 可选 refreshToken 打包存一条 Keychain 记录）。
- (BOOL)saveOAuthAccessToken:(NSString *)accessToken
               refreshToken:(nullable NSString *)refreshToken
                forProvider:(NSString *)providerID
                      error:(NSError **)error;

// 读取 OAuth accessToken；不存在返回 nil。
- (nullable NSString *)loadOAuthAccessTokenForProvider:(NSString *)providerID
                                                 error:(NSError **)error;

// 删除 OAuth 记录（access + refresh 一并删除）。
- (BOOL)deleteOAuthTokenForProvider:(NSString *)providerID
                              error:(NSError **)error;

// 是否存在任意凭证（Key 或 OAuth），用于登录态判断。
- (BOOL)hasCredentialForProvider:(NSString *)providerID;

// 分享/导出前剥离凭证：输入任意字典，移除 apiKey/token/authorization 等敏感键。
// 敏感键匹配（大小写不敏感）：apikey, api_key, token, access_token, refresh_token,
// authorization, secret, password, sk- 开头的值。
+ (NSDictionary *)sanitizedDictionaryByStrippingSecrets:(NSDictionary *)source;

// 数组批量剥离（对分享的会话/配置列表逐项调用字典版本）。
+ (NSArray<NSDictionary *> *)sanitizedArrayByStrippingSecrets:(NSArray<NSDictionary *> *)source;

@end

// 错误域与错误码。
FOUNDATION_EXPORT NSString *const LAKeychainErrorDomain;
typedef NS_ENUM(NSInteger, LAKeychainErrorCode) {
    LAKeychainErrorNotFound     = 1001, // Keychain 中无此项
    LAKeychainErrorInvalidParam = 1002, // 参数非法（provider 为空 / key 为空）
    LAKeychainErrorOSStatus     = 1003, // SecItem* 返回非 noErr（userInfo[@"OSStatus"]）
};

#endif /* LA_KEYCHAIN_STORE_H */
