#ifndef LA_MODEL_PICKER_H
#define LA_MODEL_PICKER_H

#import <Foundation/Foundation.h>

// 模型选择器：/models 数据源、small_model 轻任务路由、reasoning effort variants。
// 跨组契约：Chat 界面经此类获取展示列表、当前选择、轻任务模型与变体参数。
NS_ASSUME_NONNULL_BEGIN

// 推理强度变体（reasoning effort）。
typedef NS_ENUM(NSInteger, LAModelEffort) {
    LAModelEffortLow    = 0, // 低：标题/摘要等轻任务
    LAModelEffortMedium = 1, // 中：默认
    LAModelEffortHigh   = 2, // 高：复杂推理/代码
};

// 选择器条目。
@interface LAModelItem : NSObject <NSCopying>
@property (nonatomic, copy) NSString *fullID;        // provider/model 全标识
@property (nonatomic, copy) NSString *displayName;   // 展示名
@property (nonatomic, assign) BOOL isFree;           // 是否免费（含限时免费）
@property (nonatomic, copy, nullable) NSString *freeBadge; // 免费标注（@"限时免费"）
@property (nonatomic, copy, nullable) NSString *contextInfo; // 上下文窗/价格展示
- (instancetype)initWithFullID:(NSString *)fullID displayName:(nullable NSString *)name;
@end

@interface LAModelPicker : NSObject

// 当前选中（完整 provider/model；初始为 zen-default）。
@property (nonatomic, copy) NSString *selectedModelID;
// 轻任务模型（small_model；为空时轻任务复用当前选中）。
@property (nonatomic, copy, nullable) NSString *smallModelID;
// 当前变体（默认 Medium；Ctrl+T 式循环切换）。
@property (nonatomic, assign) LAModelEffort currentEffort;

- (instancetype)initWithDefaultModel:(nullable NSString *)defaultModel;

// 由 /models 原始数组刷新数据源（providerID 用于拼接 fullID）。
// models 为 LAProviderGateway.fetchModels 回传的字典数组；失败经 error 回传。
- (BOOL)reloadWithModelsResponse:(NSArray<NSDictionary *> *)models
                      providerID:(NSString *)providerID
                           error:(NSError **)error;

// 展示用全量条目（已按免费优先排序）。
- (NSArray<LAModelItem *> *)allItems;

// 选中指定模型（不存在返回 NO，经 error 回传）。
- (BOOL)selectModelWithID:(NSString *)fullID error:(NSError **)error;

// 轻任务路由：有 small_model 用小模型，否则用当前选中（不占用主模型上下文由调用方保证）。
- (NSString *)modelIDForLightTask;

// 变体切换（Ctrl+T 式循环：Low → Medium → High → Low），返回切换后值。
- (LAModelEffort)cycleToNextVariant;

// 变体字符串（low/medium/high），用于请求体 reasoning.effort 透传。
- (NSString *)effortStringForEffort:(LAModelEffort)effort;
+ (NSString *)effortStringForEffort:(LAModelEffort)effort;

// 当前变体字符串（快捷入口）。
- (NSString *)currentEffortString;

@end

FOUNDATION_EXPORT NSString *const LAModelPickerErrorDomain;
typedef NS_ENUM(NSInteger, LAModelPickerErrorCode) {
    LAModelPickerErrorUnknownModel = 5001, // 选择了数据源中不存在的模型
    LAModelPickerErrorBadPayload   = 5002, // /models 数据非法
};

NS_ASSUME_NONNULL_END

#endif /* LA_MODEL_PICKER_H */
