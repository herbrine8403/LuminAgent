#import "LATodoStore.h"
#import "LAErrors.h"

/* Todo 跟踪实现：单 in_progress 约束 */

@implementation LATodo

+ (NSString *)stringForStatus:(LATodoStatus)status {
    switch (status) {
        case LATodoStatusPending:    return @"pending";
        case LATodoStatusInProgress: return @"in_progress";
        case LATodoStatusCompleted:  return @"completed";
    }
    return @"pending";
}

+ (LATodoStatus)statusForString:(NSString *)string {
    if ([string isEqualToString:@"in_progress"]) return LATodoStatusInProgress;
    if ([string isEqualToString:@"completed"])   return LATodoStatusCompleted;
    return LATodoStatusPending;
}

- (NSDictionary *)toDictionary {
    return @{
        @"id": self.todoID ?: @"",
        @"content": self.content ?: @"",
        @"status": [[self class] stringForStatus:self.status],
        @"sortOrder": @(self.sortOrder),
    };
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _todoID = [dict[@"id"] copy] ?: [[NSUUID UUID] UUIDString];
        _content = [dict[@"content"] copy] ?: @"";
        _status = [[self class] statusForString:dict[@"status"]];
        _sortOrder = [dict[@"sortOrder"] longLongValue];
    }
    return self;
}

@end

@implementation LATodoStore {
    NSMutableArray<LATodo *> *_todos;
    long long _nextOrder;
}

- (instancetype)initWithSessionID:(NSString *)sessionID {
    return [self initWithSessionID:sessionID todos:nil];
}

- (instancetype)initWithSessionID:(NSString *)sessionID todos:(NSArray<LATodo *> *)todos {
    self = [super init];
    if (self) {
        _sessionID = [sessionID copy] ?: @"";
        _todos = [NSMutableArray array];
        _nextOrder = 0;
        if (todos) {
            [_todos addObjectsFromArray:todos];
            for (LATodo *todo in todos) {
                if (todo.sortOrder >= _nextOrder) {
                    _nextOrder = todo.sortOrder + 1;
                }
            }
        }
        [self sortTodos];
    }
    return self;
}

- (void)sortTodos {
    [_todos sortUsingComparator:^NSComparisonResult(LATodo *a, LATodo *b) {
        if (a.sortOrder < b.sortOrder) return NSOrderedAscending;
        if (a.sortOrder > b.sortOrder) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (void)notifyChange {
    id<LATodoStoreDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(todoStoreDidChange:)]) {
        [delegate todoStoreDidChange:self];
    }
}

- (LATodo *)addTodoWithContent:(NSString *)content error:(NSError **)error {
    if (content == nil || content.length == 0) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeStoreFailure, @"Todo 内容为空");
        }
        return nil;
    }
    LATodo *todo = [[LATodo alloc] init];
    todo.todoID = [[NSUUID UUID] UUIDString];
    todo.content = [content copy];
    todo.status = LATodoStatusPending;
    todo.sortOrder = _nextOrder++;
    [_todos addObject:todo];
    [self notifyChange];
    return todo;
}

- (BOOL)setStatus:(LATodoStatus)status forTodoID:(NSString *)todoID error:(NSError **)error {
    LATodo *target = nil;
    for (LATodo *todo in _todos) {
        if ([todo.todoID isEqualToString:todoID]) {
            target = todo;
            break;
        }
    }
    if (!target) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeNotFound, @"Todo 不存在");
        }
        return NO;
    }
    /* 单 in_progress 约束：目标置为进行中时检查其他项 */
    if (status == LATodoStatusInProgress) {
        for (LATodo *todo in _todos) {
            if (todo != target && todo.status == LATodoStatusInProgress) {
                if (error) {
                    NSString *desc = [NSString stringWithFormat:@"已有进行中：%@，请先完成再切换",
                                      todo.content];
                    *error = LAErrorWithCode(LAErrorCodeTodoConflict, desc);
                }
                return NO;
            }
        }
    }
    target.status = status;
    [self notifyChange];
    return YES;
}

- (BOOL)removeTodoWithID:(NSString *)todoID error:(NSError **)error {
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < _todos.count; i++) {
        if ([_todos[i].todoID isEqualToString:todoID]) {
            index = i;
            break;
        }
    }
    if (index == NSNotFound) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeNotFound, @"Todo 不存在");
        }
        return NO;
    }
    [_todos removeObjectAtIndex:index];
    [self notifyChange];
    return YES;
}

- (LATodo *)activeTodo {
    for (LATodo *todo in _todos) {
        if (todo.status == LATodoStatusInProgress) {
            return todo;
        }
    }
    return nil;
}

- (NSArray<LATodo *> *)allTodos {
    return [_todos copy];
}

- (NSString *)progressText {
    NSUInteger done = 0;
    for (LATodo *todo in _todos) {
        if (todo.status == LATodoStatusCompleted) {
            done++;
        }
    }
    return [NSString stringWithFormat:@"%lu/%lu", (unsigned long)done,
            (unsigned long)_todos.count];
}

- (NSArray<NSDictionary *> *)toJSONArray {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:_todos.count];
    for (LATodo *todo in _todos) {
        [array addObject:[todo toDictionary]];
    }
    return [array copy];
}

- (BOOL)loadFromJSONArray:(NSArray<NSDictionary *> *)array error:(NSError **)error {
    if (![array isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeImportInvalid, @"Todo 数组非法");
        }
        return NO;
    }
    NSMutableArray<LATodo *> *loaded = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = LAErrorWithCode(LAErrorCodeImportInvalid, @"Todo 条目非法");
            }
            return NO;
        }
        [loaded addObject:[[LATodo alloc] initWithDictionary:item]];
    }
    _todos = loaded;
    _nextOrder = 0;
    for (LATodo *todo in _todos) {
        if (todo.sortOrder >= _nextOrder) {
            _nextOrder = todo.sortOrder + 1;
        }
    }
    [self sortTodos];
    [self notifyChange];
    return YES;
}

@end
