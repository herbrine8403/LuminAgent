// LASkillLoader.m — Skills 发现与加载实现（中文注释）。
#import "LASkillLoader.h"

@implementation LASkill
@end

@interface LASkillLoader ()
// 已加载 skills（按优先级排序）。
@property (nonatomic, copy) NSArray<LASkill *> *loadedSkills;
// 告警事件累计。
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableWarnings;
@end

@implementation LASkillLoader

// 全局单例。
+ (instancetype)sharedLoader {
    static LASkillLoader *sInstance = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sInstance = [[LASkillLoader alloc] init];
    });
    return sInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _loadedSkills = @[];
        _mutableWarnings = [NSMutableArray array];
    }
    return self;
}

// 按优先级全量扫描并重建索引。
- (void)reloadWithProjectRoot:(NSString *)projectRoot
             bundledSkillRoot:(NSString *)bundledSkillRoot {
    NSMutableArray<LASkill *> *ordered = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    // 1. 项目 .agent/skills
    if (projectRoot.length > 0) {
        NSString *dir = [projectRoot stringByAppendingPathComponent:@".agent/skills"];
        [self scanSkillDir:dir scope:LASkillScopeProject into:ordered seen:seen];
    }
    // 2. 内置包
    if (bundledSkillRoot.length > 0) {
        [self scanSkillDir:bundledSkillRoot scope:LASkillScopeBundled into:ordered seen:seen];
    }
    // 3/4. 兼容目录（相对项目根）。
    if (projectRoot.length > 0) {
        NSString *claude = [projectRoot stringByAppendingPathComponent:@".claude/skills"];
        [self scanSkillDir:claude scope:LASkillScopeClaude into:ordered seen:seen];
        NSString *agents = [projectRoot stringByAppendingPathComponent:@".agents/skills"];
        [self scanSkillDir:agents scope:LASkillScopeAgents into:ordered seen:seen];
    }
    @synchronized (self) {
        self.loadedSkills = [ordered copy];
    }
}

- (NSArray<LASkill *> *)allSkills {
    @synchronized (self) {
        return self.loadedSkills;
    }
}

- (nullable LASkill *)skillNamed:(NSString *)name {
    if (name.length == 0) { return nil; }
    @synchronized (self) {
        for (LASkill *skill in self.loadedSkills) {
            if ([skill.name isEqualToString:name]) { return skill; }
        }
    }
    return nil;
}

// 注入给模型的 skill 列表块（仅 name + description，供模型自选）。
- (NSString *)promptInjectionBlock {
    NSArray<LASkill *> *skills = [self allSkills];
    if (skills.count == 0) { return @"# 可用 Skills\n（无）"; }
    NSMutableString *out = [NSMutableString stringWithString:@"# 可用 Skills（按需用 skill 工具加载正文）\n"];
    for (LASkill *skill in skills) {
        [out appendFormat:@"- %@: %@\n", skill.name, skill.skillDescription];
    }
    return [out copy];
}

- (NSArray<NSString *> *)warnings {
    @synchronized (self) {
        return [self.mutableWarnings copy];
    }
}

- (void)clearWarnings {
    @synchronized (self) {
        [self.mutableWarnings removeAllObjects];
    }
}

#pragma mark - 内部

// 扫描单个 skills 目录：每个子目录的 SKILL.md 为一条 skill。
- (void)scanSkillDir:(NSString *)dir
               scope:(LASkillScope)scope
                into:(NSMutableArray<LASkill *> *)ordered
                seen:(NSMutableSet<NSString *> *)seen {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) { return; }
    NSError *listError = nil;
    NSArray<NSString *> *children =
        [fm contentsOfDirectoryAtPath:dir error:&listError];
    if (children == nil) {
        [self emitWarning:[NSString stringWithFormat:@"无法列出 skill 目录：%@", dir]];
        return;
    }
    // 排序保证结果稳定。
    children = [children sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *child in children) {
        NSString *skillFile =
            [[dir stringByAppendingPathComponent:child]
                stringByAppendingPathComponent:@"SKILL.md"];
        if (![fm fileExistsAtPath:skillFile]) { continue; }
        LASkill *skill = [self loadSkillFile:skillFile scope:scope];
        if (skill == nil) { continue; } // 缺字段已告警并跳过。
        if ([seen containsObject:skill.name]) { continue; } // 同名高优先级胜出。
        [seen addObject:skill.name];
        [ordered addObject:skill];
    }
}

// 加载单个 SKILL.md：校验 name/description 前言，缺失跳过 + 告警。
- (nullable LASkill *)loadSkillFile:(NSString *)path scope:(LASkillScope)scope {
    NSError *readError = nil;
    NSString *content =
        [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
    if (content == nil) {
        [self emitWarning:[NSString stringWithFormat:@"无法读取 SKILL.md：%@（%@）",
                           path, readError.localizedDescription ?: @"未知错误"]];
        return nil;
    }
    NSString *frontmatter = [self frontmatterOfMarkdown:content];
    NSString *name = [self frontmatterValueForKey:@"name" in:frontmatter];
    NSString *desc = [self frontmatterValueForKey:@"description" in:frontmatter];
    if (name.length == 0 || desc.length == 0) {
        [self emitWarning:[NSString stringWithFormat:@"SKILL.md 缺 name/description，已跳过：%@", path]];
        return nil;
    }
    // 同名规范化：取前言 name 为准。
    name = [name stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    desc = [desc stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // 去掉首尾引号（description 常带引号）。
    desc = [self stripSurroundingQuotes:desc];
    LASkill *skill = [[LASkill alloc] init];
    skill.name = name;
    skill.skillDescription = desc;
    skill.body = [self bodyOfMarkdown:content];
    skill.sourcePath = path;
    skill.scope = scope;
    return skill;
}

// 取 markdown 顶部 --- 前言块（无则返回 nil）。
- (nullable NSString *)frontmatterOfMarkdown:(NSString *)markdown {
    if (![markdown hasPrefix:@"---"]) { return nil; }
    NSRange firstLineEnd = [markdown rangeOfString:@"\n"];
    if (firstLineEnd.location == NSNotFound) { return nil; }
    NSUInteger start = NSMaxRange(firstLineEnd);
    NSRange close = [markdown rangeOfString:@"\n---"
                                    options:0
                                      range:NSMakeRange(start, markdown.length - start)];
    if (close.location == NSNotFound) { return nil; }
    return [markdown substringWithRange:NSMakeRange(start, close.location - start)];
}

// 去前言正文。
- (NSString *)bodyOfMarkdown:(NSString *)markdown {
    NSString *frontmatter = [self frontmatterOfMarkdown:markdown];
    if (frontmatter == nil) { return markdown; }
    // 正文 = 第二个 --- 行之后。
    NSRange firstLineEnd = [markdown rangeOfString:@"\n"];
    NSUInteger start = NSMaxRange(firstLineEnd);
    NSRange close = [markdown rangeOfString:@"\n---"
                                    options:0
                                      range:NSMakeRange(start, markdown.length - start)];
    if (close.location == NSNotFound) { return markdown; }
    NSUInteger bodyStart = NSMaxRange(close);
    // 跳过紧随的换行。
    while (bodyStart < markdown.length &&
           [markdown characterAtIndex:bodyStart] == '\n') { bodyStart++; }
    // 跳过可能的 --- 行尾残留。
    if (bodyStart < markdown.length &&
        [markdown characterAtIndex:bodyStart] == '-' ) {
        NSRange nl = [markdown rangeOfString:@"\n"
                                     options:0
                                       range:NSMakeRange(bodyStart, markdown.length - bodyStart)];
        if (nl.location != NSNotFound) { bodyStart = NSMaxRange(nl); }
    }
    if (bodyStart >= markdown.length) { return @""; }
    return [markdown substringFromIndex:bodyStart];
}

// 前言 key: value 取值（大小写敏感）。
- (nullable NSString *)frontmatterValueForKey:(NSString *)key in:(nullable NSString *)frontmatter {
    if (frontmatter == nil || key.length == 0) { return nil; }
    NSArray<NSString *> *lines = [frontmatter componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed =
            [line stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![trimmed hasPrefix:key]) { continue; }
        NSString *rest = [trimmed substringFromIndex:key.length];
        rest = [rest stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];
        if (![rest hasPrefix:@":"]) { continue; }
        rest = [rest substringFromIndex:1];
        rest = [rest stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return rest.length > 0 ? rest : nil;
    }
    return nil;
}

// 去首尾成对引号。
- (NSString *)stripSurroundingQuotes:(NSString *)text {
    if (text.length >= 2) {
        unichar first = [text characterAtIndex:0];
        unichar last = [text characterAtIndex:text.length - 1];
        if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
            return [text substringWithRange:NSMakeRange(1, text.length - 2)];
        }
    }
    return text;
}

// 记录告警并触发回调。
- (void)emitWarning:(NSString *)message {
    LASkillWarningHandler handler = nil;
    @synchronized (self) {
        [self.mutableWarnings addObject:message];
        handler = self.warningHandler;
    }
    if (handler) { handler(message); }
}

@end
