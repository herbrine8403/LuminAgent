#import "LAModelPolicy.h"

// 治理实现：deny 优先 + 四层优先级解析。

NSString *const LAModelPolicyErrorDomain = @"ai.luminagent.policy";

@implementation LAModelPolicy

// 初始化（内置默认兜底 zen-default）。
- (instancetype)init {
    return [self initWithBuiltinDefault:@"zen-default"];
}

// 指定内置默认初始化。
- (instancetype)initWithBuiltinDefault:(NSString *)builtinDefault {
    if (self = [super init]) {
        _builtinDefaultModel = [builtinDefault copy] ?: @"zen-default";
        _blacklist = @[];
        _whitelist = @[];
        _enabledProviders = @[];
        _disabledProviders = @[];
        _enterpriseAllowedProviders = @[];
    }
    return self;
}

// 切出 provider 部分（无斜杠视为 zen）。
- (NSString *)providerOf:(NSString *)identifier {
    NSRange r = [identifier rangeOfString:@"/"];
    if (r.location == NSNotFound) { return @"zen"; }
    return [identifier substringToIndex:r.location];
}

// 切出裸 model 部分。
- (NSString *)bareModelOf:(NSString *)identifier {
    NSRange r = [identifier rangeOfString:@"/"];
    if (r.location == NSNotFound) { return identifier; }
    return [identifier substringFromIndex:r.location + 1];
}

// 名单匹配：完整标识或裸 model 任一命中即算命中（大小写敏感）。
- (BOOL)identifier:(NSString *)identifier matchesList:(NSArray<NSString *> *)list {
    if (list.count == 0) { return NO; }
    NSString *bare = [self bareModelOf:identifier];
    for (NSString *entry in list) {
        if ([entry isEqualToString:identifier] || [entry isEqualToString:bare]) { return YES; }
    }
    return NO;
}

// Provider 是否允许（deny 优先）。
- (BOOL)isProviderAllowed:(NSString *)providerID {
    if (providerID.length == 0) { return NO; }
    // 1) disabled 命中即拒绝（最高优先）。
    if ([self.disabledProviders containsObject:providerID]) { return NO; }
    // 2) 企业限制非空时，未命中即拒绝。
    if (self.enterpriseAllowedProviders.count > 0 &&
        ![self.enterpriseAllowedProviders containsObject:providerID]) { return NO; }
    // 3) enabled 非空时，未命中即拒绝。
    if (self.enabledProviders.count > 0 &&
        ![self.enabledProviders containsObject:providerID]) { return NO; }
    return YES;
}

// 模型是否可见。
- (BOOL)isModelVisible:(NSString *)fullIdentifier {
    if (fullIdentifier.length == 0) { return NO; }
    // 先判 provider。
    if (![self isProviderAllowed:[self providerOf:fullIdentifier]]) { return NO; }
    // 再判 blacklist（命中即隐藏）。
    if ([self identifier:fullIdentifier matchesList:self.blacklist]) { return NO; }
    // 最后判 whitelist（非空时未命中即隐藏）。
    if (self.whitelist.count > 0 && ![self identifier:fullIdentifier matchesList:self.whitelist]) { return NO; }
    return YES;
}

// 四层优先级解析。
- (nullable NSString *)resolveModelWithOverride:(nullable NSString *)override
                                          error:(NSError **)error {
    NSArray<NSString *> *candidates = @[
        override ?: @"",
        self.projectDefaultModel ?: @"",
        self.lastUsedModel ?: @"",
        self.builtinDefaultModel ?: @"",
    ];
    for (NSString *c in candidates) {
        if (c.length == 0) { continue; }
        if ([self isModelVisible:c]) { return c; }
        // 有候选但被策略拒绝：若它是最高优先的单次指定，直接报错（提示更换）。
        if ([c isEqualToString:override ?: @""] && override.length > 0) {
            if (error) {
                *error = [NSError errorWithDomain:LAModelPolicyErrorDomain
                                             code:LAModelPolicyErrorNotAllowed
                                         userInfo:@{NSLocalizedDescriptionKey : @"该模型被策略限制，请更换模型",
                                                    @"modelID" : c}];
            }
            return nil;
        }
        // 非单次层被拒绝则继续降级。
    }
    if (error) {
        *error = [NSError errorWithDomain:LAModelPolicyErrorDomain
                                     code:LAModelPolicyErrorNoCandidate
                                 userInfo:@{NSLocalizedDescriptionKey : @"无可用模型（均被策略过滤）"}];
    }
    return nil;
}

// 批量过滤。
- (NSArray<NSString *> *)filteredModelIDsFrom:(NSArray<NSString *> *)allIDs {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *mid in allIDs) {
        if ([mid isKindOfClass:[NSString class]] && [self isModelVisible:mid]) {
            [out addObject:mid];
        }
    }
    return [out copy];
}

// 记录使用。
- (void)recordUsedModel:(NSString *)identifier {
    if (identifier.length > 0) { self.lastUsedModel = [identifier copy]; }
}

// 导出策略快照（无凭证）。
- (NSDictionary *)exportDictionary {
    return @{
        @"blacklist" : [self.blacklist copy],
        @"whitelist" : [self.whitelist copy],
        @"enabledProviders" : [self.enabledProviders copy],
        @"disabledProviders" : [self.disabledProviders copy],
        @"enterpriseAllowedProviders" : [self.enterpriseAllowedProviders copy],
        @"projectDefaultModel" : self.projectDefaultModel ?: [NSNull null],
        @"builtinDefaultModel" : self.builtinDefaultModel ?: @"zen-default",
    };
}

@end
