#import "LASessionStore.h"
#import "AirSessionStore.h"
#import "LAErrors.h"
#import "LASession.h"
#import "LAMessage.h"
#import "LAMessagePart.h"
#import "LATodoStore.h"

/* 存储封装实现：回调收集行 + 单事务写消息/parts */

@implementation LASessionStore {
    AirSessionStore *_cStore;
    BOOL _closed;
}

/* 行收集上下文 */
typedef struct {
    __unsafe_unretained NSMutableArray *rows;
} LARowsContext;

static void LARowsCollect(const char *c0, const char *c1, const char *c2,
                          const char *c3, void *ctx) {
    LARowsContext *context = (LARowsContext *)ctx;
    NSMutableArray *rows = context->rows;
    [rows addObject:@[
        c0 ? [NSString stringWithUTF8String:c0] : @"",
        c1 ? [NSString stringWithUTF8String:c1] : @"",
        c2 ? [NSString stringWithUTF8String:c2] : @"",
        c3 ? [NSString stringWithUTF8String:c3] : @"",
    ]];
}

typedef struct {
    __unsafe_unretained NSMutableArray *rows;
} LAPartsContext;

static void LAPartsCollect(const char *partID, const char *kind, const char *text,
                           const char *metaJSON, long long tokens,
                           long long costMicro, void *ctx) {
    LAPartsContext *context = (LAPartsContext *)ctx;
    NSMutableArray *rows = context->rows;
    [rows addObject:@{
        @"id": partID ? [NSString stringWithUTF8String:partID] : [[NSUUID UUID] UUIDString],
        @"kind": kind ? [NSString stringWithUTF8String:kind] : @"text",
        @"text": text ? [NSString stringWithUTF8String:text] : @"",
        @"meta": metaJSON ? [NSString stringWithUTF8String:metaJSON] : @"{}",
        @"tokens": @(tokens),
        @"costMicro": @(costMicro),
    }];
}

- (instancetype)initWithPath:(NSString *)dbPath error:(NSError **)error {
    self = [super init];
    if (self) {
        const char *path = dbPath ? [dbPath UTF8String] : ":memory:";
        char errBuf[512] = {0};
        _cStore = AirSessionStoreOpenWithError(path, errBuf, sizeof(errBuf));
        if (!_cStore) {
            if (error) {
                NSString *desc = [NSString stringWithFormat:@"打开存储失败：%s", errBuf];
                *error = LAErrorWithCode(LAErrorCodeStoreFailure, desc);
            }
            return nil;
        }
        _databasePath = [dbPath copy] ?: @":memory:";
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (!_closed) {
        _closed = YES;
        AirSessionStoreClose(_cStore);
        _cStore = NULL;
    }
}

/* 内部：检查可用性 */
- (BOOL)ensureOpenWithError:(NSError **)error {
    if (_closed || !_cStore) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeStoreFailure, @"存储已关闭");
        }
        return NO;
    }
    return YES;
}

- (NSError *)storeErrorWithFallback:(NSString *)fallback {
    const char *msg = AirSessionStoreLastError(_cStore);
    NSString *desc = fallback;
    if (msg && msg[0] != '\0') {
        desc = [NSString stringWithFormat:@"%@：%s", fallback, msg];
    }
    return LAErrorWithCode(LAErrorCodeStoreFailure, desc);
}

#pragma mark - 会话

- (BOOL)saveSession:(LASession *)session error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return NO;
    }
    if (!session.sessionID) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeStoreFailure, @"会话标识为空");
        }
        return NO;
    }
    NSString *mode = (session.mainMode == LAAgentMainModePlan) ? @"plan" : @"build";
    int rc = AirSessionStoreUpsertSession(_cStore,
                                          [session.sessionID UTF8String],
                                          session.parentID ? [session.parentID UTF8String] : NULL,
                                          session.title ? [session.title UTF8String] : "",
                                          [mode UTF8String],
                                          (long long)session.createdAt,
                                          (long long)[[NSDate date] timeIntervalSince1970]);
    if (rc != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"保存会话失败"];
        }
        return NO;
    }
    return YES;
}

- (LASession *)loadSessionWithID:(NSString *)sessionID error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray array];
    LARowsContext ctx = { rows };
    /* 全量列出后过滤单条（会话量小，避免新增单查 C 接口） */
    if (AirSessionStoreListSessions(_cStore, LARowsCollect, &ctx) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"读取会话失败"];
        }
        return nil;
    }
    for (NSArray *row in rows) {
        if ([row[0] isEqualToString:sessionID]) {
            LASession *session = [[LASession alloc] init];
            session.sessionID = [row[0] copy];
            session.parentID = [row[1] length] > 0 ? [row[1] copy] : nil;
            session.title = [row[2] copy];
            session.mainMode = [row[3] isEqualToString:@"plan"] ? LAAgentMainModePlan : LAAgentMainModeBuild;
            session.snapshotEnabled = YES;
            session.imageMaxDimension = LAAgentDefaultImageMaxDimension;
            session.imageMaxBytes = LAAgentDefaultImageMaxBytes;
            return session;
        }
    }
    if (error) {
        *error = LAErrorWithCode(LAErrorCodeNotFound, @"会话不存在");
    }
    return nil;
}

- (BOOL)deleteSessionWithID:(NSString *)sessionID error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return NO;
    }
    if (AirSessionStoreDeleteSession(_cStore, [sessionID UTF8String]) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"删除会话失败"];
        }
        return NO;
    }
    return YES;
}

- (NSArray<LASession *> *)loadAllSessionsWithError:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray array];
    LARowsContext ctx = { rows };
    if (AirSessionStoreListSessions(_cStore, LARowsCollect, &ctx) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"列出会话失败"];
        }
        return nil;
    }
    return [self sessionsFromRows:rows];
}

- (NSArray<LASession *> *)loadChildrenOfParentID:(NSString *)parentID
                                           error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray array];
    LARowsContext ctx = { rows };
    const char *parent = parentID ? [parentID UTF8String] : NULL;
    if (AirSessionStoreListChildren(_cStore, parent, LARowsCollect, &ctx) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"列出子会话失败"];
        }
        return nil;
    }
    return [self sessionsFromRows:rows];
}

- (NSArray<LASession *> *)sessionsFromRows:(NSArray<NSArray *> *)rows {
    NSMutableArray<LASession *> *sessions = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSArray *row in rows) {
        LASession *session = [[LASession alloc] init];
        session.sessionID = [row[0] copy];
        session.parentID = [row[1] length] > 0 ? [row[1] copy] : nil;
        session.title = [row[2] copy];
        session.mainMode = [row[3] isEqualToString:@"plan"] ? LAAgentMainModePlan : LAAgentMainModeBuild;
        session.snapshotEnabled = YES;
        session.imageMaxDimension = LAAgentDefaultImageMaxDimension;
        session.imageMaxBytes = LAAgentDefaultImageMaxBytes;
        [sessions addObject:session];
    }
    return [sessions copy];
}

#pragma mark - 消息与 parts

- (BOOL)appendMessage:(LAMessage *)message error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return NO;
    }
    if (AirSessionStoreBegin(_cStore) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"开启事务失败"];
        }
        return NO;
    }
    BOOL ok = YES;
    if (AirSessionStoreInsertMessage(_cStore,
                                     [message.messageID UTF8String],
                                     [message.sessionID UTF8String],
                                     [[LAMessage stringForRole:message.role] UTF8String],
                                     (long long)message.createdAt) != 0) {
        ok = NO;
    }
    for (LAMessagePart *part in message.parts) {
        if (!ok) {
            break;
        }
        /* 扩展字段经 meta JSON 携带，保证 .m 与 .h 一致且可回读 */
        NSDictionary *meta = @{
            @"mimeType": part.mimeType ?: @"",
            @"filePath": part.filePath ?: @"",
            @"toolName": part.toolName ?: @"",
            @"toolArguments": part.toolArguments ?: @"",
            @"agentName": part.agentName ?: @"",
            @"patchText": part.patchText ?: @"",
            @"neverTrim": @(part.neverTrim),
            @"createdAt": @(part.createdAt),
        };
        NSData *metaData = [NSJSONSerialization dataWithJSONObject:meta options:0 error:nil];
        NSString *metaString = metaData
            ? [[NSString alloc] initWithData:metaData encoding:NSUTF8StringEncoding] : @"{}";
        if (AirSessionStoreInsertPart(_cStore,
                                      [part.partID UTF8String],
                                      [message.messageID UTF8String],
                                      [[LAMessagePart stringForKind:part.kind] UTF8String],
                                      part.text ? [part.text UTF8String] : "",
                                      [metaString UTF8String],
                                      part.tokens,
                                      part.costMicro) != 0) {
            ok = NO;
        }
    }
    if (ok) {
        if (AirSessionStoreCommit(_cStore) != 0) {
            ok = NO;
        }
    }
    if (!ok) {
        AirSessionStoreRollback(_cStore);
        if (error) {
            *error = [self storeErrorWithFallback:@"追加消息失败"];
        }
        return NO;
    }
    return YES;
}

- (LAMessagePart *)partFromRow:(NSDictionary *)row {
    LAMessagePart *part = [[LAMessagePart alloc] init];
    part.partID = [row[@"id"] copy];
    part.kind = [LAMessagePart kindForString:row[@"kind"]];
    part.text = [row[@"text"] copy] ?: @"";
    part.tokens = [row[@"tokens"] longLongValue];
    part.costMicro = [row[@"costMicro"] longLongValue];
    /* 解析 meta 扩展字段 */
    NSData *metaData = [row[@"meta"] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *meta = metaData
        ? [NSJSONSerialization JSONObjectWithData:metaData options:0 error:nil] : nil;
    if ([meta isKindOfClass:[NSDictionary class]]) {
        if ([meta[@"mimeType"] length] > 0)      part.mimeType = [meta[@"mimeType"] copy];
        if ([meta[@"filePath"] length] > 0)      part.filePath = [meta[@"filePath"] copy];
        if ([meta[@"toolName"] length] > 0)      part.toolName = [meta[@"toolName"] copy];
        if ([meta[@"toolArguments"] length] > 0) part.toolArguments = [meta[@"toolArguments"] copy];
        if ([meta[@"agentName"] length] > 0)     part.agentName = [meta[@"agentName"] copy];
        if ([meta[@"patchText"] length] > 0)     part.patchText = [meta[@"patchText"] copy];
        part.neverTrim = [meta[@"neverTrim"] boolValue];
        part.createdAt = [meta[@"createdAt"] doubleValue];
    }
    return part;
}

- (NSArray<LAMessage *> *)loadMessagesForSessionID:(NSString *)sessionID
                                             error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray array];
    LARowsContext ctx = { rows };
    if (AirSessionStoreListMessages(_cStore, [sessionID UTF8String],
                                    LARowsCollect, &ctx) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"读取消息失败"];
        }
        return nil;
    }
    NSMutableArray<LAMessage *> *messages = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSArray *row in rows) {
        LAMessage *message = [[LAMessage alloc] init];
        message.messageID = [row[0] copy];
        message.sessionID = [sessionID copy];
        message.role = [LAMessage roleForString:row[1]];
        message.createdAt = [row[2] doubleValue];
        message.reverted = [row[3] boolValue];
        message.parts = [NSMutableArray array];
        /* 回填 parts */
        NSMutableArray *partRows = [NSMutableArray array];
        LAPartsContext partsCtx = { partRows };
        AirSessionStoreListParts(_cStore, [message.messageID UTF8String],
                                 LAPartsCollect, &partsCtx);
        for (NSDictionary *partRow in partRows) {
            [message.parts addObject:[self partFromRow:partRow]];
        }
        [messages addObject:message];
    }
    return [messages copy];
}

- (BOOL)truncateMessagesOfSessionID:(NSString *)sessionID
                       afterMessage:(LAMessage *)message
                              error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return NO;
    }
    long long cutoff = message ? (long long)message.createdAt : 0;
    if (AirSessionStoreDeleteMessagesAfter(_cStore, [sessionID UTF8String], cutoff) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"截断消息失败"];
        }
        return NO;
    }
    return YES;
}

- (BOOL)markMessageWithID:(NSString *)messageID
                  reverted:(BOOL)reverted
                     error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return NO;
    }
    if (AirSessionStoreMarkMessageReverted(_cStore, [messageID UTF8String],
                                           reverted ? 1 : 0) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"标记消息失败"];
        }
        return NO;
    }
    return YES;
}

#pragma mark - Todo

- (BOOL)saveTodos:(NSArray<LATodo *> *)todos
     forSessionID:(NSString *)sessionID
            error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return NO;
    }
    if (AirSessionStoreBegin(_cStore) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"开启事务失败"];
        }
        return NO;
    }
    BOOL ok = YES;
    if (AirSessionStoreDeleteTodosOfSession(_cStore, [sessionID UTF8String]) != 0) {
        ok = NO;
    }
    for (LATodo *todo in todos) {
        if (!ok) {
            break;
        }
        if (AirSessionStoreUpsertTodo(_cStore,
                                      [todo.todoID UTF8String],
                                      [sessionID UTF8String],
                                      todo.content ? [todo.content UTF8String] : "",
                                      [[LATodo stringForStatus:todo.status] UTF8String],
                                      todo.sortOrder) != 0) {
            ok = NO;
        }
    }
    if (ok) {
        if (AirSessionStoreCommit(_cStore) != 0) {
            ok = NO;
        }
    }
    if (!ok) {
        AirSessionStoreRollback(_cStore);
        if (error) {
            *error = [self storeErrorWithFallback:@"保存 Todo 失败"];
        }
        return NO;
    }
    return YES;
}

- (NSArray<LATodo *> *)loadTodosForSessionID:(NSString *)sessionID
                                       error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray array];
    LARowsContext ctx = { rows };
    if (AirSessionStoreListTodos(_cStore, [sessionID UTF8String],
                                 LARowsCollect, &ctx) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"读取 Todo 失败"];
        }
        return nil;
    }
    NSMutableArray<LATodo *> *todos = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSArray *row in rows) {
        LATodo *todo = [[LATodo alloc] init];
        todo.todoID = [row[0] copy];
        todo.content = [row[1] copy];
        todo.status = [LATodo statusForString:row[2]];
        todo.sortOrder = [row[3] longLongValue];
        [todos addObject:todo];
    }
    return [todos copy];
}

#pragma mark - 用量与事件

- (BOOL)addUsageTokensIn:(long long)tokensIn
               tokensOut:(long long)tokensOut
               costMicro:(long long)costMicro
            forSessionID:(NSString *)sessionID
                   error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return NO;
    }
    if (AirSessionStoreAddUsage(_cStore, [sessionID UTF8String],
                                tokensIn, tokensOut, costMicro) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"记录用量失败"];
        }
        return NO;
    }
    return YES;
}

- (NSDictionary *)loadUsageForSessionID:(NSString *)sessionID
                                 error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return nil;
    }
    long long tokensIn = 0, tokensOut = 0, costMicro = 0;
    if (AirSessionStoreGetUsage(_cStore, [sessionID UTF8String],
                                &tokensIn, &tokensOut, &costMicro) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"读取用量失败"];
        }
        return nil;
    }
    return @{@"tokensIn": @(tokensIn), @"tokensOut": @(tokensOut), @"costMicro": @(costMicro)};
}

- (BOOL)appendEventOfKind:(NSString *)kind
                 payload:(NSDictionary *)payload
            forSessionID:(NSString *)sessionID
                   error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return NO;
    }
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload ?: @{}
                                                         options:0 error:nil];
    NSString *payloadString = payloadData
        ? [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding] : @"{}";
    NSString *eventID = [[NSUUID UUID] UUIDString];
    long long now = (long long)[[NSDate date] timeIntervalSince1970];
    if (AirSessionStoreAppendEvent(_cStore, [eventID UTF8String],
                                   [sessionID UTF8String],
                                   kind ? [kind UTF8String] : "event",
                                   [payloadString UTF8String], now) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"追加事件失败"];
        }
        return NO;
    }
    return YES;
}

- (NSArray<NSDictionary *> *)loadEventsForSessionID:(NSString *)sessionID
                                              error:(NSError **)error {
    if (![self ensureOpenWithError:error]) {
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray array];
    LARowsContext ctx = { rows };
    if (AirSessionStoreListEvents(_cStore, [sessionID UTF8String],
                                  LARowsCollect, &ctx) != 0) {
        if (error) {
            *error = [self storeErrorWithFallback:@"读取事件失败"];
        }
        return nil;
    }
    NSMutableArray<NSDictionary *> *events = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSArray *row in rows) {
        NSData *payloadData = [row[2] dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *payload = payloadData
            ? [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil] : nil;
        [events addObject:@{
            @"id": row[0],
            @"kind": row[1],
            @"payload": [payload isKindOfClass:[NSDictionary class]] ? payload : @{},
            @"createdAt": @([row[3] doubleValue]),
        }];
    }
    return [events copy];
}

@end
