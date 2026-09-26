#ifndef LA_COMMAND_PARSER_H
#define LA_COMMAND_PARSER_H

#import <Foundation/Foundation.h>

// 自定义命令模板解析与展开契约（tasks 5.3）。
//
// 自定义命令为 markdown 文件，前 matter 支持：
//   description / agent / model / subtask
// 正文为提示模板，支持：
//   $ARGUMENTS（全部参数原文）、$1/$2（位置参数）、
//   @path（文件注入）、!shell（shell 输出注入）。
// 同名自定义命令覆盖内置 slash 命令。

// 文件内容读取回调（@path 注入用，返回文件文本，失败返回 nil）。
typedef NSString *_Nullable (^LAFileReader)(NSString *path);
// shell 输出回调（!shell 注入用，返回命令 stdout 文本）。
typedef NSString *_Nullable (^LAShellRunner)(NSString *shellCommand);

// 自定义命令模板。
@interface LACommandTemplate : NSObject
@property (nonatomic, copy) NSString *name;                 // 文件名去扩展，如 test-until-green
@property (nonatomic, copy) NSString *templateDescription;  // 前 matter description
@property (nonatomic, copy, nullable) NSString *agentName;  // 前 matter agent
@property (nonatomic, copy, nullable) NSString *modelName;  // 前 matter model
@property (nonatomic, assign) BOOL subtask;                 // 前 matter subtask（子任务执行）
@property (nonatomic, copy) NSString *templateText;         // 去前 matter 正文模板
@property (nonatomic, copy, nullable) NSString *sourcePath; // 来源文件路径
@end

@interface LACommandParser : NSObject

// 全局单例。
+ (instancetype)sharedParser;

// 已加载自定义命令（name → template）。
- (NSDictionary<NSString *, LACommandTemplate *> *)customCommands;

// 从 markdown 文本加载一条自定义命令（name 为文件名去扩展）。
// 成功返回模板，失败返回 nil 并经 error 说明原因。
- (nullable LACommandTemplate *)loadCustomCommandFromMarkdown:(NSString *)markdown
                                                        name:(NSString *)name
                                                  sourcePath:(nullable NSString *)sourcePath
                                                       error:(NSError **)error;

// 按名取生效模板：自定义优先（覆盖内置），否则用 fallbackBuiltinTemplate。
- (nullable LACommandTemplate *)commandForName:(NSString *)name
                        fallbackBuiltinTemplate:(nullable LACommandTemplate *)fallback;

// 展开模板：$ARGUMENTS/$1/$2 + @path 文件注入 + !shell 输出注入。
// arguments 为位置参数数组；fileReader/shellRunner 为 nil 时对应注入保留原文。
- (nullable NSString *)expandedPromptForCommand:(LACommandTemplate *)command
                                     arguments:(NSArray<NSString *> *)arguments
                                    fileReader:(nullable LAFileReader)fileReader
                                    shellRunner:(nullable LAShellRunner)shellRunner
                                          error:(NSError **)error;

// 自测：test-until-green 模板展开用例。
// 构造含 $ARGUMENTS/$1/$2/@path/!shell 的模板，用桩回调展开并断言结果；
// 通过返回 YES（result 为展开文本），失败返回 NO（error 说明）。
+ (BOOL)selfTestTestUntilGreenWithResult:(NSString **)result
                                   error:(NSError **)error;

@end

#endif /* LA_COMMAND_PARSER_H */
