#ifndef LA_TODO_STORE_H
#define LA_TODO_STORE_H

/* Todo 跟踪：pending/in_progress/completed 三态；
 * 多步任务先建单后执行，一次仅允许一个 in_progress。 */

#import <Foundation/Foundation.h>

/* Todo 状态 */
typedef NS_ENUM(NSInteger, LATodoStatus) {
    LATodoStatusPending,    /* 待执行 */
    LATodoStatusInProgress, /* 进行中（全会话唯一） */
    LATodoStatusCompleted,  /* 已完成 */
};

@interface LATodo : NSObject

@property (nonatomic, copy) NSString *todoID;   /* Todo 唯一标识 */
@property (nonatomic, copy) NSString *content;  /* 内容描述 */
@property (nonatomic, assign) LATodoStatus status; /* 状态 */
@property (nonatomic, assign) long long sortOrder; /* 排序序号 */

+ (NSString *)stringForStatus:(LATodoStatus)status;
+ (LATodoStatus)statusForString:(NSString *)string;

- (NSDictionary *)toDictionary;
- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end

@protocol LATodoStoreDelegate;

@interface LATodoStore : NSObject

/* 所属会话标识 */
@property (nonatomic, copy, readonly) NSString *sessionID;
@property (nonatomic, weak) id<LATodoStoreDelegate> delegate;

/* 以会话标识初始化，可选载入既有 Todo */
- (instancetype)initWithSessionID:(NSString *)sessionID;
- (instancetype)initWithSessionID:(NSString *)sessionID todos:(NSArray<LATodo *> *)todos;

/* 新增 Todo（默认 pending），返回新建对象 */
- (LATodo *)addTodoWithContent:(NSString *)content error:(NSError **)error;

/* 更新状态：置为 in_progress 时若已存在另一个 in_progress 则失败 */
- (BOOL)setStatus:(LATodoStatus)status forTodoID:(NSString *)todoID error:(NSError **)error;

/* 删除 Todo */
- (BOOL)removeTodoWithID:(NSString *)todoID error:(NSError **)error;

/* 当前进行中的 Todo，无则返回 nil */
- (LATodo *)activeTodo;

/* 全部 Todo（按 sortOrder 升序） */
- (NSArray<LATodo *> *)allTodos;

/* 进度描述（如 1/3），供会话视图显示 */
- (NSString *)progressText;

/* 落库互转 */
- (NSArray<NSDictionary *> *)toJSONArray;
- (BOOL)loadFromJSONArray:(NSArray<NSDictionary *> *)array error:(NSError **)error;

@end

@protocol LATodoStoreDelegate <NSObject>
@optional
/* Todo 集合变化通知（增/改/删/载入） */
- (void)todoStoreDidChange:(LATodoStore *)store;
@end

#endif /* LA_TODO_STORE_H */
