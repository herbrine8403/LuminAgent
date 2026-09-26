#ifndef LA_CREATOR_H
#define LA_CREATOR_H

#import <Foundation/Foundation.h>

// Creator 自扩展闭环：自然语言描述新能力 → 澄清问 → 生成插件 → 签核（权限 ask）
// → 安装上架（出现在插件列表）。动态生成插件驻内存（重启消失），
// 落盘靠 profile+patch 文件（由调用方导出 manifest 落盘）。
// 内置 Jira 只读示例 preset，可一键启用。

NS_ASSUME_NONNULL_BEGIN

// 他组类型前向声明（权限 ask 回调归 Tools 组实现，此处不定义只引用）。
@protocol LAPermissionAsking;
@class LATrajectoryStore;

// Creator 草稿阶段（闭环状态机）。
typedef NS_ENUM(NSInteger, LACreatorStage) {
    LACreatorStageDescribed       = 0, // 已收描述，待澄清
    LACreatorStageClarifying      = 1, // 澄清问答中
    LACreatorStageAwaitingSignoff = 2, // 已生成，待签核（ask）
    LACreatorStageStaged          = 3, // 已签核，暂存待安装
    LACreatorStageInstalled       = 4, // 已安装上架
};

// 单个生成草稿（内存对象，重启消失）。
@interface LACreatorDraft : NSObject
@property (nonatomic, copy, readonly) NSString *draftID;
@property (nonatomic, copy) NSString *userDescription;          // 自然语言描述
@property (nonatomic, copy) NSArray<NSString *> *questions;     // 澄清问
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *answers; // 问答
@property (nonatomic, copy, nullable) NSString *generatedManifestJSON; // 生成的清单
@property (nonatomic, assign) LACreatorStage stage;
- (instancetype)initWithDescription:(NSString *)desc;
@end

@interface LACreator : NSObject
- (instancetype)initWithSessionID:(NSString *)sessionID;
@property (nonatomic, copy, readonly) NSString *sessionID;
@property (nonatomic, strong, nullable) LATrajectoryStore *trajectory;

// CreatorLoop 巡检：返回可生成线索文案（插件缺口提示）。
- (NSArray<NSString *> *)inspectHints;

// 闭环四步：开始描述 → 回答澄清 → 生成清单 → 签核安装。
- (LACreatorDraft *)startDraftWithDescription:(NSString *)desc;
- (NSArray<NSString *> *)clarifyQuestionsForDraft:(LACreatorDraft *)draft;
- (void)answerDraft:(LACreatorDraft *)draft answers:(NSDictionary<NSString *, NSString *> *)answers;
- (nullable NSString *)generateManifestForDraft:(LACreatorDraft *)draft error:(NSError **)error;
// 签核：经 asker（权限 ask）确认后才可安装；iOS 端先签核再安装为硬门。
- (void)requestSignoffForDraft:(LACreatorDraft *)draft
                         asker:(id)asker
                    completion:(void (^)(BOOL approved, NSError * _Nullable error))completion;
- (BOOL)installDraft:(LACreatorDraft *)draft error:(NSError **)error;
// 暂存/上架列表（出现在插件列表的数据源）。
- (NSArray<LACreatorDraft *> *)stagedDrafts;
- (void)removeDraft:(LACreatorDraft *)draft;

// Jira 只读示例 preset：一键启用（manifest JSON，可直接喂注册表）。
+ (NSString *)jiraReadonlyPresetManifest;
+ (NSString *)jiraReadonlyPresetID;
@end

FOUNDATION_EXPORT NSString *const LACreatorErrorDomain;
typedef NS_ENUM(NSInteger, LACreatorErrorCode) {
    LACreatorErrorNeedClarify  = 7501, // 澄清未答完，不可生成
    LACreatorErrorNeedSignoff  = 7502, // 未签核，不可安装
    LACreatorErrorBadManifest  = 7503, // 生成清单非法
};

NS_ASSUME_NONNULL_END

#endif /* LA_CREATOR_H */
