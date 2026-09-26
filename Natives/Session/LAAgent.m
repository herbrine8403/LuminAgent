#import "LAAgent.h"
#import "LAErrors.h"

/* Agent 实现：模式级工具准入 + 深度约束 + 切换映射 */

const NSInteger kLAMaxSubagentDepth = 3;

NSString * const LAAgentMentionBuild = @"@build";
NSString * const LAAgentMentionPlan = @"@plan";
NSString * const LAAgentMentionGeneral = @"@general";
NSString * const LAAgentMentionExplore = @"@explore";

@implementation LAAgent

- (instancetype)initWithKind:(LAAgentKind)kind
                       depth:(NSInteger)depth
                   sessionID:(NSString *)sessionID
                       error:(NSError **)error {
    if (depth < 0 || depth > kLAMaxSubagentDepth) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"嵌套深度 %ld 超出上限 %ld",
                              (long)depth, (long)kLAMaxSubagentDepth];
            *error = LAErrorWithCode(LAErrorCodeDepthExceeded, desc);
        }
        return nil;
    }
    self = [super init];
    if (self) {
        _kind = kind;
        _depth = depth;
        _sessionID = [sessionID copy];
    }
    return self;
}

- (BOOL)isSubagent {
    return self.kind == LAAgentKindGeneral || self.kind == LAAgentKindExplore;
}

- (NSString *)name {
    return [[self class] displayNameForKind:self.kind];
}

/* 模式级写工具集合：write/edit/bash */
- (BOOL)isWriteTool:(NSString *)toolName {
    NSString *lower = [toolName lowercaseString];
    return [lower isEqualToString:@"write"] ||
           [lower isEqualToString:@"edit"] ||
           [lower isEqualToString:@"bash"];
}

- (BOOL)isEditWriteTool:(NSString *)toolName {
    NSString *lower = [toolName lowercaseString];
    return [lower isEqualToString:@"write"] || [lower isEqualToString:@"edit"];
}

- (BOOL)canUseTool:(NSString *)toolName error:(NSError **)error {
    NSString *tool = toolName ?: @"";
    /* Plan 主代理：write/edit/bash 默认拒绝，返回取消事件说明 */
    if (self.kind == LAAgentKindPlan && [self isWriteTool:tool]) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:
                              @"Plan 模式不执行 %@，仅输出计划与差异预览（批准后可转 Build 执行）", tool];
            *error = LAErrorWithCode(LAErrorCodePlanDenied, desc);
        }
        return NO;
    }
    /* Explore 子代理：edit/write/bash 一律拒绝，只读检索 */
    if (self.kind == LAAgentKindExplore &&
        ([self isEditWriteTool:tool] || [[tool lowercaseString] isEqualToString:@"bash"])) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Explore 为只读代理，不可调用 %@，仅返回路径与匹配摘要", tool];
            *error = LAErrorWithCode(LAErrorCodePermissionDenied, desc);
        }
        return NO;
    }
    return YES;
}

- (LAAgent *)spawnSubagentWithKind:(LAAgentKind)kind error:(NSError **)error {
    /* Explore 只读代理不可派生可写代理，防止权限逃逸 */
    if (self.kind == LAAgentKindExplore &&
        (kind == LAAgentKindBuild || kind == LAAgentKindGeneral)) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodePermissionDenied,
                                     @"Explore 只读代理不可派生可写子代理");
        }
        return nil;
    }
    return [[LAAgent alloc] initWithKind:kind
                                  depth:self.depth + 1
                              sessionID:self.sessionID
                                  error:error];
}

+ (LAAgentKind)kindForTabIndex:(NSUInteger)index {
    return index == 1 ? LAAgentKindPlan : LAAgentKindBuild;
}

+ (BOOL)kindForMention:(NSString *)mention outKind:(LAAgentKind *)outKind {
    NSString *lower = [[mention lowercaseString] stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    LAAgentKind kind = LAAgentKindBuild;
    if ([lower isEqualToString:LAAgentMentionBuild]) {
        kind = LAAgentKindBuild;
    } else if ([lower isEqualToString:LAAgentMentionPlan]) {
        kind = LAAgentKindPlan;
    } else if ([lower isEqualToString:LAAgentMentionGeneral]) {
        kind = LAAgentKindGeneral;
    } else if ([lower isEqualToString:LAAgentMentionExplore]) {
        kind = LAAgentKindExplore;
    } else {
        return NO;
    }
    if (outKind) {
        *outKind = kind;
    }
    return YES;
}

+ (NSString *)mentionForKind:(LAAgentKind)kind {
    switch (kind) {
        case LAAgentKindBuild:   return LAAgentMentionBuild;
        case LAAgentKindPlan:    return LAAgentMentionPlan;
        case LAAgentKindGeneral: return LAAgentMentionGeneral;
        case LAAgentKindExplore: return LAAgentMentionExplore;
    }
    return LAAgentMentionBuild;
}

+ (NSString *)displayNameForKind:(LAAgentKind)kind {
    switch (kind) {
        case LAAgentKindBuild:   return @"build";
        case LAAgentKindPlan:    return @"plan";
        case LAAgentKindGeneral: return @"general";
        case LAAgentKindExplore: return @"explore";
    }
    return @"build";
}

@end
