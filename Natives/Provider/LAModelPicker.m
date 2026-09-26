#import "LAModelPicker.h"
#import "LAZenCatalog.h"

// 选择器实现：数据源刷新 + small_model 路由 + variants 循环。

NSString *const LAModelPickerErrorDomain = @"ai.luminagent.picker";

#pragma mark - LAModelItem

@implementation LAModelItem

// 构造条目。
- (instancetype)initWithFullID:(NSString *)fullID displayName:(nullable NSString *)name {
    if (self = [super init]) {
        _fullID = [fullID copy] ?: @"";
        _displayName = [name copy] ?: [_fullID copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    LAModelItem *c = [[[self class] alloc] initWithFullID:self.fullID displayName:self.displayName];
    c.isFree = self.isFree;
    c.freeBadge = [self.freeBadge copy];
    c.contextInfo = [self.contextInfo copy];
    return c;
}
@end

#pragma mark - LAModelPicker

@interface LAModelPicker ()
@property (nonatomic, strong) NSMutableArray<LAModelItem *> *items;
@end

@implementation LAModelPicker

// 初始化（默认选中 zen-default，变体默认 Medium）。
- (instancetype)init {
    return [self initWithDefaultModel:@"zen-default"];
}

// 指定默认模型初始化。
- (instancetype)initWithDefaultModel:(nullable NSString *)defaultModel {
    if (self = [super init]) {
        _selectedModelID = [defaultModel copy] ?: @"zen-default";
        _currentEffort = LAModelEffortMedium;
        _items = [NSMutableArray array];
    }
    return self;
}

// 由 /models 刷新数据源。
- (BOOL)reloadWithModelsResponse:(NSArray<NSDictionary *> *)models
                      providerID:(NSString *)providerID
                           error:(NSError **)error {
    if (![models isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:LAModelPickerErrorDomain
                                         code:LAModelPickerErrorBadPayload
                                     userInfo:@{NSLocalizedDescriptionKey : @"/models 数据非法"}];
        }
        return NO;
    }
    NSString *pid = providerID.length > 0 ? providerID : @"zen";
    NSMutableArray<LAModelItem *> *built = [NSMutableArray arrayWithCapacity:models.count];
    for (id entry in models) {
        if (![entry isKindOfClass:[NSDictionary class]]) { continue; }
        NSString *mid = entry[@"id"];
        if (![mid isKindOfClass:[NSString class]] || mid.length == 0) {
            mid = entry[@"name"];
        }
        if (![mid isKindOfClass:[NSString class]] || mid.length == 0) { continue; }
        // fullID 拼接：若已含斜杠视为完整标识，否则拼 provider 前缀。
        NSString *full = ([mid rangeOfString:@"/"].location == NSNotFound)
            ? [NSString stringWithFormat:@"%@/%@", pid, mid] : mid;
        NSString *name = [entry[@"display_name"] isKindOfClass:[NSString class]] ? entry[@"display_name"] : mid;
        LAModelItem *item = [[LAModelItem alloc] initWithFullID:full displayName:name];
        // 免费标记：命中 Zen 名单即免费（含限时标注）。
        if ([LAZenCatalog isFreeModelID:mid] || [LAZenCatalog isFreeModelID:full]) {
            item.isFree = YES;
            item.freeBadge = [LAZenCatalog limitedFreeBadgeText];
        }
        // 上下文窗/价格展示透传。
        id ctx = entry[@"context_window"] ?: entry[@"contextWindow"];
        id price = entry[@"pricing"];
        if (ctx || price) {
            NSMutableArray *parts = [NSMutableArray array];
            if (ctx) { [parts addObject:[NSString stringWithFormat:@"上下文:%@", ctx]]; }
            if (price) { [parts addObject:[NSString stringWithFormat:@"价格:%@", price]]; }
            item.contextInfo = [parts componentsJoinedByString:@" "];
        }
        [built addObject:item];
    }
    // 免费优先排序（稳定：免费在前，其余保持原顺序）。
    NSArray<LAModelItem *> *free = [built filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isFree == YES"]];
    NSArray<LAModelItem *> *rest = [built filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isFree == NO"]];
    [self.items removeAllObjects];
    [self.items addObjectsFromArray:free];
    [self.items addObjectsFromArray:rest];
    // 不覆盖用户默认选择：仅当当前选中不在新数据源时才保持原值（不强制切换）。
    return YES;
}

// 全量条目（返回拷贝防篡改）。
- (NSArray<LAModelItem *> *)allItems {
    return [self.items copy];
}

// 选中模型。
- (BOOL)selectModelWithID:(NSString *)fullID error:(NSError **)error {
    if (fullID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:LAModelPickerErrorDomain
                                         code:LAModelPickerErrorUnknownModel
                                     userInfo:@{NSLocalizedDescriptionKey : @"模型 ID 为空"}];
        }
        return NO;
    }
    // 数据源为空时允许直接选中（零配置首启：Zen 默认可用，无需先拉 /models）。
    if (self.items.count == 0) {
        self.selectedModelID = [fullID copy];
        return YES;
    }
    for (LAModelItem *item in self.items) {
        if ([item.fullID isEqualToString:fullID]) {
            self.selectedModelID = [fullID copy];
            return YES;
        }
    }
    if (error) {
        *error = [NSError errorWithDomain:LAModelPickerErrorDomain
                                     code:LAModelPickerErrorUnknownModel
                                 userInfo:@{NSLocalizedDescriptionKey : @"未知的模型 ID",
                                            @"modelID" : fullID}];
    }
    return NO;
}

// 轻任务路由。
- (NSString *)modelIDForLightTask {
    if (self.smallModelID.length > 0) { return self.smallModelID; }
    return self.selectedModelID;
}

// 变体循环切换。
- (LAModelEffort)cycleToNextVariant {
    if (self.currentEffort == LAModelEffortLow) { self.currentEffort = LAModelEffortMedium; }
    else if (self.currentEffort == LAModelEffortMedium) { self.currentEffort = LAModelEffortHigh; }
    else { self.currentEffort = LAModelEffortLow; }
    return self.currentEffort;
}

// 变体转字符串。
+ (NSString *)effortStringForEffort:(LAModelEffort)effort {
    switch (effort) {
        case LAModelEffortLow: return @"low";
        case LAModelEffortHigh: return @"high";
        case LAModelEffortMedium:
        default: return @"medium";
    }
}

// 实例版转发。
- (NSString *)effortStringForEffort:(LAModelEffort)effort {
    return [[self class] effortStringForEffort:effort];
}

// 当前变体字符串。
- (NSString *)currentEffortString {
    return [[self class] effortStringForEffort:self.currentEffort];
}

@end
