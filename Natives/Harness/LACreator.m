#import "LACreator.h"
#import "LATrajectoryStore.h"

NSString *const LACreatorErrorDomain = @"com.luminagent.harness.creator";

@implementation LACreatorDraft
- (instancetype)initWithDescription:(NSString *)desc {
    if (self = [super init]) {
        _draftID = [[NSUUID UUID] UUIDString];
        _userDescription = [desc copy] ?: @"";
        _questions = @[];
        _answers = @{};
        _stage = LACreatorStageDescribed;
    }
    return self;
}
@end

@interface LACreator ()
@property (nonatomic, copy) NSString *mutableSessionID;
@property (nonatomic, strong) NSMutableArray<LACreatorDraft *> *drafts;
@end

@implementation LACreator
- (instancetype)initWithSessionID:(NSString *)sessionID {
    if (self = [super init]) {
        _mutableSessionID = [sessionID copy] ?: @"";
        _drafts = [NSMutableArray array];
    }
    return self;
}
- (NSString *)sessionID { return _mutableSessionID; }

- (NSArray<NSString *> *)inspectHints {
    // 运行时巡检：返回缺口线索（真实巡检读注册表 dump，此处给启发式三条）。
    return @[
        @"未发现只读外部数据插件（如 Jira 只读），可用 Creator 一键生成",
        @"远端 subagent 插件未注册，强模型委派能力缺失",
        @"沙盒后端无 XPC helper 声明，写文件将 fail-closed",
    ];
}

- (LACreatorDraft *)startDraftWithDescription:(NSString *)desc {
    LACreatorDraft *d = [[LACreatorDraft alloc] initWithDescription:desc ?: @""];
    [self.drafts addObject:d];
    [self.trajectory appendEventOfType:LATrajectoryEventTurnStart payload:@{@"creator": @"describe", @"draft": d.draftID} sourcePlugin:@"loop-creator" sessionID:self.mutableSessionID];
    return d;
}

- (NSArray<NSString *> *)clarifyQuestionsForDraft:(LACreatorDraft *)draft {
    // 按描述启发式出澄清问：Jira 类追问 host/鉴权范围，其余走通用三问。
    NSString *desc = draft.userDescription ?: @"";
    if ([desc rangeOfString:@"jira" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        draft.questions = @[@"Jira 站点 host 是什么？", @"只读范围是否仅限浏览 issue（不含写/转派）？", @"鉴权 token 由谁保管（Keychain 还是会话内存）？"];
    } else {
        draft.questions = @[@"这个能力需要哪类工具（只读/写文件/网络）？", @"适用哪个 Preset 会话？", @"是否允许落盘为 profile+patch（重启保留）？"];
    }
    draft.stage = LACreatorStageClarifying;
    return draft.questions;
}

- (void)answerDraft:(LACreatorDraft *)draft answers:(NSDictionary<NSString *, NSString *> *)answers {
    draft.answers = [answers copy] ?: @{};
}

- (nullable NSString *)generateManifestForDraft:(LACreatorDraft *)draft error:(NSError **)error {
    // 澄清答完才可生成（缺答即报 NeedClarify，不静默编造）。
    for (NSString *q in draft.questions) {
        if (!draft.answers[q].length) {
            if (error) *error = [NSError errorWithDomain:LACreatorErrorDomain code:LACreatorErrorNeedClarify userInfo:@{NSLocalizedDescriptionKey: @"澄清问未答完，暂不生成"}];
            return nil;
        }
    }
    NSString *pid = [NSString stringWithFormat:@"creator-%@", [draft.draftID substringToIndex:MIN(8, draft.draftID.length)].lowercaseString];
    NSDictionary *manifest = @{
        @"id": pid,
        @"slot": @"tools",
        @"version": @"0.1",
        @"enabled": @YES,
        @"desc": draft.userDescription ?: @"",
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:error];
    if (!data) {
        if (error && !*error) *error = [NSError errorWithDomain:LACreatorErrorDomain code:LACreatorErrorBadManifest userInfo:@{NSLocalizedDescriptionKey: @"生成清单失败"}];
        return nil;
    }
    draft.generatedManifestJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    draft.stage = LACreatorStageAwaitingSignoff;
    [self.trajectory appendEventOfType:LATrajectoryEventPluginExt payload:@{@"extKind": @"creator-generate", @"draft": draft.draftID} sourcePlugin:@"loop-creator" sessionID:self.mutableSessionID];
    return draft.generatedManifestJSON;
}

- (void)requestSignoffForDraft:(LACreatorDraft *)draft
                         asker:(id)asker
                    completion:(void (^)(BOOL, NSError * _Nullable))completion {
    // 签核硬门：asker 为空或无 ask 能力即失败，不自动放行。
    // asker 须响应 askPermission:（LAPermissionAsking 契约，前向声明，不导入他组头）。
    SEL askSel = NSSelectorFromString(@"askPermission:");
    if (!asker || ![asker respondsToSelector:askSel]) {
        if (completion) completion(NO, [NSError errorWithDomain:LACreatorErrorDomain code:LACreatorErrorNeedSignoff userInfo:@{NSLocalizedDescriptionKey: @"签核器不可用，拒绝安装（先签核再安装）"}]);
        return;
    }
    // ask 参数为权限请求体（由 Tools 组 LAPermissionRequest 定义，此处用字典转述避免重复定义类型）。
    id request = nil;
    Class reqCls = NSClassFromString(@"LAPermissionRequest");
    SEL reqSel = NSSelectorFromString(@"requestWithTool:target:reason:");
    if (reqCls && [reqCls respondsToSelector:reqSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        request = [reqCls performSelector:reqSel withObject:@"creator-install" withObject:draft.generatedManifestJSON withObject:@"Creator 请求安装新插件"];
#pragma clang diagnostic pop
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSInteger decision = (NSInteger)[asker performSelector:askSel withObject:request];
#pragma clang diagnostic pop
    // 约定：LAPermissionDecisionAllow == 1 为通过（与 Tools 组枚举值对齐）。
    BOOL approved = (decision == 1);
    if (approved) draft.stage = LACreatorStageStaged;
    [self.trajectory appendEventOfType:LATrajectoryEventPluginExt payload:@{@"extKind": @"creator-signoff", @"approved": @(approved), @"draft": draft.draftID} sourcePlugin:@"loop-creator" sessionID:self.mutableSessionID];
    if (completion) completion(approved, nil);
}

- (BOOL)installDraft:(LACreatorDraft *)draft error:(NSError **)error {
    // 未签核不可安装（硬门）。
    if (draft.stage != LACreatorStageStaged && draft.stage != LACreatorStageInstalled) {
        if (error) *error = [NSError errorWithDomain:LACreatorErrorDomain code:LACreatorErrorNeedSignoff userInfo:@{NSLocalizedDescriptionKey: @"未经签核，拒绝安装"}];
        return NO;
    }
    if (!draft.generatedManifestJSON.length) {
        if (error) *error = [NSError errorWithDomain:LACreatorErrorDomain code:LACreatorErrorBadManifest userInfo:@{NSLocalizedDescriptionKey: @"清单为空，无法安装"}];
        return NO;
    }
    draft.stage = LACreatorStageInstalled;
    [self.trajectory appendEventOfType:LATrajectoryEventPluginExt payload:@{@"extKind": @"creator-install", @"draft": draft.draftID} sourcePlugin:@"loop-creator" sessionID:self.mutableSessionID];
    return YES;
}

- (NSArray<LACreatorDraft *> *)stagedDrafts { return [self.drafts copy]; }
- (void)removeDraft:(LACreatorDraft *)draft { [self.drafts removeObject:draft]; }

+ (NSString *)jiraReadonlyPresetID { return @"preset-jira-readonly"; }
+ (NSString *)jiraReadonlyPresetManifest {
    // Jira 只读示例 preset：单目录分发单元（工具+prompt+skills 清单），isolate 按 session 隔离。
    return @"{\"id\":\"preset-jira-readonly\",\"slot\":\"tools\",\"version\":\"1.0\",\"enabled\":true,"
           @"\"preset\":{\"tools\":[\"jira-issue-read\",\"jira-search\"],"
           @"\"prompt\":\"只读访问 Jira issue，禁止写/转派/删评\","
           @"\"skills\":[],\"sandbox\":\"read-only\"}}";
}
@end
