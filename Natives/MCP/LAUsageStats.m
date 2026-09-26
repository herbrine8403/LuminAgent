// LAUsageStats.m
// 中文注释：用量统计的占位实现（内存聚合 + 免费归零 + 预算阈值判断，无网络）。

#import "LAUsageStats.h"

NSString *const LAUsageStatsErrorDomain = @"org.luminagent.usage";

#pragma mark - LAUsageRecord

@implementation LAUsageRecord

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _sessionId = [coder decodeObjectOfClass:[NSString class] forKey:@"sessionId"];
        _projectId = [coder decodeObjectOfClass:[NSString class] forKey:@"projectId"];
        _model = [coder decodeObjectOfClass:[NSString class] forKey:@"model"];
        _tool = [coder decodeObjectOfClass:[NSString class] forKey:@"tool"];
        _inputTokens = [coder decodeInt64ForKey:@"inputTokens"];
        _outputTokens = [coder decodeInt64ForKey:@"outputTokens"];
        _cacheTokens = [coder decodeInt64ForKey:@"cacheTokens"];
        _cost = [coder decodeDoubleForKey:@"cost"];
        _latencySeconds = [coder decodeDoubleForKey:@"latencySeconds"];
        _createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.sessionId forKey:@"sessionId"];
    [coder encodeObject:self.projectId forKey:@"projectId"];
    [coder encodeObject:self.model forKey:@"model"];
    [coder encodeObject:self.tool forKey:@"tool"];
    [coder encodeInt64:self.inputTokens forKey:@"inputTokens"];
    [coder encodeInt64:self.outputTokens forKey:@"outputTokens"];
    [coder encodeInt64:self.cacheTokens forKey:@"cacheTokens"];
    [coder encodeDouble:self.cost forKey:@"cost"];
    [coder encodeDouble:self.latencySeconds forKey:@"latencySeconds"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
}

- (id)copyWithZone:(NSZone *)zone {
    LAUsageRecord *c = [[LAUsageRecord allocWithZone:zone] init];
    c.sessionId = self.sessionId;
    c.projectId = self.projectId;
    c.model = self.model;
    c.tool = self.tool;
    c.inputTokens = self.inputTokens;
    c.outputTokens = self.outputTokens;
    c.cacheTokens = self.cacheTokens;
    c.cost = self.cost;
    c.latencySeconds = self.latencySeconds;
    c.createdAt = self.createdAt;
    return c;
}

@end

#pragma mark - LAUsageMatrixRow

@implementation LAUsageMatrixRow
@end

#pragma mark - LAUsageStats

@interface LAUsageStats ()
@property (nonatomic, strong) NSMutableArray<LAUsageRecord *> *records;
@property (nonatomic, strong) dispatch_queue_t syncQueue;
@end

@implementation LAUsageStats

+ (instancetype)sharedStats {
    static LAUsageStats *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[LAUsageStats alloc] initPrivate]; });
    return s;
}

- (instancetype)initPrivate {
    if (self = [super init]) {
        _records = [NSMutableArray array];
        _syncQueue = dispatch_queue_create("org.luminagent.usage.sync", DISPATCH_QUEUE_SERIAL);
        _budgetLimit = 0;     // <=0 不限
        _warningRatio = 0.8;  // 80% 预警
    }
    return self;
}

- (instancetype)init { return [[self class] sharedStats]; }

#pragma mark 免费名单

+ (NSSet<NSString *> *)freeModelNames {
    // 与任务 3.3 Zen 免费名单对齐（含“限时免费”标注的模型，上层展示时自行加标注）
    return [NSSet setWithArray:@[
        @"big-pickle", @"mimo", @"ling", @"nemotron", @"muse-spark",
        @"deepseek-v4", @"kimi", @"minimax", @"glm", @"qwen",
        @"longcat", @"north", @"laguna",
    ]];
}

+ (BOOL)isFreeModel:(NSString *)model {
    if (model.length == 0) { return NO; }
    NSString *lower = model.lowercaseString;
    for (NSString *free in [self freeModelNames]) {
        // 兼容带前后缀的模型变体（如 zen-big-pickle / big-pickle-reasoning）
        if ([lower containsString:free.lowercaseString]) { return YES; }
    }
    return NO;
}

#pragma mark 记录

- (BOOL)recordUsageForSession:(NSString *)sessionId
                      project:(NSString *)projectId
                        model:(NSString *)model
                         tool:(NSString *)tool
                  inputTokens:(long long)inputTokens
                 outputTokens:(long long)outputTokens
                  cacheTokens:(long long)cacheTokens
                         cost:(double)cost
              latencySeconds:(double)latencySeconds
                       error:(NSError **)error {
    if (sessionId.length == 0 || model.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:LAUsageStatsErrorDomain code:LAUsageStatsErrorCodeInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"sessionId/model 不能为空"}];
        }
        return NO;
    }
    if (inputTokens < 0 || outputTokens < 0 || cacheTokens < 0 || cost < 0 || latencySeconds < 0) {
        if (error) {
            *error = [NSError errorWithDomain:LAUsageStatsErrorDomain code:LAUsageStatsErrorCodeInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"tokens/费用/耗时不能为负"}];
        }
        return NO;
    }
    LAUsageRecord *r = [[LAUsageRecord alloc] init];
    r.sessionId = sessionId;
    r.projectId = projectId.length > 0 ? projectId : @"default";
    r.model = model;
    r.tool = tool.length > 0 ? tool : @"(chat)";
    r.inputTokens = inputTokens;
    r.outputTokens = outputTokens;
    r.cacheTokens = cacheTokens;
    // 免费档强制记 0（即使调用方误传 cost 也归零，保证对账正确）
    r.cost = [[self class] isFreeModel:model] ? 0.0 : cost;
    r.latencySeconds = latencySeconds;
    r.createdAt = [NSDate date];
    dispatch_sync(self.syncQueue, ^{ [self.records addObject:r]; });
    // 每次记录后顺手检查预算（超限提示由回调发出，不阻塞记录）
    [self checkBudgetWithCurrentCost:NULL];
    return YES;
}

#pragma mark 聚合

- (NSDictionary *)aggregate:(NSArray<LAUsageRecord *> *)list {
    long long input = 0, output = 0, cache = 0;
    double cost = 0, latency = 0;
    for (LAUsageRecord *r in list) {
        input += r.inputTokens; output += r.outputTokens; cache += r.cacheTokens;
        cost += r.cost; latency += r.latencySeconds;
    }
    return @{
        @"calls": @(list.count),
        @"inputTokens": @(input),
        @"outputTokens": @(output),
        @"cacheTokens": @(cache),
        @"totalTokens": @(input + output + cache),
        @"cost": @(cost),
        @"latencySeconds": @(latency),
    };
}

- (NSArray<LAUsageRecord *> *)allRecords {
    __block NSArray *c = nil;
    dispatch_sync(self.syncQueue, ^{ c = [self.records copy]; });
    return c;
}

- (NSDictionary *)statsForSession:(NSString *)sessionId {
    NSMutableArray *out = [NSMutableArray array];
    for (LAUsageRecord *r in [self allRecords]) {
        if ([r.sessionId isEqualToString:sessionId]) { [out addObject:r]; }
    }
    return [self aggregate:out];
}

- (NSDictionary *)globalStats {
    return [self aggregate:[self allRecords]];
}

#pragma mark 矩阵

- (NSArray<LAUsageMatrixRow *> *)matrixForRecords:(NSArray<LAUsageRecord *> *)list
                                          keyOf:(NSString * (^)(LAUsageRecord *))keyOf {
    NSMutableDictionary<NSString *, LAUsageMatrixRow *> *map = [NSMutableDictionary dictionary];
    for (LAUsageRecord *r in list) {
        NSString *k = keyOf(r) ?: @"(unknown)";
        LAUsageMatrixRow *row = map[k];
        if (!row) { row = [[LAUsageMatrixRow alloc] init]; row.key = k; map[k] = row; }
        row.inputTokens += r.inputTokens;
        row.outputTokens += r.outputTokens;
        row.cacheTokens += r.cacheTokens;
        row.cost += r.cost;
        row.latencySeconds += r.latencySeconds;
        row.calls += 1;
    }
    // 按 cost 降序（烧 token/烧钱的调用方排前，便于定位）
    return [map.allValues sortedArrayUsingComparator:^NSComparisonResult(LAUsageMatrixRow *a, LAUsageMatrixRow *b) {
        if (a.cost > b.cost) { return NSOrderedAscending; }
        if (a.cost < b.cost) { return NSOrderedDescending; }
        long long ta = a.inputTokens + a.outputTokens, tb = b.inputTokens + b.outputTokens;
        if (ta > tb) { return NSOrderedAscending; }
        if (ta < tb) { return NSOrderedDescending; }
        return NSOrderedSame;
    }];
}

- (NSArray<LAUsageMatrixRow *> *)matrixByModel {
    return [self matrixForRecords:[self allRecords] keyOf:^NSString *(LAUsageRecord *r) { return r.model; }];
}

- (NSArray<LAUsageMatrixRow *> *)matrixByTool {
    return [self matrixForRecords:[self allRecords] keyOf:^NSString *(LAUsageRecord *r) { return r.tool; }];
}

- (NSArray<LAUsageMatrixRow *> *)matrixByProject {
    return [self matrixForRecords:[self allRecords] keyOf:^NSString *(LAUsageRecord *r) { return r.projectId; }];
}

- (NSArray<LAUsageMatrixRow *> *)matrixByModelForSession:(NSString *)sessionId sinceLastWeek:(BOOL)lastWeekOnly {
    NSMutableArray *list = [NSMutableArray array];
    NSDate *weekAgo = lastWeekOnly ? [NSDate dateWithTimeIntervalSinceNow:-7 * 24 * 3600] : nil;
    for (LAUsageRecord *r in [self allRecords]) {
        if (sessionId.length > 0 && ![r.sessionId isEqualToString:sessionId]) { continue; }
        if (weekAgo && [r.createdAt compare:weekAgo] == NSOrderedAscending) { continue; }
        [list addObject:r];
    }
    return [self matrixForRecords:list keyOf:^NSString *(LAUsageRecord *r) { return r.model; }];
}

#pragma mark /stats 文案

- (NSString *)rowLine:(LAUsageMatrixRow *)row {
    return [NSString stringWithFormat:@"  %@  calls=%lu in=%lld out=%lld cache=%lld cost=%.4f latency=%.1fs",
            row.key, (unsigned long)row.calls,
            row.inputTokens, row.outputTokens, row.cacheTokens, row.cost, row.latencySeconds];
}

- (NSString *)formattedStatsStringForSession:(NSString *)sessionId {
    NSDictionary *sess = sessionId.length > 0 ? [self statsForSession:sessionId] : @{};
    NSDictionary *glob = [self globalStats];
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"用量统计 /stats\n"];
    if (sessionId.length > 0) {
        [s appendFormat:@"本会话(%@)：calls=%@ tokens=%@（in %@ / out %@ / cache %@）费用 %@\n",
         sessionId, sess[@"calls"], sess[@"totalTokens"], sess[@"inputTokens"],
         sess[@"outputTokens"], sess[@"cacheTokens"], sess[@"cost"]];
    }
    [s appendFormat:@"累计：calls=%@ tokens=%@（in %@ / out %@ / cache %@）费用 %@\n",
     glob[@"calls"], glob[@"totalTokens"], glob[@"inputTokens"],
     glob[@"outputTokens"], glob[@"cacheTokens"], glob[@"cost"]];
    [s appendString:@"— 分模型 —\n"];
    for (LAUsageMatrixRow *r in [self matrixByModel]) { [s appendFormat:@"%@\n", [self rowLine:r]]; }
    [s appendString:@"— 分工具 —\n"];
    for (LAUsageMatrixRow *r in [self matrixByTool]) { [s appendFormat:@"%@\n", [self rowLine:r]]; }
    [s appendString:@"— 分项目 —\n"];
    for (LAUsageMatrixRow *r in [self matrixByProject]) { [s appendFormat:@"%@\n", [self rowLine:r]]; }
    // 预算提示行
    if (self.budgetLimit > 0) {
        double cur = [glob[@"cost"] doubleValue];
        [s appendFormat:@"预算：%.4f / %.4f（%.0f%%）%@\n", cur, self.budgetLimit,
         (self.budgetLimit > 0 ? cur / self.budgetLimit * 100 : 0),
         cur >= self.budgetLimit ? @"【已超预算，建议暂停高耗调用】" :
         (cur >= self.budgetLimit * self.warningRatio ? @"【接近预算，请注意开销】" : @"")];
    } else {
        [s appendString:@"预算：未设置\n"];
    }
    [s appendString:@"（免费模型费用记 0；矩阵按费用降序）"];
    return [s copy];
}

#pragma mark 预算

- (BOOL)checkBudgetWithCurrentCost:(double *)outCost {
    double cur = [[[self globalStats] objectForKey:@"cost"] doubleValue];
    if (outCost) { *outCost = cur; }
    if (self.budgetLimit <= 0) { return NO; } // 未设置不限
    if (cur >= self.budgetLimit) {
        LAUsageBudgetHandler h = self.onBudgetExceeded;
        if (h) { h(@"global", cur, self.budgetLimit); }
        return YES;
    }
    if (cur >= self.budgetLimit * self.warningRatio) {
        LAUsageBudgetHandler h = self.onBudgetWarning;
        if (h) { h(@"global", cur, self.budgetLimit); }
    }
    return NO;
}

- (void)resetAll {
    dispatch_sync(self.syncQueue, ^{ [self.records removeAllObjects]; });
}

@end
