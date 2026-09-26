#ifndef LAMCPMANAGER_H
#define LAMCPMANAGER_H

/* MCP 服务管理：add/list/auth/logout/debug 对等能力占位。
 * 支持 local（受限命令白名单）与 remote（url+headers）两类；
 * enabled=NO 表示停用而不删除；连接状态可在设置页展示；
 * 远端 tools 经连通性检测后注入 Agent 可用集（本文件只管可用集计算，不做真实网络）。
 * 中文注释；所有可失败接口均使用 NSError**；不做真实网络验证。 */

#import <Foundation/Foundation.h>

/* 前向声明：Session 存储与 Provider 由他组并行实现，此处不重复定义，仅用于解耦。 */
@class LASessionManager;
@class LAKeychainStore;

/* 错误域与错误码 */
FOUNDATION_EXPORT NSString *const LAMCPErrorDomain;
typedef NS_ENUM(NSInteger, LAMCPErrorCode) {
    LAMCPErrorCodeInvalidArgument = 1001,  /* 参数非法（空 serverId / 非法 URL 等） */
    LAMCPErrorCodeNotFound        = 1002,  /* 指定的 serverId 不存在 */
    LAMCPErrorCodeNotAllowed      = 1003,  /* local 命令不在白名单内 */
    LAMCPErrorCodeNeedAuth        = 1004,  /* 需要先完成 OAuth 授权 */
    LAMCPErrorCodeDisabled        = 1005,  /* 服务已停用 */
};

/* 服务类型：本地受限命令 / 远端 URL */
typedef NS_ENUM(NSInteger, LAMCPServerType) {
    LAMCPServerTypeLocal  = 0,  /* 本地：仅允许白名单内的无副作用查询类命令 */
    LAMCPServerTypeRemote = 1,  /* 远端：url + headers（headers 永不落盘明文展示） */
};

/* 连接状态模型：设置页直接展示 */
typedef NS_ENUM(NSInteger, LAMCPConnectionState) {
    LAMCPConnectionStateUnknown    = 0,  /* 尚未检测 */
    LAMCPConnectionStateDisabled   = 1,  /* enabled=NO 停用中 */
    LAMCPConnectionStateConnecting = 2,  /* 检测中（占位） */
    LAMCPConnectionStateConnected  = 3,  /* 连通性检测通过，tools 可注入 */
    LAMCPConnectionStateNeedAuth   = 4,  /* 需要 OAuth（远端 401 映射至此） */
    LAMCPConnectionStateFailed     = 5,  /* 检测失败，见 lastErrorMessage */
};

/* 单个 MCP 服务描述（值对象，可序列化为配置 JSON） */
@interface LAMCPServer : NSObject <NSCopying, NSSecureCoding>

/* 唯一标识（add 时若为空则自动生成 UUID） */
@property (nonatomic, copy) NSString *serverId;
/* 展示名，如 @"search"（tools 命名前缀 mcp_<展示名>_* 参见 LAMCPOAuth 通配匹配） */
@property (nonatomic, copy) NSString *name;
/* 服务类型 */
@property (nonatomic, assign) LAMCPServerType type;
/* local 专用：白名单内的命令名（如 mcp-fs-read），不含参数 */
@property (nonatomic, copy, nullable) NSString *command;
/* local 专用：命令固定参数（仅允许查询类参数，add 时做白名单校验） */
@property (nonatomic, copy, nullable) NSArray<NSString *> *args;
/* remote 专用：远端 MCP 地址（http/https） */
@property (nonatomic, copy, nullable) NSString *url;
/* remote 专用：附加请求头（内存持有；debug 输出时必须脱敏，见 debugDictionarySanitized） */
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *headers;
/* enabled 开关：NO 表示停用而不删除 */
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
/* 连接状态（设置页可见） */
@property (nonatomic, assign) LAMCPConnectionState connectionState;
/* 最近一次状态描述（不含任何密钥） */
@property (nonatomic, copy, nullable) NSString *lastErrorMessage;
/* 该服务暴露的 tools 全量名（远端连通性检测通过后写入；命名形如 mcp_<server>_*） */
@property (nonatomic, copy) NSArray<NSString *> *tools;
/* 高 token 服务标记：YES 则默认全局禁用，需按会话按需启用（见 LAMCPOAuth） */
@property (nonatomic, assign, getter=isHighToken) BOOL highToken;

- (instancetype)initWithName:(NSString *)name type:(LAMCPServerType)type;

/* 脱敏字典：headers 只输出 key 名 + "***"，永不输出 value；供设置页/debug展示 */
- (NSDictionary *)debugDictionarySanitized;

@end

/* MCP 管理器：单例，内存 + NSUserDefaults 持久化配置（token 本身不在此存，走 LAMCPOAuth/Keychain） */
@interface LAMCPManager : NSObject

/* 单例 */
+ (instancetype)sharedManager;

/* 白名单：默认仅允许无副作用查询类命令；示例中禁止出现真实系统命令全路径 */
+ (NSSet<NSString *> *)defaultLocalCommandWhitelist;
/* 校验 local 命令是否在白名单内（大小写敏感、全字匹配） */
+ (BOOL)isAllowedLocalCommand:(nullable NSString *)command;

/* 添加 local 服务：command 必须在白名单内，否则 NSError(LAMCPErrorCodeNotAllowed) */
- (nullable LAMCPServer *)addLocalServerWithName:(NSString *)name
                                         command:(NSString *)command
                                            args:(nullable NSArray<NSString *> *)args
                                           error:(NSError **)error;
/* 添加 remote 服务：url 必须为 http/https；headers 可空；连通性检测为占位（不真调网络） */
- (nullable LAMCPServer *)addRemoteServerWithName:(NSString *)name
                                              url:(NSString *)url
                                          headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                                            error:(NSError **)error;
/* 删除服务（同时建议调用方走 LAMCPOAuth 清除该 serverId 的 token，见 auth/logout 约定） */
- (BOOL)removeServerWithId:(NSString *)serverId error:(NSError **)error;
/* 按 serverId 查找 */
- (nullable LAMCPServer *)serverWithId:(NSString *)serverId;
/* 列出全部服务（按 name 排序，便于设置页展示） */
- (NSArray<LAMCPServer *> *)listServers;

/* enabled 开关：停用而不删除；停用后 connectionState 置为 Disabled，可用集自动排除 */
- (BOOL)setEnabled:(BOOL)enabled forServerWithId:(NSString *)serverId error:(NSError **)error;

/* auth 占位：标记该远端服务需要/已完成授权检查（真实 OAuth 流程见 LAMCPOAuth） */
- (BOOL)markAuthCheckedForServerWithId:(NSString *)serverId
                             needAuth:(BOOL)needAuth
                                error:(NSError **)error;
/* logout 约定：清除连接态为 NeedAuth/Failed 的展示态；真实 token 清除由 LAMCPOAuth 执行 */
- (BOOL)logoutServerWithId:(NSString *)serverId error:(NSError **)error;

/* debug 信息：脱敏字典数组（headers/密钥永不输出明文），供设置页与 mcp debug 命令展示 */
- (NSArray<NSDictionary *> *)debugInfoSanitized;

/* 更新连接状态（连通性检测占位入口：当前仅做本地状态机翻转，不发起真实网络请求） */
- (BOOL)updateConnectionState:(LAMCPConnectionState)state
               forServerWithId:(NSString *)serverId
                  errorMessage:(nullable NSString *)errorMessage
                         error:(NSError **)error;
/* 写入某服务的远端 tools 全量（命名应为 mcp_<server>_*；仅在 Connected 后调用方写入） */
- (BOOL)setTools:(NSArray<NSString *> *)tools
  forServerWithId:(NSString *)serverId
            error:(NSError **)error;

/* Agent 可用集注入：返回全局可用 tools（enabled 且 Connected 的服务之 tools 并集，已排序去重） */
- (NSArray<NSString *> *)availableToolNamesGlobal;
/* 按会话可用集：全局可用集 ∩ 会话启用集；高 token 服务默认不在会话启用集内（按需启用见 LAMCPOAuth） */
- (NSArray<NSString *> *)availableToolNamesForSessionEnabledServerIds:(nullable NSSet<NSString *> *)sessionEnabledIds;

/* 持久化：显式保存/重载配置（headers 仅存 key 名列表，不存 value，避免密钥落盘） */
- (BOOL)saveWithError:(NSError **)error;
- (BOOL)reloadWithError:(NSError **)error;

@end

#endif /* LAMCPMANAGER_H */
