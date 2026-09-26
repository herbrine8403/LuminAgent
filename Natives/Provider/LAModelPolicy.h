#ifndef LA_MODEL_POLICY_H
#define LA_MODEL_POLICY_H

#import <Foundation/Foundation.h>

// 模型可见性与优先级治理：blacklist/whitelist、enabled/disabled_providers（deny 优先）、
// 企业 policies、解析优先级（单次 > 项目 > 上次 > 默认）。
// 跨组契约：模型选择器与网关调用前经此类过滤与解析。
NS_ASSUME_NONNULL_BEGIN

@interface LAModelPolicy : NSObject

// 裁剪：模型级黑/白名单（存完整 provider/model 或裸 model，二者皆匹配）。
@property (nonatomic, copy) NSArray<NSString *> *blacklist;
@property (nonatomic, copy) NSArray<NSString *> *whitelist; // 为空表示不限制

// 全局供应商 allowlist/denylist：disabled 优先于 enabled（deny 优先）。
@property (nonatomic, copy) NSArray<NSString *> *enabledProviders;  // 为空表示全部允许（除 disabled）
@property (nonatomic, copy) NSArray<NSString *> *disabledProviders; // 命中即拒绝

// 企业合规：仅允许的 Provider 集合；为空表示无企业限制。
@property (nonatomic, copy) NSArray<NSString *> *enterpriseAllowedProviders;

// 解析优先级各层级默认值。
@property (nonatomic, copy, nullable) NSString *projectDefaultModel; // 项目配置
@property (nonatomic, copy, nullable) NSString *lastUsedModel;       // 上次使用
@property (nonatomic, copy) NSString *builtinDefaultModel;           // 内置默认（默认 zen-default）

- (instancetype)initWithBuiltinDefault:(NSString *)builtinDefault;

// Provider 是否允许：依次检查 disabled（命中即 NO）→ enterprise（非空且未命中即 NO）→ enabled（非空且未命中即 NO）。
- (BOOL)isProviderAllowed:(NSString *)providerID;

// 模型是否可见：先判 provider 允许，再判 blacklist（命中即 NO），最后判 whitelist（非空且未命中即 NO）。
- (BOOL)isModelVisible:(NSString *)fullIdentifier;

// 模型解析：override（单次）> projectDefaultModel（项目）> lastUsedModel（上次）> builtinDefaultModel（默认）。
// 返回解析出的 identifier；若最终为空或不可见，经 error 回传。
- (nullable NSString *)resolveModelWithOverride:(nullable NSString *)override
                                          error:(NSError **)error;

// 批量过滤：输入全量 identifier 数组，返回可见子集（保持原顺序）。
- (NSArray<NSString *> *)filteredModelIDsFrom:(NSArray<NSString *> *)allIDs;

// 记录一次成功使用（更新 lastUsedModel，供下次解析）。
- (void)recordUsedModel:(NSString *)identifier;

// 导出分享前的策略快照（不含任何凭证，仅策略字段）。
- (NSDictionary *)exportDictionary;

@end

FOUNDATION_EXPORT NSString *const LAModelPolicyErrorDomain;
typedef NS_ENUM(NSInteger, LAModelPolicyErrorCode) {
    LAModelPolicyErrorNoCandidate  = 4001, // 四层均无可用模型
    LAModelPolicyErrorNotAllowed   = 4002, // 解析结果被策略拒绝（userInfo[@"modelID"]）
};

NS_ASSUME_NONNULL_END

#endif /* LA_MODEL_POLICY_H */
