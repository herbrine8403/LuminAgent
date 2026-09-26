#ifndef LA_ZEN_CATALOG_H
#define LA_ZEN_CATALOG_H

#import <Foundation/Foundation.h>

// Zen 端点与免费模型目录：内置端点、免费名单、“限时免费”标注。
// 跨组契约：模型选择器与用量统计经此类获取免费标记与默认模型。
@interface LAZenCatalog : NSObject

// Zen 默认基地址：https://opencode.ai/zen/v1（结尾无斜杠）。
+ (NSString *)zenBaseURL;

// 默认别名：@"zen-default"，解析时映射到当前首选免费模型，不锁死具体 ID。
+ (NSString *)zenDefaultAlias;

// 当前默认模型 ID（首选免费模型；名单为空时回退 big-pickle）。
+ (NSString *)defaultModelID;

// 免费名单 ID 数组（共 14 个，顺序即推荐顺序）。
+ (NSArray<NSString *> *)freeModelIDs;

// 免费名单详情数组，每项含 modelID/displayName/isFree/freeBadge/priceNote。
+ (NSArray<NSDictionary *> *)freeModelInfos;

// 是否为免费模型（含 zen-default 别名，视为免费）。
+ (BOOL)isFreeModelID:(nullable NSString *)modelID;

// “限时免费”标注文案（随官方政策变动，仅改此处）。
+ (NSString *)limitedFreeBadgeText;

// 由 /models 响应刷新免费标记：输入 /models 原始数组，返回过滤后的免费子集。
// 不覆盖用户默认选择：仅返回展示用数据，调用方自行决定是否更新 UI。
// 元素为 LAZenCatalog 详情字典；解析失败经 error 回传。
+ (nullable NSArray<NSDictionary *> *)refreshedFreeModelsFromModelsResponse:(id)json
                                                                      error:(NSError **)error;

// 由 /models 响应提取全部模型 ID（含付费），用于选择器展示。
+ (nullable NSArray<NSString *> *)allModelIDsFromModelsResponse:(id)json
                                                          error:(NSError **)error;

@end

// 错误域与错误码。
FOUNDATION_EXPORT NSString *const LAZenCatalogErrorDomain;
typedef NS_ENUM(NSInteger, LAZenCatalogErrorCode) {
    LAZenCatalogErrorBadPayload = 2001, // /models 响应格式非法
};

#endif /* LA_ZEN_CATALOG_H */
