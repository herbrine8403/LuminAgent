#ifndef LA_INPUT_PARSER_H
#define LA_INPUT_PARSER_H

#import <Foundation/Foundation.h>

// 输入语法解析契约（tasks 5.4）。
// 解析 @path 文件引用、@agent 子 Agent 调用、!command shell 输出附加、Tab 切换主 Agent。

// 解析结果。
@interface LAParsedInput : NSObject
@property (nonatomic, copy) NSString *originalText;              // 原始输入
@property (nonatomic, copy) NSString *plainText;                 // 去标记后的正文
@property (nonatomic, copy) NSArray<NSString *> *fileRefs;       // @path 列表
@property (nonatomic, copy) NSArray<NSString *> *agentRefs;      // @agent 列表
@property (nonatomic, copy) NSArray<NSString *> *shellCommands;  // !command 列表
@property (nonatomic, copy, nullable) NSString *slashCommand;    // 开头 /命令（如有）
@property (nonatomic, copy) NSArray<NSString *> *slashArgs;      // slash 参数
@property (nonatomic, assign) BOOL wantsTabSwitch;               // 是否请求 Tab 切换主 Agent
@end

@interface LAInputParser : NSObject

// 全局单例。
+ (instancetype)sharedParser;

// 解析单行/多行输入（纯解析，不做 IO；注入由会话执行侧完成）。
- (LAParsedInput *)parseInput:(nullable NSString *)text;

@end

#endif /* LA_INPUT_PARSER_H */
