#ifndef LA_SESSION_STORE_H
#define LA_SESSION_STORE_H

/* 会话存储 ObjC 封装：经 Core C 层（AirSessionStore，系统 sqlite3）
 * 落库 sessions/messages/parts/todos/usage/events 五表。
 * path 为 nil 时使用内存库（单测/无盘场景）。 */

#import <Foundation/Foundation.h>

@class LASession;
@class LAMessage;
@class LATodo;

@interface LASessionStore : NSObject

/* 数据库文件路径（:memory: 表示内存库） */
@property (nonatomic, copy, readonly) NSString *databasePath;

/* 打开存储：path 为 nil 则用内存库；失败经 error 回传 */
- (instancetype)initWithPath:(NSString *)dbPath error:(NSError **)error;

/* 关闭（dealloc 自动关闭，显式关闭后对象不可再用） */
- (void)close;

/* 会话 CRUD */
- (BOOL)saveSession:(LASession *)session error:(NSError **)error;
- (LASession *)loadSessionWithID:(NSString *)sessionID error:(NSError **)error;
- (BOOL)deleteSessionWithID:(NSString *)sessionID error:(NSError **)error;
- (NSArray<LASession *> *)loadAllSessionsWithError:(NSError **)error;
- (NSArray<LASession *> *)loadChildrenOfParentID:(NSString *)parentID
                                           error:(NSError **)error;

/* 消息：整体追加（含 parts，单事务）；整体读取（含 parts） */
- (BOOL)appendMessage:(LAMessage *)message error:(NSError **)error;
- (NSArray<LAMessage *> *)loadMessagesForSessionID:(NSString *)sessionID
                                             error:(NSError **)error;
/* 回滚截断：删除该会话中 createdAt 之后的消息（含 parts） */
- (BOOL)truncateMessagesOfSessionID:(NSString *)sessionID
                       afterMessage:(LAMessage *)message
                              error:(NSError **)error;
- (BOOL)markMessageWithID:(NSString *)messageID
                  reverted:(BOOL)reverted
                     error:(NSError **)error;

/* Todo：整体覆盖保存 / 读取 */
- (BOOL)saveTodos:(NSArray<LATodo *> *)todos
     forSessionID:(NSString *)sessionID
            error:(NSError **)error;
- (NSArray<LATodo *> *)loadTodosForSessionID:(NSString *)sessionID
                                       error:(NSError **)error;

/* 用量：累计叠加 / 读取（免费记 0） */
- (BOOL)addUsageTokensIn:(long long)tokensIn
               tokensOut:(long long)tokensOut
               costMicro:(long long)costMicro
            forSessionID:(NSString *)sessionID
                   error:(NSError **)error;
- (NSDictionary *)loadUsageForSessionID:(NSString *)sessionID
                                 error:(NSError **)error;

/* 事件：trajectory append-only 日志 */
- (BOOL)appendEventOfKind:(NSString *)kind
                 payload:(NSDictionary *)payload
            forSessionID:(NSString *)sessionID
                   error:(NSError **)error;
- (NSArray<NSDictionary *> *)loadEventsForSessionID:(NSString *)sessionID
                                              error:(NSError **)error;

@end

#endif /* LA_SESSION_STORE_H */
