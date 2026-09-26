#ifndef LAMCPOAUTH_H
#define LAMCPOAUTH_H

/* MCP OAuth 与权限治理占位。
 * 约定：token 只存 Keychain（本文件经 Security 框架直写，不经 NSUserDefaults）；
 * 401 触发重登回调；任何日志/description 永不打印密钥；
 * tools 命名以 mcp_<server>_* 参与通配权限匹配（如 mcp_search: ask）；
 * 高 token 服务默认全局禁用，按会话按需启用。
 * 中文注释；可失败接口均使用 NSError**；仅封装 ASWebAuthenticationSession，不真调。 */

#import <Foundation/Foundation.h>

/* 前向声明：Keychain 统一封装与 Session 管理由他组并行实现，此处不重复定义 */
@class LAKeychainStore;
@class LASessionManager;

FOUNDATION_EXPORT NSString *const LAMCPOAuthErrorDomain;
typedef NS_ENUM(NSInteger, LAMCPOAuthErrorCode) {
    LAMCPOAuthErrorCodeInvalidArgument = 2001, /* 参数非法 */
    LAMCPOAuthErrorCodeKeychainFailed  = 2002, /* Keychain 读写失败 */
    LAMCPOAuthErrorCodeNotAuthorized   = 2003, /* 无 token，需先授权 */
};

/* 授权状态（mcp auth list 展示用，不含 token 本体） */
typedef NS_ENUM(NSInteger, LAMCPAuthState) {
    LAMCPAuthStateUnknown      = 0, /* 未知（local 服务恒为此态，无需 OAuth） */
    LAMCPAuthStateAuthorized   = 1, /* Keychain 内有 token */
    LAMCPAuthStateNotAuthorized = 2,/* 无 token */
    LAMCPAuthStateExpired      = 3, /* 曾收到 401，待重新授权 */
};

/* 401 重登回调：在收到远端 401 时由调用方触发 handleHTTPStatus 继而回调 UI 层弹授权页 */
typedef void (^LAMCPReauthHandler)(NSString *serverId);

/* OAuth 占位上下文：真机联调时用其拼出授权 URL，再以 ASWebAuthenticationSession 调起系统浏览器 */
@interface LAMCPOAuthContext : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *serverId;      /* 目标 MCP 服务 */
@property (nonatomic, copy) NSString *clientId;      /* OAuth clientId（示例中禁止填真实值） */
@property (nonatomic, copy) NSString *scope;         /* 授权 scope，如 @"mcp.read" */
@property (nonatomic, copy) NSString *authorizeURL;  /* 授权端点（占位字符串，不真请求） */
@property (nonatomic, copy) NSString *redirectScheme;/* 回调 scheme，如 @"luminagent-mcp" */
@end

@interface LAMCPOAuth : NSObject

+ (instancetype)sharedOAuth;

/* 401 重登回调（UI 层设置；触发时只传 serverId，不传 token） */
@property (nonatomic, copy, nullable) LAMCPReauthHandler onNeedReauth;

/* 生成 OAuth 占位上下文（仅拼参数，不创建网络请求；真调点见 startAuthenticationSessionPlaceholder 注释） */
- (nullable LAMCPOAuthContext *)makeOAuthContextForServerId:(NSString *)serverId
                                                   clientId:(NSString *)clientId
                                                      scope:(nullable NSString *)scope
                                               authorizeURL:(NSString *)authorizeURL
                                             redirectScheme:(NSString *)redirectScheme
                                                      error:(NSError **)error;

/* ASWebAuthenticationSession 占位接口（iOS15+ API，仅封装不真调）：
 * 真机联调时在此方法内创建 ASWebAuthenticationSession 并调起；
 * 当前占位实现直接回 NSError（NotAuthorized），避免任何真实 OAuth/网络验证。 */
- (void)startAuthenticationSessionPlaceholder:(LAMCPOAuthContext *)context
                                   completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

/* Keychain：保存 / 读取存在性 / 清除（logout）。token 本体永不经 NSLog/description 输出 */
- (BOOL)saveToken:(NSString *)token forServerId:(NSString *)serverId error:(NSError **)error;
- (BOOL)hasTokenForServerId:(NSString *)serverId;
- (nullable NSString *)loadTokenForServerId:(NSString *)serverId error:(NSError **)error;
- (BOOL)clearTokenForServerId:(NSString *)serverId error:(NSError **)error;

/* 授权状态列表（mcp auth list 数据源；只返回状态枚举，不返回 token） */
- (LAMCPAuthState)authStateForServerId:(NSString *)serverId isLocal:(BOOL)isLocal;

/* HTTP 状态处理：statusCode==401 时标记 Expired 并触发 onNeedReauth；返回 YES 表示需要重登 */
- (BOOL)handleHTTPStatus:(NSInteger)statusCode forServerId:(NSString *)serverId;

/* 通配权限匹配：pattern 支持 mcp_* 风格（* 匹配任意子串，? 匹配单字符）；
 * 如 pattern @"mcp_search:*" 可匹配 @"mcp_search:query"。大小写敏感 */
+ (BOOL)toolName:(NSString *)toolName matchesPattern:(NSString *)pattern;
/* 在一组 pattern 中任一命中即返回 YES（权限规则 ask/allow/deny 的匹配内核） */
+ (BOOL)toolName:(NSString *)toolName matchesAnyPatternIn:(NSArray<NSString *> *)patterns;

#pragma mark 高 token 治理
/* 标记某服务是否为高 token（默认全局禁用）；状态由 LAMCPManager 同步写入，此处只做会话级开关 */
- (void)setHighToken:(BOOL)highToken forServerId:(NSString *)serverId;
- (BOOL)isHighTokenServer:(NSString *)serverId;
/* 按会话按需启用：默认空集（即默认禁用）；启用后该会话可用集才包含其 tools */
- (void)setHighTokenServer:(NSString *)serverId enabled:(BOOL)enabled forSessionId:(NSString *)sessionId;
- (BOOL)isHighTokenServer:(NSString *)serverId enabledForSession:(NSString *)sessionId;
- (NSSet<NSString *> *)enabledHighTokenServerIdsForSession:(NSString *)sessionId;

@end

#endif /* LAMCPOAUTH_H */
