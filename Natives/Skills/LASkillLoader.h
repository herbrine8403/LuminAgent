#ifndef LA_SKILL_LOADER_H
#define LA_SKILL_LOADER_H

#import <Foundation/Foundation.h>

// Skills 发现与加载契约（tasks 5.1）。
//
// 扫描优先级（高→低）：
//   1. 项目 .agent/skills/*/SKILL.md
//   2. 内置包（随 App 预置，含 Superpowers 离线 skills）
//   3. 兼容 .claude/skills/*/SKILL.md
//   4. 兼容 .agents/skills/*/SKILL.md
// 同名 skill 高优先级胜出；SKILL.md 缺 name/description 则跳过并记录告警事件。

// Skill 归属域。
typedef NS_ENUM(NSInteger, LASkillScope) {
    LASkillScopeProject = 0, // 项目 .agent/skills
    LASkillScopeBundled,     // 内置预置包
    LASkillScopeClaude,      // 兼容 .claude/skills
    LASkillScopeAgents       // 兼容 .agents/skills
};

// 单个 skill 条目（仅元数据 + 正文；正文懒加载亦可直接持有）。
@interface LASkill : NSObject
@property (nonatomic, copy) NSString *name;        // 前言 name（必填）
@property (nonatomic, copy) NSString *skillDescription; // 前言 description（必填）
@property (nonatomic, copy) NSString *body;        // SKILL.md 去前言正文
@property (nonatomic, copy) NSString *sourcePath;  // SKILL.md 全路径
@property (nonatomic, assign) LASkillScope scope;  // 来源域
@end

// 告警事件回调：SKILL.md 缺字段/不可读时触发（缺失跳过 + 告警）。
typedef void (^LASkillWarningHandler)(NSString *warningMessage);

@interface LASkillLoader : NSObject

// 全局单例。
+ (instancetype)sharedLoader;

// 按优先级全量扫描并重建索引。同名仅保留高优先级者。
// projectRoot: 项目根目录；bundledSkillRoot: 内置包 Skills 根目录。
- (void)reloadWithProjectRoot:(NSString *)projectRoot
             bundledSkillRoot:(NSString *)bundledSkillRoot;

// 全部已加载 skills（按优先级排序）。
- (NSArray<LASkill *> *)allSkills;

// 按名取 skill（不存在返回 nil）。
- (nullable LASkill *)skillNamed:(NSString *)name;

// 注入给模型的 skill 列表块（供模型自选加载正文，仅 name + description）。
- (NSString *)promptInjectionBlock;

// 告警事件列表（累计，可用于上报会话执行侧）。
- (NSArray<NSString *> *)warnings;

// 清空告警事件。
- (void)clearWarnings;

// 告警回调（可选，会话执行侧可订阅落盘/上报）。
@property (nonatomic, copy, nullable) LASkillWarningHandler warningHandler;

@end

#endif /* LA_SKILL_LOADER_H */
