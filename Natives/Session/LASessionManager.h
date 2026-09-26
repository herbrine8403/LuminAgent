#ifndef LA_SESSION_MANAGER_H
#define LA_SESSION_MANAGER_H

/* 会话管理器：创建/恢复/删除/fork/children 导航/abort/diff/export/import，
 * revert/unrevert 消息回滚；运行事件经 delegate 与存储 events 表双写。 */

#import <Foundation/Foundation.h>
#import "LASession.h"

@class LASessionManager;
@class LASessionStore;
@class LAMessage;
@class LATodo;
@class LAUndoRedo;

@protocol LASessionManagerDelegate;

@interface LASessionManager : NSObject

@property (nonatomic, strong, readonly) LASessionStore *store;
@property (nonatomic, strong, readonly) LAUndoRedo *undoRedo;
@property (nonatomic, weak) id<LASessionManagerDelegate> delegate;

/* 以存储构造；store 为 nil 时使用内存库 */
- (instancetype)initWithStore:(LASessionStore *)store;

/* 创建会话（首条用户消息可选传入，一并落库） */
- (LASession *)createSessionWithTitle:(NSString *)title
                             parentID:(NSString *)parentID
                                 mode:(LAAgentMainMode)mode
                         firstMessage:(NSString *)firstMessage
                                error:(NSError **)error;

/* 恢复会话（含消息，由调用方决定是否重建 Todo/用量） */
- (LASession *)restoreSessionWithID:(NSString *)sessionID
                              error:(NSError **)error;
- (NSArray<LAMessage *> *)messagesForSessionID:(NSString *)sessionID
                                         error:(NSError **)error;

/* 删除会话（含级联清理与 undo 栈） */
- (BOOL)deleteSessionWithID:(NSString *)sessionID error:(NSError **)error;

/* 从某条消息 fork 分叉：新会话 parentID=源会话，继承此前上下文 */
- (LASession *)forkSessionWithID:(NSString *)sessionID
                   fromMessageID:(NSString *)messageID
                        newTitle:(NSString *)newTitle
                           error:(NSError **)error;

/* children 导航：子会话列表 / 根会话列表 */
- (NSArray<LASession *> *)childrenOfSessionID:(NSString *)sessionID
                                        error:(NSError **)error;
- (NSArray<LASession *> *)rootSessionsWithError:(NSError **)error;

/* 追加消息（含用量累计：tokensIn/Out 按消息汇总，免费记 0） */
- (BOOL)appendMessage:(LAMessage *)message
            tokensIn:(long long)tokensIn
           tokensOut:(long long)tokensOut
           costMicro:(long long)costMicro
               error:(NSError **)error;

/* abort 中断运行中循环；isAborted 查询；clearAbort 开新一轮前清除 */
- (void)abortSessionWithID:(NSString *)sessionID;
- (BOOL)isAbortedSessionWithID:(NSString *)sessionID;
- (void)clearAbortForSessionID:(NSString *)sessionID;

/* revert/unrevert：截断到目标消息并标记；unrevert 恢复截断前的 stash */
- (BOOL)revertSessionID:(NSString *)sessionID
          toMessageID:(NSString *)messageID
                error:(NSError **)error;
- (BOOL)unrevertSessionID:(NSString *)sessionID error:(NSError **)error;

/* diff：本会话 patch parts 汇总的变更集文本 */
- (NSString *)diffForSessionID:(NSString *)sessionID error:(NSError **)error;

/* export/import：纯 JSON（仅会话/消息/Todo，不含密钥）；冲突 ID 重映射 */
- (NSData *)exportSessionWithID:(NSString *)sessionID error:(NSError **)error;
- (LASession *)importSessionFromData:(NSData *)data error:(NSError **)error;

@end

@protocol LASessionManagerDelegate <NSObject>
@optional
/* 运行事件：创建/恢复/删除/分叉/中断/回滚/取消/干预等 */
- (void)sessionManager:(LASessionManager *)manager
     didAppendEventOfKind:(NSString *)kind
                 payload:(NSDictionary *)payload
               sessionID:(NSString *)sessionID;
@end

/* 事件 kind 常量 */
extern NSString * const LASessionEventCreated;
extern NSString * const LASessionEventRestored;
extern NSString * const LASessionEventDeleted;
extern NSString * const LASessionEventForked;
extern NSString * const LASessionEventAborted;
extern NSString * const LASessionEventReverted;
extern NSString * const LASessionEventUnreverted;
extern NSString * const LASessionEventCancelled;
extern NSString * const LASessionEventDoomLoop;

#endif /* LA_SESSION_MANAGER_H */
