#ifndef AIR_SESSION_STORE_H
#define AIR_SESSION_STORE_H

/* 会话存储 C 层：SQLite WAL 五表
 *（sessions/messages/parts/todos/usage/events）。
 * 仅依赖系统 libsqlite3，无第三方库。
 * 回调中的字符串为借用指针（可能为 NULL），如需长期持有请自行拷贝。 */

#include <stddef.h>

typedef struct AirSessionStore AirSessionStore;

/* 行回调：c0-c3 含义见各 List 接口注释。 */
typedef void (*AirSessionStoreRowFn)(const char *c0,
                                     const char *c1,
                                     const char *c2,
                                     const char *c3,
                                     void *ctx);

/* part 行回调（含数值列）：id/kind/text/meta/tokens/costMicro。 */
typedef void (*AirSessionStorePartFn)(const char *partID,
                                      const char *kind,
                                      const char *text,
                                      const char *metaJSON,
                                      long long tokens,
                                      long long costMicro,
                                      void *ctx);

/* 打开（或创建）指定路径的存储；path 为 NULL 或空时使用内存库。
 * 兼容旧签名：失败返回 NULL。 */
AirSessionStore *AirSessionStoreOpen(const char *path);

/* 打开并经 errBuf 回传错误文本（errBuf 可为 NULL）。失败返回 NULL。 */
AirSessionStore *AirSessionStoreOpenWithError(const char *path,
                                              char *errBuf,
                                              size_t errBufLen);

/* 关闭存储并释放资源。 */
void AirSessionStoreClose(AirSessionStore *store);

/* 取最近一次错误文本（内部缓冲，线程不安全，使用后即时拷贝）。 */
const char *AirSessionStoreLastError(AirSessionStore *store);

/* 建表迁移（幂等）：五表 + 索引 + WAL。成功返回 0。 */
int AirSessionStoreMigrate(AirSessionStore *store, char *errBuf, size_t errBufLen);

/* 事务：成功返回 0。 */
int AirSessionStoreBegin(AirSessionStore *store);
int AirSessionStoreCommit(AirSessionStore *store);
int AirSessionStoreRollback(AirSessionStore *store);

/* 会话：parentID 可为 NULL（根会话）；时间戳为秒。成功返回 0。 */
int AirSessionStoreUpsertSession(AirSessionStore *store,
                                 const char *sessionID,
                                 const char *parentID,
                                 const char *title,
                                 const char *mode,
                                 long long createdAt,
                                 long long updatedAt);
int AirSessionStoreDeleteSession(AirSessionStore *store, const char *sessionID);

/* 列出全部会话：c0=id c1=parentID c2=title c3=mode。 */
int AirSessionStoreListSessions(AirSessionStore *store, AirSessionStoreRowFn cb, void *ctx);

/* 列出子会话：parentID 为 NULL 时列出根会话。列含义同上。 */
int AirSessionStoreListChildren(AirSessionStore *store,
                                const char *parentID,
                                AirSessionStoreRowFn cb,
                                void *ctx);

/* 取会话父标识：写入 outBuf（空字符串表示根会话）；会话不存在返回 -2。 */
int AirSessionStoreGetSessionParent(AirSessionStore *store,
                                    const char *sessionID,
                                    char *outBuf,
                                    size_t outLen);

/* 消息：成功返回 0。 */
int AirSessionStoreInsertMessage(AirSessionStore *store,
                                 const char *messageID,
                                 const char *sessionID,
                                 const char *role,
                                 long long createdAt);

/* 列出会话消息（按 createdAt 升序）：c0=id c1=role c2=createdAt c3=reverted。 */
int AirSessionStoreListMessages(AirSessionStore *store,
                                const char *sessionID,
                                AirSessionStoreRowFn cb,
                                void *ctx);

/* 删除某时间戳之后的消息（含其 parts，供 revert 截断用）。成功返回 0。 */
int AirSessionStoreDeleteMessagesAfter(AirSessionStore *store,
                                       const char *sessionID,
                                       long long createdAtExclusive);

/* 标记消息 revert 状态：reverted 非 0 为已回滚。成功返回 0。 */
int AirSessionStoreMarkMessageReverted(AirSessionStore *store,
                                       const char *messageID,
                                       int reverted);

/* part：metaJSON 可为 NULL；tokens/costMicro 免费记 0。成功返回 0。 */
int AirSessionStoreInsertPart(AirSessionStore *store,
                              const char *partID,
                              const char *messageID,
                              const char *kind,
                              const char *text,
                              const char *metaJSON,
                              long long tokens,
                              long long costMicro);

/* 列出消息的 parts（按 rowid 升序）。 */
int AirSessionStoreListParts(AirSessionStore *store,
                             const char *messageID,
                             AirSessionStorePartFn cb,
                             void *ctx);

/* 删除单条消息的全部 parts。成功返回 0。 */
int AirSessionStoreDeletePartsOfMessage(AirSessionStore *store, const char *messageID);

/* Todo：成功返回 0。 */
int AirSessionStoreUpsertTodo(AirSessionStore *store,
                              const char *todoID,
                              const char *sessionID,
                              const char *content,
                              const char *status,
                              long long sortOrder);

/* 清空会话 Todo（导入覆盖前用）。成功返回 0。 */
int AirSessionStoreDeleteTodosOfSession(AirSessionStore *store, const char *sessionID);

/* 列出会话 Todo（按 sortOrder 升序）：c0=id c1=content c2=status c3=sortOrder。 */
int AirSessionStoreListTodos(AirSessionStore *store,
                             const char *sessionID,
                             AirSessionStoreRowFn cb,
                             void *ctx);

/* 用量：累计叠加（免费记 0）。成功返回 0。 */
int AirSessionStoreAddUsage(AirSessionStore *store,
                            const char *sessionID,
                            long long tokensIn,
                            long long tokensOut,
                            long long costMicro);

/* 读取用量：会话无记录时三值均为 0，返回 0。 */
int AirSessionStoreGetUsage(AirSessionStore *store,
                            const char *sessionID,
                            long long *tokensIn,
                            long long *tokensOut,
                            long long *costMicro);

/* 事件（trajectory append-only 日志）：成功返回 0。 */
int AirSessionStoreAppendEvent(AirSessionStore *store,
                               const char *eventID,
                               const char *sessionID,
                               const char *kind,
                               const char *payloadJSON,
                               long long createdAt);

/* 列出会话事件（按 createdAt 升序）：c0=id c1=kind c2=payload c3=createdAt。 */
int AirSessionStoreListEvents(AirSessionStore *store,
                              const char *sessionID,
                              AirSessionStoreRowFn cb,
                              void *ctx);

#endif /* AIR_SESSION_STORE_H */
