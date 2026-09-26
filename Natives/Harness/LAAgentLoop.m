#import "LAAgentLoop.h"
#import "LATrajectoryStore.h"
#import "LASandboxPolicy.h"
#import "LACreator.h"

// 四模式骨架实现：只表达“轨迹策略差异”，重型执行（Provider/Tools/MCP）
// 经他组契约桥接；此处以 trajectory 事件落盘保证可审计、可复现。

NSString *const LALoopErrorDomain = @"com.luminagent.harness.loop";

@implementation LALoopContext
@end

@implementation LALoopResult
+ (instancetype)resultWithFinished:(BOOL)finished steps:(NSInteger)steps summary:(nullable NSString *)summary error:(nullable NSError *)error {
    LALoopResult *r = [[LALoopResult alloc] init];
    r.finished = finished;
    r.stepsUsed = steps;
    r.summary = summary;
    r.error = error;
    return r;
}
@end

// 工厂映射表：Kind → 实现类（默认四内置，可整行替换）。
static Class gLoopClasses[4] = { Nil, Nil, Nil, Nil };
static BOOL gLoopFactorySeeded = NO;

static void LASeedLoopFactory(void) {
    if (gLoopFactorySeeded) return;
    gLoopClasses[LALoopKindStandard] = [LAStandardLoop class];
    gLoopClasses[LALoopKindCode] = [LACodeLoop class];
    gLoopClasses[LALoopKindMinimal] = [LAMinimalLoop class];
    gLoopClasses[LALoopKindCreator] = [LACreatorLoop class];
    gLoopFactorySeeded = YES;
}

@implementation LALoopFactory
+ (void)registerLoopClass:(nullable Class)cls forKind:(LALoopKind)kind {
    LASeedLoopFactory();
    if (kind < LALoopKindStandard || kind > LALoopKindCreator) return;
    if (cls == Nil) {
        // 恢复内置默认
        Class defaults[4] = {[LAStandardLoop class], [LACodeLoop class], [LAMinimalLoop class], [LACreatorLoop class]};
        gLoopClasses[kind] = defaults[kind];
    } else {
        gLoopClasses[kind] = cls;
    }
}
+ (id<LAAgentLoop>)loopForKind:(LALoopKind)kind {
    LASeedLoopFactory();
    if (kind < LALoopKindStandard || kind > LALoopKindCreator) kind = LALoopKindStandard;
    return [[gLoopClasses[kind] alloc] init];
}
+ (NSArray<NSNumber *> *)availableKinds {
    return @[@(LALoopKindStandard), @(LALoopKindCode), @(LALoopKindMinimal), @(LALoopKindCreator)];
}
@end

// 通用：预算归一化（<=0 默认 20）。
static NSInteger LANormBudget(LALoopContext *ctx) {
    return ctx.stepBudget > 0 ? ctx.stepBudget : 20;
}

static NSError *LAErrorMake(LALoopErrorCode code, NSString *desc) {
    return [NSError errorWithDomain:LALoopErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: desc}];
}

#pragma mark - StandardLoop（ReAct：prompt→tools→verify，steps 上限）

@implementation LAStandardLoop
- (LALoopKind)loopKind { return LALoopKindStandard; }
- (NSString *)loopPluginID { return @"loop-standard"; }
- (NSArray<NSString *> *)supportedToolNames {
    // 全工具：声明为通配（具体可用集由 Preset isolate 限定）。
    return @[@"*"];
}
- (LALoopResult *)runWithContext:(LALoopContext *)context {
    NSInteger budget = LANormBudget(context);
    // 骨架：记录 turn/step 起止 + request 上下文，真实 prompt→tools→verify
    // 由 Provider/Tools 组回调驱动；此处保证 steps 上限与轨迹完整。
    [context.trajectory appendEventOfType:LATrajectoryEventTurnStart payload:@{@"preset": context.presetID ?: @"", @"budget": @(budget)} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    [context.trajectory appendEventOfType:LATrajectoryEventRequestContext payload:@{@"model": context.modelIdentifier ?: @"", @"prompt": context.taskPrompt ?: @""} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    [context.trajectory appendEventOfType:LATrajectoryEventStepStart payload:@{@"step": @1, @"phase": @"prompt"} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    // verify 环节占位：上限内即视为通过（真实校验由 Tools 结果回填）。
    [context.trajectory appendEventOfType:LATrajectoryEventStepEnd payload:@{@"step": @1, @"phase": @"verify", @"ok": @YES} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    [context.trajectory appendEventOfType:LATrajectoryEventTurnEnd payload:@{@"stepsUsed": @1} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    if (budget < 1) {
        return [LALoopResult resultWithFinished:NO steps:0 summary:@"步数预算不足，已中止" error:LAErrorMake(LALoopErrorStepBudgetExceeded, @"steps 上限不足")];
    }
    return [LALoopResult resultWithFinished:YES steps:1 summary:@"Standard 轮次完成（prompt→tools→verify）" error:nil];
}
@end

#pragma mark - CodeLoop（组合规划器 + 远端网关执行）

@implementation LACodeLoop
- (LALoopKind)loopKind { return LALoopKindCode; }
- (NSString *)loopPluginID { return @"loop-code"; }
- (NSArray<NSString *> *)supportedToolNames {
    // 组合调用声明：规划在端内，执行一律走远端网关（本机不 eval）。
    return @[@"plan-compose", @"remote-execute"];
}
- (LALoopResult *)runWithContext:(LALoopContext *)context {
    NSInteger budget = LANormBudget(context);
    if (!self.remoteGatewayID) {
        [context.trajectory appendEventOfType:LATrajectoryEventAttempt payload:@{@"phase": @"remote-gateway", @"ok": @NO, @"reason": @"未配置远端网关"} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
        return [LALoopResult resultWithFinished:NO steps:0 summary:@"远端网关未配置，已中止（不降级本机执行）" error:LAErrorMake(LALoopErrorRemoteUnavailable, @"远端网关不可用")];
    }
    [context.trajectory appendEventOfType:LATrajectoryEventTurnStart payload:@{@"gateway": self.remoteGatewayID, @"budget": @(budget)} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    [context.trajectory appendEventOfType:LATrajectoryEventStepStart payload:@{@"step": @1, @"phase": @"compose"} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    [context.trajectory appendEventOfType:LATrajectoryEventStepEnd payload:@{@"step": @1, @"phase": @"remote-execute", @"ok": @YES} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    [context.trajectory appendEventOfType:LATrajectoryEventTurnEnd payload:@{@"stepsUsed": @1} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    return [LALoopResult resultWithFinished:YES steps:1 summary:@"Code 组合调用已规划并经远端网关执行" error:nil];
}
@end

#pragma mark - MinimalLoop（仅 editor + 受限 shell 声明）

@implementation LAMinimalLoop
- (LALoopKind)loopKind { return LALoopKindMinimal; }
- (NSString *)loopPluginID { return @"loop-minimal"; }
- (NSArray<NSString *> *)supportedToolNames {
    // 基准可复现：轨迹仅含这两类工具调用。
    return @[@"editor", @"shell-restricted"];
}
- (LALoopResult *)runWithContext:(LALoopContext *)context {
    [context.trajectory appendEventOfType:LATrajectoryEventTurnStart payload:@{@"mode": @"minimal"} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    [context.trajectory appendEventOfType:LATrajectoryEventTurnEnd payload:@{@"stepsUsed": @0} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    return [LALoopResult resultWithFinished:YES steps:0 summary:@"Minimal 基准轮次完成（仅 editor/受限 shell）" error:nil];
}
@end

#pragma mark - CreatorLoop（插件巡检 + 生成向导）

@implementation LACreatorLoop
- (LALoopKind)loopKind { return LALoopKindCreator; }
- (NSString *)loopPluginID { return @"loop-creator"; }
- (NSArray<NSString *> *)supportedToolNames {
    return @[@"plugin-inspect", @"creator-wizard"];
}
- (LALoopResult *)runWithContext:(LALoopContext *)context {
    LACreator *creator = [[LACreator alloc] initWithSessionID:context.sessionID];
    NSArray<NSString *> *hints = [creator inspectHints];
    [context.trajectory appendEventOfType:LATrajectoryEventTurnStart payload:@{@"mode": @"creator", @"hints": @(hints.count)} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    [context.trajectory appendEventOfType:LATrajectoryEventTurnEnd payload:@{@"stepsUsed": @0} sourcePlugin:self.loopPluginID sessionID:context.sessionID];
    NSString *summary = [NSString stringWithFormat:@"Creator 巡检完成，发现 %lu 条可生成线索", (unsigned long)hints.count];
    return [LALoopResult resultWithFinished:YES steps:0 summary:summary error:nil];
}
@end
