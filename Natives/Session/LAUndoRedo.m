#import "LAUndoRedo.h"
#import "LAErrors.h"

/* Undo/Redo 实现：双栈（undo/redo）按会话隔离 */

@implementation LAFileChange

+ (instancetype)changeWithPath:(NSString *)path kind:(NSString *)kind {
    LAFileChange *change = [[LAFileChange alloc] init];
    change.path = [path copy] ?: @"";
    change.kind = [kind copy] ?: @"modified";
    return change;
}

- (NSDictionary *)toDictionary {
    return @{@"path": self.path ?: @"", @"kind": self.kind ?: @"modified"};
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _path = [dict[@"path"] copy] ?: @"";
        _kind = [dict[@"kind"] copy] ?: @"modified";
    }
    return self;
}

@end

@implementation LAUndoSnapshot
@end

@implementation LAUndoRedo {
    NSMutableDictionary<NSString *, NSMutableArray<LAUndoSnapshot *> *> *_undoStacks;
    NSMutableDictionary<NSString *, NSMutableArray<LAUndoSnapshot *> *> *_redoStacks;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _snapshotEnabled = YES;
        _undoStacks = [NSMutableDictionary dictionary];
        _redoStacks = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSMutableArray<LAUndoSnapshot *> *)undoStackForSessionID:(NSString *)sessionID {
    NSMutableArray *stack = _undoStacks[sessionID];
    if (!stack) {
        stack = [NSMutableArray array];
        _undoStacks[sessionID] = stack;
    }
    return stack;
}

- (NSMutableArray<LAUndoSnapshot *> *)redoStackForSessionID:(NSString *)sessionID {
    NSMutableArray *stack = _redoStacks[sessionID];
    if (!stack) {
        stack = [NSMutableArray array];
        _redoStacks[sessionID] = stack;
    }
    return stack;
}

- (void)pushSnapshotForSessionID:(NSString *)sessionID
                         changes:(NSArray<LAFileChange *> *)changes
                    messageCount:(NSUInteger)messageCount
                           label:(NSString *)label {
    if (sessionID.length == 0) {
        return;
    }
    LAUndoSnapshot *snapshot = [[LAUndoSnapshot alloc] init];
    snapshot.snapshotID = [[NSUUID UUID] UUIDString];
    snapshot.label = [label copy] ?: @"还原点";
    snapshot.createdAt = [[NSDate date] timeIntervalSince1970];
    snapshot.changes = [changes copy] ?: @[];
    snapshot.messageCount = messageCount;
    [[self undoStackForSessionID:sessionID] addObject:snapshot];
    /* 新快照使 redo 失效 */
    [[self redoStackForSessionID:sessionID] removeAllObjects];
}

- (BOOL)canUndoForSessionID:(NSString *)sessionID {
    return _undoStacks[sessionID].count > 0;
}

- (BOOL)canRedoForSessionID:(NSString *)sessionID {
    return _redoStacks[sessionID].count > 0;
}

- (BOOL)undoForSessionID:(NSString *)sessionID
    restoredMessageCount:(NSUInteger *)restoredMessageCount
         revertedChanges:(NSArray<LAFileChange *> **)revertedChanges
                   error:(NSError **)error {
    NSMutableArray *undo = _undoStacks[sessionID];
    if (undo.count == 0) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeNotFound, @"无可回滚的还原点");
        }
        return NO;
    }
    LAUndoSnapshot *snapshot = [undo lastObject];
    /* 文件回滚：快照开且有变更且有 delegate 时执行，否则仅回滚消息 */
    if (self.snapshotEnabled && snapshot.changes.count > 0) {
        id delegate = self.delegate;
        if (delegate && [delegate respondsToSelector:@selector(undoRedo:revertChanges:forSessionID:error:)]) {
            if (![delegate undoRedo:self revertChanges:snapshot.changes
                       forSessionID:sessionID error:error]) {
                return NO;
            }
        }
    }
    [undo removeLastObject];
    [[self redoStackForSessionID:sessionID] addObject:snapshot];
    if (restoredMessageCount) {
        *restoredMessageCount = snapshot.messageCount;
    }
    if (revertedChanges) {
        *revertedChanges = snapshot.changes;
    }
    return YES;
}

- (BOOL)redoForSessionID:(NSString *)sessionID
    restoredMessageCount:(NSUInteger *)restoredMessageCount
        reappliedChanges:(NSArray<LAFileChange *> **)reappliedChanges
                   error:(NSError **)error {
    NSMutableArray *redo = _redoStacks[sessionID];
    if (redo.count == 0) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeNotFound, @"无可重做的记录");
        }
        return NO;
    }
    LAUndoSnapshot *snapshot = [redo lastObject];
    if (self.snapshotEnabled && snapshot.changes.count > 0) {
        id delegate = self.delegate;
        if (delegate && [delegate respondsToSelector:@selector(undoRedo:reapplyChanges:forSessionID:error:)]) {
            if (![delegate undoRedo:self reapplyChanges:snapshot.changes
                       forSessionID:sessionID error:error]) {
                return NO;
            }
        }
    }
    [redo removeLastObject];
    [[self undoStackForSessionID:sessionID] addObject:snapshot];
    if (restoredMessageCount) {
        *restoredMessageCount = snapshot.messageCount;
    }
    if (reappliedChanges) {
        *reappliedChanges = snapshot.changes;
    }
    return YES;
}

- (void)clearForSessionID:(NSString *)sessionID {
    [_undoStacks removeObjectForKey:sessionID];
    [_redoStacks removeObjectForKey:sessionID];
}

@end
