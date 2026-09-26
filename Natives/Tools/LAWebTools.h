#ifndef LA_WEB_TOOLS_H
#define LA_WEB_TOOLS_H

#import <Foundation/Foundation.h>

// 网络工具错误域。
extern NSString * const LAWebToolsErrorDomain;

typedef NS_ENUM(NSInteger, LAWebToolsErrorCode) {
    LAWebToolsErrorInvalidURL      = 3001, // URL 非法
    LAWebToolsErrorInsecureDenied  = 3002, // ATS：默认拒绝明文 HTTP
    LAWebToolsErrorCancelled       = 3003, // 用户取消
    LAWebToolsErrorTimeout         = 3004, // 超时
    LAWebToolsErrorHTTPError       = 3005, // 非 2xx
    LAWebToolsErrorInvalidArgument = 3006, // 参数非法
};

// 抓取格式：markdown（默认）或纯文本。
typedef NS_ENUM(NSInteger, LAWebFetchFormat) {
    LAWebFetchFormatMarkdown = 0,
    LAWebFetchFormatText     = 1,
};

// 取消令牌：跨 webfetch/websearch 共享，调用 cancel 即取消在途任务。
@interface LACancellationToken : NSObject
@property (atomic, assign, getter=isCancelled) BOOL cancelled;
- (void)cancel;
@end

// webfetch 结果：正文摘要 + 来源链接（spec 要求附来源）。
@interface LAWebFetchResult : NSObject
@property (nonatomic, copy) NSString *sourceURL; // 实际响应 URL（跟随重定向后）
@property (nonatomic, copy, nullable) NSString *title; // HTML <title>（如有）
@property (nonatomic, copy) NSString *content;   // markdown 或纯文本
@property (nonatomic, assign) LAWebFetchFormat format;
@property (nonatomic, copy, nullable) NSString *mimeType;
@end

// websearch 单条：标题 + 摘要 + 来源链接。
@interface LAWebSearchItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *snippet;
@property (nonatomic, copy) NSString *sourceURL;
@end

// 网络工具：webfetch（URL→markdown/text）与 websearch（检索+摘要+来源）。
// 遵守 ATS（默认仅 HTTPS，明文需显式 allowInsecure=YES）；支持超时与取消。
@interface LAWebTools : NSObject

// 会话（默认 ephemeral，便于测试注入）；超时秒数默认 30。
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) NSTimeInterval defaultTimeoutSeconds;
// 搜索网关基地址（用户自备，如公司内网搜索 API；为 nil 则 websearch 返回配置指引错误）。
@property (nonatomic, copy, nullable) NSString *searchEndpoint;

// 抓取：同步阻塞接口（内部用信号量等待 NSURLSession 回调；调用方应在后台队列调用）。
- (nullable LAWebFetchResult *)webfetchURLString:(NSString *)urlString
                                          format:(LAWebFetchFormat)format
                                   allowInsecure:(BOOL)allowInsecure
                                         timeout:(NSTimeInterval)timeout
                              cancellationToken:(nullable LACancellationToken *)token
                                          error:(NSError **)error;

// 搜索：同步阻塞接口；query 为空返回参数错误；未配置 searchEndpoint 返回指引错误。
- (nullable NSArray<LAWebSearchItem *> *)websearchQuery:(NSString *)query
                                             maxResults:(NSInteger)maxResults
                                                timeout:(NSTimeInterval)timeout
                                     cancellationToken:(nullable LACancellationToken *)token
                                                 error:(NSError **)error;

@end

#endif /* LA_WEB_TOOLS_H */
