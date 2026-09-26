#import "LATrajectoryStore.h"

NSString *const LATrajectoryErrorDomain = @"com.luminagent.harness.trajectory";

@implementation LATrajectoryEvent
- (instancetype)initWithSeq:(uint64_t)seq
                       type:(LATrajectoryEventType)type
                    payload:(NSDictionary *)payload
               sourcePlugin:(NSString *)sourcePlugin
                  sessionID:(NSString *)sessionID {
    if (self = [super init]) {
        _seq = seq;
        _type = type;
        _payload = [payload copy] ?: @{};
        _sourcePlugin = [sourcePlugin copy] ?: @"unknown";
        _timestamp = [NSDate date];
        _sessionID = [sessionID copy] ?: @"";
    }
    return self;
}
- (id)copyWithZone:(nullable NSZone *)zone {
    LATrajectoryEvent *c = [[[self class] allocWithZone:zone] initWithSeq:_seq type:_type payload:_payload sourcePlugin:_sourcePlugin sessionID:_sessionID];
    return c;
}
+ (NSString *)stringFromType:(LATrajectoryEventType)type {
    switch (type) {
        case LATrajectoryEventTurnStart: return @"turn_start";
        case LATrajectoryEventTurnEnd: return @"turn_end";
        case LATrajectoryEventStepStart: return @"step_start";
        case LATrajectoryEventStepEnd: return @"step_end";
        case LATrajectoryEventUserMessage: return @"user_message";
        case LATrajectoryEventAssistantMsg: return @"assistant_message";
        case LATrajectoryEventAttempt: return @"attempt";
        case LATrajectoryEventToolCall: return @"tool_call";
        case LATrajectoryEventToolResult: return @"tool_result";
        case LATrajectoryEventRequestCtx: return @"request_context";
        case LATrajectoryEventSessionSeed: return @"session_end_seed";
        case LATrajectoryEventPluginExt: return @"plugin_event";
    }
    return @"plugin_event";
}
+ (LATrajectoryEventType)typeFromString:(NSString *)string {
    NSDictionary *map = @{
        @"turn_start": @(LATrajectoryEventTurnStart),
        @"turn_end": @(LATrajectoryEventTurnEnd),
        @"step_start": @(LATrajectoryEventStepStart),
        @"step_end": @(LATrajectoryEventStepEnd),
        @"user_message": @(LATrajectoryEventUserMessage),
        @"assistant_message": @(LATrajectoryEventAssistantMsg),
        @"attempt": @(LATrajectoryEventAttempt),
        @"tool_call": @(LATrajectoryEventToolCall),
        @"tool_result": @(LATrajectoryEventToolResult),
        @"request_context": @(LATrajectoryEventRequestCtx),
        @"session_end_seed": @(LATrajectoryEventSessionSeed),
        @"plugin_event": @(LATrajectoryEventPluginExt),
    };
    NSNumber *n = map[string ?: @""];
    return n ? (LATrajectoryEventType)n.integerValue : LATrajectoryEventPluginExt;
}
@end

@interface LATrajectoryStore ()
// append-only 主流 + fork 继承的只读前缀（同流语义：前缀不可改，只可续）。
@property (nonatomic, copy) NSString *mutableSessionID;
@property (nonatomic, strong) NSMutableArray<LATrajectoryEvent *> *prefixEvents;
@property (nonatomic, strong) NSMutableArray<LATrajectoryEvent *> *liveEvents;
@property (nonatomic, assign) uint64_t nextSeq;
@property (nonatomic, strong) NSLock *lock;
@end

@implementation LATrajectoryStore
- (instancetype)initWithSessionID:(NSString *)sessionID {
    if (self = [super init]) {
        _mutableSessionID = [sessionID copy] ?: @"";
        _prefixEvents = [NSMutableArray array];
        _liveEvents = [NSMutableArray array];
        _nextSeq = 1;
        _lock = [[NSLock alloc] init];
    }
    return self;
}
- (NSString *)sessionID { return _mutableSessionID; }

- (LATrajectoryEvent *)appendEventOfType:(LATrajectoryEventType)type
                                 payload:(NSDictionary *)payload
                            sourcePlugin:(NSString *)sourcePlugin
                               sessionID:(nullable NSString *)sessionID {
    LATrajectoryEvent *e;
    [self.lock lock];
    e = [[LATrajectoryEvent alloc] initWithSeq:self.nextSeq
                                          type:type
                                       payload:payload ?: @{}
                                  sourcePlugin:sourcePlugin ?: @"unknown"
                                     sessionID:sessionID ?: self.mutableSessionID];
    [self.liveEvents addObject:e];
    self.nextSeq++;
    [self.lock unlock];
    return e;
}

- (nullable LATrajectoryEvent *)appendPluginEventWithKind:(NSString *)extKind
                                                 payload:(NSDictionary *)payload
                                            sourcePlugin:(NSString *)sourcePlugin {
    if (!extKind.length) return nil;
    NSMutableDictionary *full = [(payload ?: @{}) mutableCopy];
    full[@"extKind"] = extKind;
    return [self appendEventOfType:LATrajectoryEventPluginExt payload:full sourcePlugin:sourcePlugin sessionID:self.mutableSessionID];
}

- (NSArray<LATrajectoryEvent *> *)allEvents {
    [self.lock lock];
    NSArray *all = [self.prefixEvents arrayByAddingObjectsFromArray:self.liveEvents];
    [self.lock unlock];
    return all;
}

- (NSArray<LATrajectoryEvent *> *)eventsSinceSeq:(uint64_t)seq {
    NSMutableArray *out = [NSMutableArray array];
    for (LATrajectoryEvent *e in self.allEvents) {
        if (e.seq > seq) [out addObject:e];
    }
    return out;
}
- (NSArray<LATrajectoryEvent *> *)eventsOfType:(LATrajectoryEventType)type {
    NSMutableArray *out = [NSMutableArray array];
    for (LATrajectoryEvent *e in self.allEvents) {
        if (e.type == type) [out addObject:e];
    }
    return out;
}
- (NSArray<LATrajectoryEvent *> *)eventsFromPlugin:(NSString *)sourcePlugin {
    NSMutableArray *out = [NSMutableArray array];
    for (LATrajectoryEvent *e in self.allEvents) {
        if ([e.sourcePlugin isEqualToString:sourcePlugin ?: @""]) [out addObject:e];
    }
    return out;
}
- (NSArray<LATrajectoryEvent *> *)search:(NSString *)keyword {
    if (!keyword.length) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (LATrajectoryEvent *e in self.allEvents) {
        NSString *desc = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:e.payload options:0 error:NULL] encoding:NSUTF8StringEncoding] ?: @"";
        if ([desc rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) [out addObject:e];
    }
    return out;
}

- (NSArray<NSDictionary *> *)projectModelHistory {
    // LLM 历史仅投影：user/assistant 两类消息按 seq 拼成 role/content 数组。
    NSMutableArray *msgs = [NSMutableArray array];
    for (LATrajectoryEvent *e in self.allEvents) {
        if (e.type == LATrajectoryEventUserMessage) {
            [msgs addObject:@{@"role": @"user", @"content": e.payload[@"text"] ?: @""}];
        } else if (e.type == LATrajectoryEventAssistantMsg) {
            [msgs addObject:@{@"role": @"assistant", @"content": e.payload[@"text"] ?: @""}];
        }
    }
    return msgs;
}

- (LATrajectoryStore *)resumedStore {
    // 同 sessionID 续跑：seq 连续（复用同一前缀+活流）。
    LATrajectoryStore *s = [[LATrajectoryStore alloc] initWithSessionID:self.mutableSessionID];
    s.prefixEvents = [[self.allEvents mutableCopy] ?: [NSMutableArray array] mutableCopy];
    uint64_t maxSeq = 0;
    for (LATrajectoryEvent *e in s.prefixEvents) maxSeq = MAX(maxSeq, e.seq);
    s.nextSeq = maxSeq + 1;
    return s;
}
- (LATrajectoryStore *)forkedStoreWithNewSessionID:(NSString *)newSessionID {
    // fork：老流变只读前缀，新 ID 续写（同流语义不断）。
    LATrajectoryStore *s = [[LATrajectoryStore alloc] initWithSessionID:newSessionID];
    s.prefixEvents = [[self.allEvents mutableCopy] ?: [NSMutableArray array] mutableCopy];
    uint64_t maxSeq = 0;
    for (LATrajectoryEvent *e in s.prefixEvents) maxSeq = MAX(maxSeq, e.seq);
    s.nextSeq = maxSeq + 1;
    return s;
}
- (void)replayWithHandler:(BOOL (^)(LATrajectoryEvent *event))handler {
    if (!handler) return;
    for (LATrajectoryEvent *e in self.allEvents) {
        if (!handler(e)) break;
    }
}

- (NSArray<NSDictionary *> *)exportJSON {
    NSMutableArray *out = [NSMutableArray array];
    for (LATrajectoryEvent *e in self.allEvents) {
        [out addObject:@{
            @"seq": @(e.seq),
            @"type": [LATrajectoryEvent stringFromType:e.type],
            @"payload": e.payload,
            @"sourcePlugin": e.sourcePlugin,
            @"timestamp": @([e.timestamp timeIntervalSince1970]),
            @"session": e.sessionID,
        }];
    }
    return out;
}
- (NSUInteger)eventCount { return self.allEvents.count; }
@end
