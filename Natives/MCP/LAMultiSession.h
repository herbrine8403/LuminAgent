#ifndef LAMULTISESSION_H
#define LAMULTISESSION_H

/* 多会话并行 + 分享治理占位。
 * 约定：真实消息体存储由 LASessionManager（他组并行）持有，
 * 本文件只维护会话拓扑（parent/child）、分享态与导入导出快照，不重复定义 Session 存储；
 * 分享链接形如 opncd.ai/s/ 风格（本地生成 token，不做真实上传）；
 * export --sanitize 脱敏后离线流转；分享/导出均剥离凭证（API Key / MCP token / headers value）。
 * 中文注释；可失败接口均使用 NSError**。 */

#import <Foundation/Foundation.h>

/* 前向声明：真实 Session 存储在他组，此处仅持有 sessionId 字符串做拓扑 */
@class LASessionManager;

FOUNDATION_EXPORT NSString *const LAMultiSessionErrorDomain;
typedef NS_ENUM(NSInteger, LAMultiSessionErrorCode) {
    LAMultiSessionErrorCodeInvalidArgument = 3001, /* 参数非法 */
    LAMultiSessionErrorCodeNotFound        = 3002, /* 会话不存在 */
    LAMultiSessionErrorCodeShareDisabled   = 3003, /* 分享被禁用（全局 auto 禁止或项目级强制禁用） */
    LAMultiSessionErrorCodeIOFailed        = 3004, /* 导入导出文件读写失败 */
    LAMultiSessionErrorCodeSanitizeFailed  = 3005, /* 脱敏失败（拒绝导出带密钥快照） */
};

/* 分享三档：manual 默认调起 / auto 建会即分享 / disabled 合规禁用 */
typedef NS_ENUM(NSInteger, LAMShareMode) {
    LAMShareModeManual   = 0, /* 默认：用户显式 /share 才生成链接 */
    LAMShareModeAuto     = 1, /* 建会即分享（自动生成链接，需自托管服务联调后才外发） */
    LAMShareModeDisabled = 2, /* 合规禁用：share/export 外发均拒绝（本地草稿不受影响） */
};

/* 会话拓扑节点（轻量快照，不含消息正文；正文经 LASessionManager 按 sessionId 取） */
@interface LAMSessionNode : NSObject <NSSecureCoding, NSCopying>
@property (nonatomic, copy) NSString *sessionId;             /* 会话唯一标识 */
@property (nonatomic, copy) NSString *projectId;             /* 所属项目（同一项目不同 concern 并行） */
@property (nonatomic, copy, nullable) NSString *parentSessionId; /* 父会话（fork 来源），根会话为 nil */
@property (nonatomic, copy) NSString *concern;                /* 并行关注点，如 @"修测试" / @"改文档" */
@property (nonatomic, strong) NSDate *createdAt;
@end

/* 分享快照的轻量描述（不含任何密钥，仅含消息与配置快照的引用信息） */
@interface LAMShareRecord : NSObject <NSSecureCoding, NSCopying>
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *shareToken;  /* 链接 token：opncd.ai/s/<token> */
@property (nonatomic, copy) NSString *shareURL;    /* 形如 https://opncd.ai/s/<token>（占位，未真上传） */
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, assign) BOOL revoked;        /* unshare 后置 YES */
@end

@interface LAMultiSession : NSObject

+ (instancetype)sharedInstance;

/* 全局分享模式（默认 Manual）；自托管分享服务地址（占位字符串，不真请求） */
@property (nonatomic, assign) LAMShareMode shareMode;
@property (nonatomic, copy, nullable) NSString *selfHostedShareBaseURL;

/* 项目级强制禁用分享（合规）：一旦加入，该项目 share/export 外发一律拒绝 */
- (void)setShareDisabled:(BOOL)disabled forProjectId:(NSString *)projectId;
- (BOOL)isShareDisabledForProjectId:(NSString *)projectId;

#pragma mark 多会话并行
/* 新建会话拓扑（同一项目不同 concern 上下文隔离由 LASessionManager 保证，此处只记拓扑） */
- (nullable LAMSessionNode *)createSessionInProject:(NSString *)projectId
                                            concern:(NSString *)concern
                                              error:(NSError **)error;
/* fork：以源会话为 parent 建子会话（子会话初始配置快照继承，消息拷贝由调用方经 LASessionManager 完成） */
- (nullable LAMSessionNode *)forkSession:(NSString *)sourceSessionId
                             newConcern:(NSString *)concern
                                  error:(NSError **)error;
/* 删除会话拓扑（同时清理其分享记录；真实消息删除由 LASessionManager 执行） */
- (BOOL)removeSession:(NSString *)sessionId error:(NSError **)error;
/* 查询 */
- (nullable LAMSessionNode *)nodeForSession:(NSString *)sessionId;
- (NSArray<LAMSessionNode *> *)listSessionsInProject:(NSString *)projectId;
- (NSArray<LAMSessionNode *> *)childrenOfSession:(NSString *)sessionId;
- (nullable LAMSessionNode *)parentOfSession:(NSString *)sessionId;
/* parent/child 导航：当前活动会话切换（返回切换后的节点，便于 UI 高亮面包屑） */
- (nullable LAMSessionNode *)switchToSession:(NSString *)sessionId error:(NSError **)error;
- (nullable LAMSessionNode *)activeSession;

#pragma mark 分享与导入导出
/* /share：生成 opncd.ai/s/ 风格链接（默认 manual；auto 模式下 create 即自动调用；disabled 直接拒绝） */
- (nullable LAMShareRecord *)shareSession:(NSString *)sessionId error:(NSError **)error;
/* /unshare：撤销（revoked=YES，链接即时失效占位标记） */
- (BOOL)unshareSession:(NSString *)sessionId error:(NSError **)error;
- (BOOL)isSessionShared:(NSString *)sessionId;

/* /export：将快照写 JSON 文件；sanitize=YES 时强制脱敏（等价 export --sanitize），否则若检测到密钥直接失败 */
- (BOOL)exportSession:(NSString *)sessionId
               toFile:(NSString *)filePath
             sanitize:(BOOL)sanitize
fetchSnapshot:(NSDictionary * (^)(NSString *sessionId))fetchSnapshot
                error:(NSError **)error;
/* /import：从 JSON 文件恢复（返回新 sessionId 的拓扑节点；文件中若含密钥字段则拒绝并报错） */
- (nullable LAMSessionNode *)importSessionFromFile:(NSString *)filePath
                                         projectId:(NSString *)projectId
                                             error:(NSError **)error;

/* 脱敏内核：剥离 API Key / MCP token / headers value / Authorization 等（export/share 共用） */
+ (NSDictionary *)sanitizedSnapshot:(NSDictionary *)snapshot;
/* 检测快照是否含疑似凭证（key/token/secret/authorization 等键名命中即视为含） */
+ (BOOL)snapshotContainsCredential:(NSDictionary *)snapshot;

@end

#endif /* LAMULTISESSION_H */
