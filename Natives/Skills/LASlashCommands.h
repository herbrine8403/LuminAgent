#ifndef LA_SLASH_COMMANDS_H
#define LA_SLASH_COMMANDS_H

#import <Foundation/Foundation.h>

// 内置 slash 命令注册表契约（tasks 5.2）。
// 必含：/init /new /sessions /compact /undo /redo /share /unshare
//      /models /connect /themes /export /stats，语义与 OpenCode 对齐。

// 命令处理回调：args 为解析后的参数字典（argv/rawText 至少其一）。
typedef void (^LASlashHandler)(NSDictionary *args);

// 单条命令描述。
@interface LASlashCommand : NSObject
@property (nonatomic, copy) NSString *name;        // 如 @"init"（不含斜杠）
@property (nonatomic, copy) NSString *cmdDescription; // 说明文本
@property (nonatomic, assign) BOOL builtin;        // 是否内置（自定义同名可覆盖）
@property (nonatomic, copy, nullable) LASlashHandler handler;
@end

@interface LASlashCommands : NSObject

// 全局单例（初始化即注册全部内置命令）。
+ (instancetype)sharedCommands;

// 内置命令名列表（12 个）。
+ (NSArray<NSString *> *)builtinCommandNames;

// 注册/覆盖命令（自定义命令同名覆盖内置时 builtin=NO）。
- (void)registerCommand:(NSString *)name
            description:(NSString *)description
                builtin:(BOOL)builtin
                handler:(nullable LASlashHandler)handler;

// 按名取命令（不含斜杠，@"init"）；不存在返回 nil。
- (nullable LASlashCommand *)commandNamed:(NSString *)name;

// 是否为内置命令名。
- (BOOL)isBuiltinCommand:(NSString *)name;

// 全部命令（内置 + 自定义覆盖后）。
- (NSArray<LASlashCommand *> *)allCommands;

// /init 生成的 AGENTS.md 模板（项目记忆；会话执行侧负责分析目录后落盘）。
- (NSString *)agentsTemplateForInitWithProjectName:(nullable NSString *)projectName;

@end

#endif /* LA_SLASH_COMMANDS_H */
