#ifndef LA_SANDBOX_FILE_TOOLS_H
#define LA_SANDBOX_FILE_TOOLS_H

#import <Foundation/Foundation.h>
#import "LAPermissionAsking.h"

// 沙盒文件工具错误域。
extern NSString * const LAFileToolsErrorDomain;

// 错误码：调用方据此区分“需授权 / 未下载 / 二进制 / 未找到”等。
typedef NS_ENUM(NSInteger, LAFileToolsErrorCode) {
    LAFileToolsErrorNotFound            = 1001, // 文件不存在
    LAFileToolsErrorOutsideSandbox      = 1002, // 越界且未授权（已触发 ask）
    LAFileToolsErrorPermissionDenied    = 1003, // 用户在权限卡拒绝
    LAFileToolsErrorIsDirectory         = 1004, // 目标是目录而非文件
    LAFileToolsErrorIsBinary            = 1005, // 二进制文件拒绝按文本读取
    LAFileToolsErrorNotDownloaded       = 1006, // iCloud 云端未下载
    LAFileToolsErrorEditNoMatch         = 1007, // edit 精确串无匹配
    LAFileToolsErrorEditAmbiguous       = 1008, // edit 非 replaceAll 有多处匹配
    LAFileToolsErrorGitIgnored          = 1009, // 命中 .gitignore 被跳过
    LAFileToolsErrorInvalidArgument     = 1010, // 参数非法
};

// grep 单行命中模型。
@interface LAGrepMatch : NSObject
@property (nonatomic, copy) NSString *filePath; // 命中文件绝对路径
@property (nonatomic, assign) NSInteger line;   // 1 起行号
@property (nonatomic, copy) NSString *preview;  // 命中行裁剪预览
@end

// 沙盒文件工具：read/write/edit/glob/grep/list。
// 默认限定 App 沙盒（Documents/Projects）+ 经 picker 授权的外部目录；
// external_directory 越界走 LAPermissionAsking 回调；尊重 .gitignore 语义。
@interface LASandboxFileTools : NSObject

// 授权的外部目录（picker 回调写入的绝对路径集合）。
@property (nonatomic, copy) NSSet<NSString *> *authorizedExternalDirectories;
// 项目根（用于加载 .gitignore）；可为 nil（此时不做忽略过滤）。
@property (nonatomic, copy, nullable) NSString *projectRoot;
// 权限 ask 回调（UI 他组实现）；为 nil 时越界一律按拒绝处理。
@property (nonatomic, weak, nullable) id<LAPermissionAsking> permissionCenter;

// 沙盒根：Documents 与 Documents/Projects（不存在则视为未创建）。
+ (NSArray<NSString *> *)sandboxRoots;

// 读取文本文件：二进制 / iCloud 未下载返回明确 NSError。
- (nullable NSString *)readFileAtPath:(NSString *)path
                             encoding:(NSStringEncoding)encoding
                                error:(NSError **)error;

// 写文本文件：父目录自动创建；越界走 ask；命中 .gitignore 仍允许显式写但返回告警？此处直接允许写（读/列才过滤）。
- (BOOL)writeFileAtPath:(NSString *)path
                content:(NSString *)content
               encoding:(NSStringEncoding)encoding
                  error:(NSError **)error;

// 精确字符串替换：oldString 必须逐字节精确匹配；replaceAll=NO 且多处匹配返回 Ambiguous 错误。
- (BOOL)editFileAtPath:(NSString *)path
             oldString:(NSString *)oldString
             newString:(NSString *)newString
           replaceAll:(BOOL)replaceAll
                error:(NSError **)error;

// 目录列举（非递归一层）；返回绝对路径数组。
- (nullable NSArray<NSString *> *)listDirectoryAtPath:(NSString *)path
                                                error:(NSError **)error;

// glob：pattern 为相对 projectRoot 或绝对的 fnmatch 风格（如 **/*.m）；尊重 .gitignore。
- (nullable NSArray<NSString *> *)globWithPattern:(NSString *)pattern
                                        basePath:(nullable NSString *)basePath
                                           error:(NSError **)error;

// grep：正则逐行扫，返回命中列表；二进制/未下载文件跳过并计入 skippedPaths。
- (nullable NSArray<LAGrepMatch *> *)grepWithRegex:(NSString *)regex
                                          basePath:(NSString *)basePath
                                      includeGlobs:(nullable NSArray<NSString *> *)includeGlobs
                                      skippedPaths:(NSArray<NSString *> * _Nullable * _Nullable)skippedPaths
                                             error:(NSError **)error;

// picker 授权目录注册入口（UI 拿到安全作用域 URL 后调用方传入路径即可）。
- (void)addAuthorizedExternalDirectory:(NSString *)path;
- (void)removeAuthorizedExternalDirectory:(NSString *)path;

@end

#endif /* LA_SANDBOX_FILE_TOOLS_H */
