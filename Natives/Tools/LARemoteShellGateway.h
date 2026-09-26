#ifndef LA_REMOTE_SHELL_GATEWAY_H
#define LA_REMOTE_SHELL_GATEWAY_H

#import <Foundation/Foundation.h>
#import "LAPermissionAsking.h"

// 受限 shell 网关错误域。
extern NSString * const LARemoteShellErrorDomain;

typedef NS_ENUM(NSInteger, LARemoteShellErrorCode) {
    LARemoteShellErrorLocalDenied      = 2001, // 本机任意 bash 一律拒绝（红线）
    LARemoteShellErrorDangerousDenied  = 2002, // 危险命令默认 deny
    LARemoteShellErrorPermissionDenied = 2003, // 权限卡拒绝
    LARemoteShellErrorNotConfigured    = 2004, // 远端网关未配置
    LARemoteShellErrorInvalidArgument  = 2005, // 参数非法
};

// 执行通道：UI 必须明示当前通道（spec 要求）。
typedef NS_ENUM(NSInteger, LARemoteChannel) {
    LARemoteChannelLocalDenied = 0, // 本机：永远拒绝，仅返回指引
    LARemoteChannelSSH         = 1, // 用户自备 SSH 远端
    LARemoteChannelContainer   = 2, // 用户自建容器 HTTP 网关
    LARemoteChannelAppIntent   = 3, // App Intent / 快捷指令扩展
    LARemoteChannelMinimalNote = 4, // Minimal 模式声明（仅记录，不执行）
};

// 远端网关配置模型（用户自备；密钥存 Keychain，此处只存指纹/引用名）。
@interface LARemoteGatewayConfig : NSObject <NSCopying>
@property (nonatomic, assign) LARemoteChannel channel;
@property (nonatomic, copy, nullable) NSString *host;          // SSH/容器 host
@property (nonatomic, assign) NSInteger port;                  // SSH 默认 22
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *keyReference;  // Keychain 项名（非密钥本身）
@property (nonatomic, copy, nullable) NSString *endpointURL;   // 容器 HTTP 网关地址
@property (nonatomic, assign) NSTimeInterval timeoutSeconds;   // 默认 30
+ (instancetype)sshConfigWithHost:(NSString *)host port:(NSInteger)port username:(NSString *)user keyReference:(NSString *)keyRef;
+ (instancetype)containerConfigWithEndpointURL:(NSString *)url;
+ (instancetype)appIntentConfig;
@end

// shell 执行请求（结构化，便于审计与权限卡展示）。
@interface LARemoteShellRequest : NSObject
@property (nonatomic, copy) NSString *command;                 // 原始命令文本
@property (nonatomic, copy, nullable) NSString *workdir;       // 远端工作目录
@property (nonatomic, assign) NSTimeInterval timeoutSeconds;   // 0 则用配置默认值
+ (instancetype)requestWithCommand:(NSString *)command workdir:(nullable NSString *)workdir;
@end

// shell 执行结果（远端回执的统一封装）。
@interface LARemoteShellResult : NSObject
@property (nonatomic, assign) BOOL executed;                   // 是否真正下发远端
@property (nonatomic, assign) LARemoteChannel channel;         // 实际通道
@property (nonatomic, copy) NSString *userGuidance;            // 给用户的中文指引
@property (nonatomic, copy, nullable) NSString *receiptId;     // 远端回执 ID（扩展点回填）
@end

// 快捷指令/App Intent 扩展点：由宿主 App 实现实际投递，本类只组装载荷。
@protocol LARemoteHandoff <NSObject>
@required
// 投递远端执行载荷；receiptId 回填结果。NS_NOESCAPE 风格的同步接口，异步实现方需阻塞等待。
- (BOOL)deliverRequest:(LARemoteShellRequest *)request
                config:(LARemoteGatewayConfig *)config
             receiptId:(NSString * _Nullable * _Nullable)receiptId
                 error:(NSError **)error;
@end

// 受限 shell 网关：本机永不执行（无 NSTask/system/posix_spawn）；
// 危险命令默认 deny；其余按通道转远端/App Intent，或返回配置指引。
@interface LARemoteShellGateway : NSObject

@property (nonatomic, strong) LARemoteGatewayConfig *config;
@property (nonatomic, weak, nullable) id<LAPermissionAsking> permissionCenter;
@property (nonatomic, weak, nullable) id<LARemoteHandoff> handoff; // App Intent/快捷指令投递器

// 内置危险命令表（子串/正则摘要，供 UI 展示与审计）。
+ (NSArray<NSString *> *)dangerousPatterns;

// 危险判定：命中内置表即 YES（reason 回填中文原因）。
+ (BOOL)isDangerousCommand:(NSString *)command reason:(NSString * _Nullable * _Nullable)reason;

// 主入口：按“危险→权限→通道”顺序裁决；本机命令直接拒绝并返回配置指引。
- (nullable LARemoteShellResult *)executeRequest:(LARemoteShellRequest *)request
                                          error:(NSError **)error;

@end

#endif /* LA_REMOTE_SHELL_GATEWAY_H */
