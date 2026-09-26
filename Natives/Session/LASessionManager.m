#import "LASessionManager.h"
#import "LAErrors.h"
#import "LASessionStore.h"
#import "LAMessage.h"
#import "LAMessagePart.h"
#import "LATodoStore.h"
#import "LAUndoRedo.h"

/* 会话管理器实现 */

NSString * const LASessionEventCreated = @"created";
NSString * const LASessionEventRestored = @"restored";
NSString * const LASessionEventDeleted = @"deleted";
NSString * const LASessionEventForked = @"forked";
NSString * const LASessionEventAborted = @"aborted";
NSString * const LASessionEventReverted = @"reverted";
NSString * const LASessionEventUnreverted = @"unreverted";
NSString * const LASessionEventCancelled = @"cancelled";
NSString * const LASessionEventDoomLoop = @"doom_loop";

@implementation LASessionManager {
    NSMutableSet<NSString *> *_abortedSessionIDs;
    /* unrevert 暂存：被 revert 截掉的消息（仅内存，重启丢失） */
    NSMutableDictionary<NSString *, NSArray<LAMessage *> *> *_revertStash;
}

- (instancetype)initWithStore:(LASessionStore *)store {
    self = [super init];
    if (self) {
        if (store) {
            _store = store;
        } else {
            _store = [[LASessionStore alloc] initWithPath:nil error:nil];
        }
        _undoRedo = [[LAUndoRedo alloc] init];
        _abortedSessionIDs = [NSMutableSet set];
        _revertStash = [NSMutableDictionary dictionary];
    }
    return self;
}

/* 事件双写：delegate + events 表（写表失败不阻断主流程） */
- (void)emitEventOfKind:(NSString *)kind
               payload:(NSDictionary *)payload
             sessionID:(NSString *)sessionID {
    id<LASessionManagerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(sessionManager:didAppendEventOfKind:payload:sessionID:)]) {
        [delegate sessionManager:self didAppendEventOfKind:kind
                         payload:payload ?: @{} sessionID:sessionID ?: @""];
    }
    if (sessionID.length > 0) {
        [self.store appendEventOfKind:kind payload:payload ?: @{}
                         forSessionID:sessionID error:nil];
    }
}

#pragma mark - 创建/恢复/删除

- (LASession *)createSessionWithTitle:(NSString *)title
                             parentID:(NSString *)parentID
                                 mode:(LAAgentMainMode)mode
                         firstMessage:(NSString *)firstMessage
                                error:(NSError **)error {
    LASession *session = [LASession sessionWithTitle:title parentID:parentID mode:mode];
    if (![self.store saveSession:session error:error]) {
        return nil;
    }
    /* 首条用户提示一并落库 */
    if (firstMessage.length > 0) {
        LAMessage *message = [LAMessage messageWithSessionID:session.sessionID
                                                        role:LAMessageRoleUser];
        [message appendPart:[LAMessagePart partWithKind:LAMessagePartKindText
                                                   text:firstMessage]];
        NSError *appendError = nil;
        if (![self.store appendMessage:message error:&appendError]) {
            if (error) {
                *error = appendError;
            }
            return nil;
        }
    }
    [self emitEventOfKind:LASessionEventCreated
                  payload:@{@"title": session.title ?: @"", @"mode": session.mainMode == LAAgentMainModePlan ? @"plan" : @"build"}
                sessionID:session.sessionID];
    return session;
}

- (LASession *)restoreSessionWithID:(NSString *)sessionID
                              error:(NSError **)error {
    LASession *session = [self.store loadSessionWithID:sessionID error:error];
    if (!session) {
        return nil;
    }
    [self emitEventOfKind:LASessionEventRestored payload:@{} sessionID:sessionID];
    return session;
}

- (NSArray<LAMessage *> *)messagesForSessionID:(NSString *)sessionID
                                         error:(NSError **)error {
    return [self.store loadMessagesForSessionID:sessionID error:error];
}

- (BOOL)deleteSessionWithID:(NSString *)sessionID error:(NSError **)error {
    if (![self.store deleteSessionWithID:sessionID error:error]) {
        return NO;
    }
    [self.undoRedo clearForSessionID:sessionID];
    [_abortedSessionIDs removeObject:sessionID];
    [_revertStash removeObjectForKey:sessionID];
    [self emitEventOfKind:LASessionEventDeleted payload:@{} sessionID:sessionID];
    return YES;
}

#pragma mark - fork 与导航

- (LASession *)forkSessionWithID:(NSString *)sessionID
                   fromMessageID:(NSString *)messageID
                        newTitle:(NSString *)newTitle
                           error:(NSError **)error {
    LASession *source = [self.store loadSessionWithID:sessionID error:error];
    if (!source) {
        return nil;
    }
    NSError *loadError = nil;
    NSArray<LAMessage *> *sourceMessages =
        [self.store loadMessagesForSessionID:sessionID error:&loadError];
    if (!sourceMessages && loadError) {
        if (error) {
            *error = loadError;
        }
        return nil;
    }
    /* 定位分叉点：继承该消息及之前全部上下文 */
    NSUInteger forkIndex = sourceMessages.count;
    if (messageID.length > 0) {
        forkIndex = NSNotFound;
        for (NSUInteger i = 0; i < sourceMessages.count; i++) {
            if ([sourceMessages[i].messageID isEqualToString:messageID]) {
                forkIndex = i + 1;
                break;
            }
        }
        if (forkIndex == NSNotFound) {
            if (error) {
                *error = LAErrorWithCode(LAErrorCodeNotFound, @"分叉消息不存在");
            }
            return nil;
        }
    }
    NSString *title = newTitle.length > 0
        ? newTitle : [NSString stringWithFormat:@"%@（分叉）", source.title];
    LASession *forked = [LASession sessionWithTitle:title
                                           parentID:sessionID
                                               mode:source.mainMode];
    forked.snapshotEnabled = source.snapshotEnabled;
    forked.tokenLimit = source.tokenLimit;
    if (![self.store saveSession:forked error:error]) {
        return nil;
    }
    /* 深拷贝消息（新 ID，归属新会话） */
    for (NSUInteger i = 0; i < forkIndex; i++) {
        LAMessage *origin = sourceMessages[i];
        LAMessage *copy = [LAMessage messageWithSessionID:forked.sessionID
                                                     role:origin.role];
        copy.createdAt = origin.createdAt;
        for (LAMessagePart *part in origin.parts) {
            LAMessagePart *partCopy = [LAMessagePart partWithKind:part.kind text:part.text];
            partCopy.mimeType = part.mimeType;
            partCopy.filePath = part.filePath;
            partCopy.toolName = part.toolName;
            partCopy.toolArguments = part.toolArguments;
            partCopy.agentName = part.agentName;
            partCopy.patchText = part.patchText;
            partCopy.tokens = part.tokens;
            partCopy.costMicro = part.costMicro;
            partCopy.neverTrim = part.neverTrim;
            partCopy.createdAt = part.createdAt;
            [copy appendPart:partCopy];
        }
        if (![self.store appendMessage:copy error:error]) {
            return nil;
        }
    }
    [self emitEventOfKind:LASessionEventForked
                  payload:@{@"from": sessionID ?: @"",
                            @"fromMessage": messageID ?: @"",
                            @"inherited": @(forkIndex)}
                sessionID:forked.sessionID];
    return forked;
}

- (NSArray<LASession *> *)childrenOfSessionID:(NSString *)sessionID
                                        error:(NSError **)error {
    return [self.store loadChildrenOfParentID:sessionID error:error];
}

- (NSArray<LASession *> *)rootSessionsWithError:(NSError **)error {
    return [self.store loadChildrenOfParentID:nil error:error];
}

#pragma mark - 追加/abort

- (BOOL)appendMessage:(LAMessage *)message
            tokensIn:(long long)tokensIn
           tokensOut:(long long)tokensOut
           costMicro:(long long)costMicro
               error:(NSError **)error {
    if ([self isAbortedSessionWithID:message.sessionID]) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeAborted, @"会话已被中断，消息未追加");
        }
        return NO;
    }
    if (![self.store appendMessage:message error:error]) {
        return NO;
    }
    /* 用量累计（免费记 0 由调用方传入 0） */
    if (tokensIn != 0 || tokensOut != 0 || costMicro != 0) {
        [self.store addUsageTokensIn:tokensIn tokensOut:tokensOut costMicro:costMicro
                        forSessionID:message.sessionID error:nil];
    }
    return YES;
}

- (void)abortSessionWithID:(NSString *)sessionID {
    if (sessionID.length == 0) {
        return;
    }
    [_abortedSessionIDs addObject:sessionID];
    [self emitEventOfKind:LASessionEventAborted payload:@{} sessionID:sessionID];
}

- (BOOL)isAbortedSessionWithID:(NSString *)sessionID {
    return [_abortedSessionIDs containsObject:sessionID ?: @""];
}

- (void)clearAbortForSessionID:(NSString *)sessionID {
    [_abortedSessionIDs removeObject:sessionID ?: @""];
}

#pragma mark - revert/unrevert

- (BOOL)revertSessionID:(NSString *)sessionID
          toMessageID:(NSString *)messageID
                error:(NSError **)error {
    NSError *loadError = nil;
    NSArray<LAMessage *> *messages =
        [self.store loadMessagesForSessionID:sessionID error:&loadError];
    if (!messages && loadError) {
        if (error) {
            *error = loadError;
        }
        return NO;
    }
    LAMessage *target = nil;
    NSUInteger targetIndex = NSNotFound;
    for (NSUInteger i = 0; i < messages.count; i++) {
        if ([messages[i].messageID isEqualToString:messageID]) {
            target = messages[i];
            targetIndex = i;
            break;
        }
    }
    if (!target) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeNotFound, @"回滚目标消息不存在");
        }
        return NO;
    }
    /* 暂存截掉部分供 unrevert */
    if (targetIndex + 1 < messages.count) {
        _revertStash[sessionID] =
            [messages subarrayWithRange:NSMakeRange(targetIndex + 1,
                                                    messages.count - targetIndex - 1)];
    } else {
        _revertStash[sessionID] = @[];
    }
    if (![self.store truncateMessagesOfSessionID:sessionID
                                    afterMessage:target error:error]) {
        return NO;
    }
    [self.store markMessageWithID:messageID reverted:YES error:nil];
    [self emitEventOfKind:LASessionEventReverted
                  payload:@{@"toMessage": messageID ?: @""} sessionID:sessionID];
    return YES;
}

- (BOOL)unrevertSessionID:(NSString *)sessionID error:(NSError **)error {
    NSArray<LAMessage *> *stashed = _revertStash[sessionID];
    if (!stashed) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeNotFound, @"无可恢复的回滚记录");
        }
        return NO;
    }
    for (LAMessage *message in stashed) {
        message.reverted = NO;
        if (![self.store appendMessage:message error:error]) {
            return NO;
        }
    }
    [_revertStash removeObjectForKey:sessionID];
    [self emitEventOfKind:LASessionEventUnreverted
                  payload:@{@"restored": @(stashed.count)} sessionID:sessionID];
    return YES;
}

#pragma mark - diff/export/import

- (NSString *)diffForSessionID:(NSString *)sessionID error:(NSError **)error {
    NSError *loadError = nil;
    NSArray<LAMessage *> *messages =
        [self.store loadMessagesForSessionID:sessionID error:&loadError];
    if (!messages && loadError) {
        if (error) {
            *error = loadError;
        }
        return nil;
    }
    NSMutableString *diff = [NSMutableString string];
    for (LAMessage *message in messages) {
        for (LAMessagePart *part in message.parts) {
            if (part.kind == LAMessagePartKindPatch && part.patchText.length > 0) {
                [diff appendFormat:@"--- %@ ---\n%@\n", part.filePath ?: @"未命名", part.patchText];
            }
        }
    }
    return [diff copy];
}

- (NSData *)exportSessionWithID:(NSString *)sessionID error:(NSError **)error {
    LASession *session = [self.store loadSessionWithID:sessionID error:error];
    if (!session) {
        return nil;
    }
    NSError *loadError = nil;
    NSArray<LAMessage *> *messages =
        [self.store loadMessagesForSessionID:sessionID error:&loadError];
    if (!messages && loadError) {
        if (error) {
            *error = loadError;
        }
        return nil;
    }
    NSArray<LATodo *> *todos = [self.store loadTodosForSessionID:sessionID error:nil];
    NSMutableArray *messageDicts = [NSMutableArray arrayWithCapacity:messages.count];
    for (LAMessage *message in messages) {
        [messageDicts addObject:[message toDictionary]];
    }
    NSMutableArray *todoDicts = [NSMutableArray array];
    for (LATodo *todo in todos) {
        [todoDicts addObject:[todo toDictionary]];
    }
    /* 仅会话/消息/Todo，不含任何密钥 */
    NSDictionary *root = @{
        @"version": @1,
        @"session": [session toDictionary],
        @"messages": [messageDicts copy],
        @"todos": [todoDicts copy],
    };
    NSError *serializeError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0
                                                     error:&serializeError];
    if (!data) {
        /* 构造期错误理论上不可达，防御性回退 */
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeStoreFailure, @"导出序列化失败");
        }
        return nil;
    }
    return data;
}

- (LASession *)importSessionFromData:(NSData *)data error:(NSError **)error {
    if (!data) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeImportInvalid, @"导入数据为空");
        }
        return nil;
    }
    NSError *parseError = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0
                                                          error:&parseError];
    if (![root isKindOfClass:[NSDictionary class]] ||
        [root[@"version"] integerValue] != 1 ||
        ![root[@"session"] isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeImportInvalid, @"导入格式不支持（需 version=1）");
        }
        return nil;
    }
    LASession *incoming = [[LASession alloc] initWithDictionary:root[@"session"]];
    /* ID 冲突重映射：旧→新，保证关联完整 */
    NSError *lookupError = nil;
    LASession *existing = [self.store loadSessionWithID:incoming.sessionID
                                                  error:&lookupError];
    NSDictionary<NSString *, NSString *> *messageIDMap = @{};
    NSMutableDictionary *mutableMap = [NSMutableDictionary dictionary];
    if (existing) {
        NSString *newSessionID = [[NSUUID UUID] UUIDString];
        NSArray *incomingMessages = root[@"messages"];
        for (NSDictionary *messageDict in incomingMessages) {
            if ([messageDict isKindOfClass:[NSDictionary class]] && messageDict[@"id"]) {
                mutableMap[messageDict[@"id"]] = [[NSUUID UUID] UUIDString];
            }
        }
        messageIDMap = [mutableMap copy];
        incoming.sessionID = newSessionID;
    }
    if (![self.store saveSession:incoming error:error]) {
        return nil;
    }
    for (NSDictionary *messageDict in root[@"messages"]) {
        if (![messageDict isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        LAMessage *message = [[LAMessage alloc] initWithDictionary:messageDict
                                                         sessionID:incoming.sessionID];
        NSString *remapped = messageIDMap[message.messageID];
        if (remapped) {
            message.messageID = remapped;
        }
        /* parts 保持原 ID（冲突概率可忽略，落库为 REPLACE 语义） */
        if (![self.store appendMessage:message error:error]) {
            return nil;
        }
    }
    NSMutableArray<LATodo *> *todos = [NSMutableArray array];
    for (NSDictionary *todoDict in root[@"todos"]) {
        if ([todoDict isKindOfClass:[NSDictionary class]]) {
            [todos addObject:[[LATodo alloc] initWithDictionary:todoDict]];
        }
    }
    if (todos.count > 0) {
        [self.store saveTodos:todos forSessionID:incoming.sessionID error:nil];
    }
    return incoming;
}

@end
