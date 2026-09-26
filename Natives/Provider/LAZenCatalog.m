#import "LAZenCatalog.h"

// Zen 目录实现：端点常量 + 14 免费模型 + /models 刷新解析。

NSString *const LAZenCatalogErrorDomain = @"ai.luminagent.zen";

// 默认基地址（HTTPS，满足 ATS）。
static NSString *const kLAZenBaseURL = @"https://opencode.ai/zen/v1";
// 默认别名（不锁死具体 ID，随免费名单变动自动跟随）。
static NSString *const kLAZenDefaultAlias = @"zen-default";
// 兜底默认 ID。
static NSString *const kLAZenFallbackModel = @"big-pickle";

@implementation LAZenCatalog

// 返回 Zen 基地址。
+ (NSString *)zenBaseURL { return kLAZenBaseURL; }

// 返回默认别名。
+ (NSString *)zenDefaultAlias { return kLAZenDefaultAlias; }

// 当前默认模型：免费名单首位。
+ (NSString *)defaultModelID {
    NSArray<NSString *> *free = [self freeModelIDs];
    if (free.count > 0) { return free.firstObject; }
    return kLAZenFallbackModel;
}

// 免费名单（spec 锁定 14 个，顺序即推荐顺序）。
+ (NSArray<NSString *> *)freeModelIDs {
    return @[
        @"big-pickle",
        @"mimo-v2.5-free",
        @"ling-3.0-flash-fin-free",
        @"nemotron-3-ultra-free",
        @"nemotron-3.5-lightning-free",
        @"muse-spark-1.3-contributor-free",
        @"deepseek-v4-flash-free",
        @"kimi-k2.5-free",
        @"minimax-m2.5-free",
        @"glm-4.7-free",
        @"qwen3.6-plus-free",
        @"longcat-2.0-free",
        @"north-mini-code-free",
        @"laguna-s-2.1-free",
    ];
}

// 限时免费标注。
+ (NSString *)limitedFreeBadgeText { return @"限时免费"; }

// 免费名单详情（展示用：显示名 + 免费标记 + 价格说明）。
+ (NSArray<NSDictionary *> *)freeModelInfos {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSString *mid in [self freeModelIDs]) {
        [out addObject:@{
            @"modelID" : mid,
            @"displayName" : mid,
            @"isFree" : @YES,
            @"freeBadge" : [self limitedFreeBadgeText],
            @"priceNote" : @"免费（限时以官方为准）",
            @"contextWindow" : @"见 /models 刷新",
        }];
    }
    return [out copy];
}

// 是否免费（含别名）。
+ (BOOL)isFreeModelID:(nullable NSString *)modelID {
    if (modelID.length == 0) { return NO; }
    if ([modelID isEqualToString:kLAZenDefaultAlias]) { return YES; }
    // 支持 provider/model 与裸 model 两种写法。
    NSString *bare = modelID;
    NSRange slash = [modelID rangeOfString:@"/"];
    if (slash.location != NSNotFound) {
        bare = [modelID substringFromIndex:slash.location + 1];
    }
    if ([bare isEqualToString:kLAZenDefaultAlias]) { return YES; }
    return [[self freeModelIDs] containsObject:bare];
}

// 从 /models 响应中提取 data 数组（兼容 {data:[...]} 与裸数组两种形状）。
+ (nullable NSArray *)dataArrayFromResponse:(id)json error:(NSError **)error {
    NSArray *arr = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        arr = json;
    } else if ([json isKindOfClass:[NSDictionary class]]) {
        id d = json[@"data"];
        if ([d isKindOfClass:[NSArray class]]) { arr = d; }
    }
    if (arr == nil && error) {
        *error = [NSError errorWithDomain:LAZenCatalogErrorDomain
                                     code:LAZenCatalogErrorBadPayload
                                 userInfo:@{NSLocalizedDescriptionKey : @"/models 响应格式非法：缺少 data 数组"}];
    }
    return arr;
}

// 取模型条目的 ID（兼容 id / name / model 三种字段）。
+ (nullable NSString *)modelIDFromEntry:(id)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) { return nil; }
    for (NSString *k in @[@"id", @"name", @"model"]) {
        id v = entry[k];
        if ([v isKindOfClass:[NSString class]] && ((NSString *)v).length > 0) { return v; }
    }
    return nil;
}

// 刷新免费标记：取 /models 全量与内置名单取交集，保留官方附加字段。
+ (nullable NSArray<NSDictionary *> *)refreshedFreeModelsFromModelsResponse:(id)json
                                                                      error:(NSError **)error {
    NSArray *arr = [self dataArrayFromResponse:json error:error];
    if (arr == nil) { return nil; }
    NSSet<NSString *> *freeSet = [NSSet setWithArray:[self freeModelIDs]];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (id entry in arr) {
        NSString *mid = [self modelIDFromEntry:entry];
        if (mid.length == 0) { continue; }
        if (![freeSet containsObject:mid]) { continue; }
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"modelID"] = mid;
        info[@"displayName"] = mid;
        info[@"isFree"] = @YES;
        info[@"freeBadge"] = [self limitedFreeBadgeText];
        info[@"priceNote"] = @"免费（限时以官方为准）";
        // 透传官方上下文窗/价格展示字段（存在才带）。
        if ([entry isKindOfClass:[NSDictionary class]]) {
            for (NSString *k in @[@"context_window", @"contextWindow", @"pricing", @"owned_by"]) {
                id v = entry[k];
                if (v) { info[k] = v; }
            }
        }
        [out addObject:[info copy]];
    }
    return [out copy];
}

// 提取全量模型 ID（选择器展示用，不做免费过滤）。
+ (nullable NSArray<NSString *> *)allModelIDsFromModelsResponse:(id)json
                                                          error:(NSError **)error {
    NSArray *arr = [self dataArrayFromResponse:json error:error];
    if (arr == nil) { return nil; }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id entry in arr) {
        NSString *mid = [self modelIDFromEntry:entry];
        if (mid.length > 0) { [out addObject:mid]; }
    }
    return [out copy];
}

@end
