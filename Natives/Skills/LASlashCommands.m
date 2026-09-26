// LASlashCommands.m — 内置 slash 命令注册表实现（中文注释）。
#import "LASlashCommands.h"

@implementation LASlashCommand
@end

@interface LASlashCommands ()
// 命令表（name → command）。
@property (nonatomic, strong) NSMutableDictionary<NSString *, LASlashCommand *> *table;
@end

@implementation LASlashCommands

// 全局单例（初始化即注册全部内置命令）。
+ (instancetype)sharedCommands {
    static LASlashCommands *sInstance = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sInstance = [[LASlashCommands alloc] init];
        [sInstance registerBuiltins];
    });
    return sInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _table = [NSMutableDictionary dictionary];
    }
    return self;
}

// 内置命令名列表（12 个，与 OpenCode 语义对齐）。
+ (NSArray<NSString *> *)builtinCommandNames {
    return @[@"init", @"new", @"sessions", @"compact", @"undo", @"redo",
             @"share", @"unshare", @"models", @"connect", @"themes",
             @"export", @"stats"];
}

- (void)registerCommand:(NSString *)name
            description:(NSString *)description
                builtin:(BOOL)builtin
                handler:(nullable LASlashHandler)handler {
    if (name.length == 0) { return; }
    LASlashCommand *cmd = [[LASlashCommand alloc] init];
    cmd.name = name;
    cmd.cmdDescription = description ?: @"";
    cmd.builtin = builtin;
    cmd.handler = handler;
    @synchronized (self) {
        self.table[name] = cmd;
    }
}

- (nullable LASlashCommand *)commandNamed:(NSString *)name {
    if (name.length == 0) { return nil; }
    // 容忍前导斜杠。
    NSString *key = [name hasPrefix:@"/"] ? [name substringFromIndex:1] : name;
    @synchronized (self) {
        return self.table[key];
    }
}

- (BOOL)isBuiltinCommand:(NSString *)name {
    NSString *key = [name hasPrefix:@"/"] ? [name substringFromIndex:1] : name;
    return [[[self class] builtinCommandNames] containsObject:key];
}

- (NSArray<LASlashCommand *> *)allCommands {
    @synchronized (self) {
        NSArray *names = [[[self.table allKeys]
            sortedArrayUsingSelector:@selector(compare:)] copy];
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:names.count];
        for (NSString *key in names) { [out addObject:self.table[key]]; }
        return [out copy];
    }
}

// /init 生成的 AGENTS.md 模板（项目记忆；执行侧分析目录后落盘，后续会话自动载入）。
- (NSString *)agentsTemplateForInitWithProjectName:(nullable NSString *)projectName {
    NSString *title = projectName.length > 0 ? projectName : @"<项目名>";
    return [NSString stringWithFormat:
        @"# AGENTS.md — %@\n"
        @"\n"
        @"<!-- 由 LuminAgent /init 生成；后续会话自动载入。 -->\n"
        @"\n"
        @"## 项目简介\n"
        @"- 名称：%@\n"
        @"- 一句话描述：<填写>\n"
        @"\n"
        @"## 构建与运行\n"
        @"- 构建命令：<填写>\n"
        @"- 运行命令：<填写>\n"
        @"- 测试命令：<填写>\n"
        @"\n"
        @"## 目录约定\n"
        @"- <目录>：<用途>\n"
        @"\n"
        @"## 代码风格\n"
        @"- <语言/规范>\n"
        @"\n"
        @"## 注意事项\n"
        @"- <禁忌/坑点>\n", title, title];
}

#pragma mark - 内部

// 注册 12 个内置命令（默认 handler 为 nil，由会话执行侧绑定真实行为）。
- (void)registerBuiltins {
    [self registerCommand:@"init" description:@"分析目录并生成 AGENTS.md 项目记忆" builtin:YES handler:nil];
    [self registerCommand:@"new" description:@"开始新会话" builtin:YES handler:nil];
    [self registerCommand:@"sessions" description:@"列出/切换历史会话" builtin:YES handler:nil];
    [self registerCommand:@"compact" description:@"压缩上下文（摘要替换历史）" builtin:YES handler:nil];
    [self registerCommand:@"undo" description:@"撤销上一步文件变更（需 Git）" builtin:YES handler:nil];
    [self registerCommand:@"redo" description:@"重做已撤销的变更" builtin:YES handler:nil];
    [self registerCommand:@"share" description:@"分享当前会话" builtin:YES handler:nil];
    [self registerCommand:@"unshare" description:@"取消会话分享" builtin:YES handler:nil];
    [self registerCommand:@"models" description:@"列出/切换模型" builtin:YES handler:nil];
    [self registerCommand:@"connect" description:@"连接远程/账号" builtin:YES handler:nil];
    [self registerCommand:@"themes" description:@"列出/切换主题" builtin:YES handler:nil];
    [self registerCommand:@"export" description:@"导出会话记录" builtin:YES handler:nil];
    [self registerCommand:@"stats" description:@"查看用量统计" builtin:YES handler:nil];
}

@end
