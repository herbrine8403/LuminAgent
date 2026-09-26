#ifndef LA_UNDO_REDO_H
#define LA_UNDO_REDO_H

/* Undo/Redo：基于快照栈回滚改动；
 * snapshotEnabled=YES 时文件回滚经 delegate 交 Tools 组 Git 快照执行，
 * =NO 或无仓库时仅回滚消息（截断到快照点）。 */

#import <Foundation/Foundation.h>

@class LAMessage;
@class LAUndoRedo;

/* 单文件变更记录 */
@interface LAFileChange : NSObject

@property (nonatomic, copy) NSString *path; /* 文件路径 */
@property (nonatomic, copy) NSString *kind; /* added/modified/deleted */

+ (instancetype)changeWithPath:(NSString *)path kind:(NSString *)kind;

- (NSDictionary *)toDictionary;
- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end

/* 快照点 */
@interface LAUndoSnapshot : NSObject

@property (nonatomic, copy) NSString *snapshotID;
@property (nonatomic, copy) NSString *label;              /* 还原点标注 */
@property (nonatomic, assign) NSTimeInterval createdAt;
@property (nonatomic, strong) NSArray<LAFileChange *> *changes; /* 文件变更集 */
@property (nonatomic, assign) NSUInteger messageCount;   /* 当时消息条数 */

@end

@interface LAUndoRedo : NSObject

/* 快照总开关（对应会话 snapshotEnabled，可配 snapshot:false 关闭） */
@property (nonatomic, assign) BOOL snapshotEnabled;
@property (nonatomic, weak) id delegate;

/* 入栈快照点 */
- (void)pushSnapshotForSessionID:(NSString *)sessionID
                         changes:(NSArray<LAFileChange *> *)changes
                    messageCount:(NSUInteger)messageCount
                           label:(NSString *)label;

- (BOOL)canUndoForSessionID:(NSString *)sessionID;
- (BOOL)canRedoForSessionID:(NSString *)sessionID;

/* /undo：弹出最近快照；文件回滚经 delegate，无 delegate 仅回滚消息。
 * restoredMessageCount 输出应截断到的消息条数，revertedChanges 输出待回滚变更。 */
- (BOOL)undoForSessionID:(NSString *)sessionID
    restoredMessageCount:(NSUInteger *)restoredMessageCount
         revertedChanges:(NSArray<LAFileChange *> **)revertedChanges
                   error:(NSError **)error;

/* /redo：重做最近一次 undo */
- (BOOL)redoForSessionID:(NSString *)sessionID
    restoredMessageCount:(NSUInteger *)restoredMessageCount
        reappliedChanges:(NSArray<LAFileChange *> **)reappliedChanges
                   error:(NSError **)error;

/* 清空会话栈（删除会话时调用） */
- (void)clearForSessionID:(NSString *)sessionID;

@end

@protocol LAUndoRedoDelegate <NSObject>
@optional
/* 文件级回滚（Git 快照实际执行，Tools 组实现）；返回 NO 则整体 undo 失败 */
- (BOOL)undoRedo:(LAUndoRedo *)undoRedo
    revertChanges:(NSArray<LAFileChange *> *)changes
     forSessionID:(NSString *)sessionID
            error:(NSError **)error;
/* 文件级重做 */
- (BOOL)undoRedo:(LAUndoRedo *)undoRedo
    reapplyChanges:(NSArray<LAFileChange *> *)changes
      forSessionID:(NSString *)sessionID
             error:(NSError **)error;
@end

#endif /* LA_UNDO_REDO_H */
