#include "AirSessionStore.h"

#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 会话存储 C 层实现：系统 sqlite3 C API 直写，无第三方依赖。 */

struct AirSessionStore {
    sqlite3 *db;
    char lastError[512];
};

/* 记录内部错误文本并同步拷贝到调用方缓冲 */
static void AirStoreSetError(AirSessionStore *store, const char *message,
                             char *errBuf, size_t errBufLen) {
    const char *msg = (message && message[0] != '\0') ? message : "unknown store error";
    if (store) {
        strncpy(store->lastError, msg, sizeof(store->lastError) - 1);
        store->lastError[sizeof(store->lastError) - 1] = '\0';
    }
    if (errBuf && errBufLen > 0) {
        strncpy(errBuf, msg, errBufLen - 1);
        errBuf[errBufLen - 1] = '\0';
    }
}

/* 无回调简单执行 */
static int AirStoreExec(AirSessionStore *store, const char *sql,
                        char *errBuf, size_t errBufLen) {
    char *sqliteErr = NULL;
    int rc = sqlite3_exec(store->db, sql, NULL, NULL, &sqliteErr);
    if (rc != SQLITE_OK) {
        AirStoreSetError(store, sqliteErr ? sqliteErr : sqlite3_errmsg(store->db),
                         errBuf, errBufLen);
        sqlite3_free(sqliteErr);
        return -1;
    }
    return 0;
}

/* 绑定文本或 NULL */
static void AirStoreBindTextOrNull(sqlite3_stmt *stmt, int index, const char *value) {
    if (value) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, index);
    }
}

AirSessionStore *AirSessionStoreOpen(const char *path) {
    return AirSessionStoreOpenWithError(path, NULL, 0);
}

AirSessionStore *AirSessionStoreOpenWithError(const char *path,
                                              char *errBuf,
                                              size_t errBufLen) {
    const char *dbPath = (path && path[0] != '\0') ? path : ":memory:";
    AirSessionStore *store = (AirSessionStore *)calloc(1, sizeof(AirSessionStore));
    if (!store) {
        if (errBuf && errBufLen > 0) {
            strncpy(errBuf, "out of memory", errBufLen - 1);
            errBuf[errBufLen - 1] = '\0';
        }
        return NULL;
    }
    int rc = sqlite3_open(dbPath, &store->db);
    if (rc != SQLITE_OK) {
        AirStoreSetError(store, store->db ? sqlite3_errmsg(store->db) : "sqlite3_open failed",
                         errBuf, errBufLen);
        if (store->db) {
            sqlite3_close(store->db);
        }
        free(store);
        return NULL;
    }
    /* 超时等待 + WAL，保证多读并发与掉电安全 */
    sqlite3_busy_timeout(store->db, 5000);
    if (AirStoreExec(store, "PRAGMA journal_mode=WAL;", NULL, 0) != 0 ||
        AirStoreExec(store, "PRAGMA foreign_keys=ON;", NULL, 0) != 0) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), errBuf, errBufLen);
        sqlite3_close(store->db);
        free(store);
        return NULL;
    }
    if (AirSessionStoreMigrate(store, errBuf, errBufLen) != 0) {
        sqlite3_close(store->db);
        free(store);
        return NULL;
    }
    return store;
}

void AirSessionStoreClose(AirSessionStore *store) {
    if (!store) {
        return;
    }
    if (store->db) {
        sqlite3_close(store->db);
        store->db = NULL;
    }
    free(store);
}

const char *AirSessionStoreLastError(AirSessionStore *store) {
    if (!store) {
        return "null store";
    }
    return store->lastError[0] ? store->lastError : "ok";
}

int AirSessionStoreMigrate(AirSessionStore *store, char *errBuf, size_t errBufLen) {
    if (!store || !store->db) {
        AirStoreSetError(store, "null store", errBuf, errBufLen);
        return -1;
    }
    static const char *kSchema =
        "CREATE TABLE IF NOT EXISTS sessions("
        " id TEXT PRIMARY KEY,"
        " parent_id TEXT,"
        " title TEXT,"
        " mode TEXT,"
        " created_at INTEGER,"
        " updated_at INTEGER);"
        "CREATE TABLE IF NOT EXISTS messages("
        " id TEXT PRIMARY KEY,"
        " session_id TEXT NOT NULL,"
        " role TEXT,"
        " created_at INTEGER,"
        " reverted INTEGER DEFAULT 0);"
        "CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, created_at);"
        "CREATE TABLE IF NOT EXISTS parts("
        " id TEXT PRIMARY KEY,"
        " message_id TEXT NOT NULL,"
        " kind TEXT,"
        " text TEXT,"
        " meta_json TEXT,"
        " tokens INTEGER DEFAULT 0,"
        " cost_micro INTEGER DEFAULT 0);"
        "CREATE INDEX IF NOT EXISTS idx_parts_message ON parts(message_id);"
        "CREATE TABLE IF NOT EXISTS todos("
        " id TEXT PRIMARY KEY,"
        " session_id TEXT NOT NULL,"
        " content TEXT,"
        " status TEXT,"
        " sort_order INTEGER DEFAULT 0);"
        "CREATE INDEX IF NOT EXISTS idx_todos_session ON todos(session_id, sort_order);"
        "CREATE TABLE IF NOT EXISTS usage("
        " session_id TEXT PRIMARY KEY,"
        " tokens_in INTEGER DEFAULT 0,"
        " tokens_out INTEGER DEFAULT 0,"
        " cost_micro INTEGER DEFAULT 0);"
        "CREATE TABLE IF NOT EXISTS events("
        " id TEXT PRIMARY KEY,"
        " session_id TEXT NOT NULL,"
        " kind TEXT,"
        " payload_json TEXT,"
        " created_at INTEGER);"
        "CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id, created_at);";
    return AirStoreExec(store, kSchema, errBuf, errBufLen);
}

int AirSessionStoreBegin(AirSessionStore *store) {
    if (!store) {
        return -1;
    }
    return AirStoreExec(store, "BEGIN IMMEDIATE;", NULL, 0);
}

int AirSessionStoreCommit(AirSessionStore *store) {
    if (!store) {
        return -1;
    }
    return AirStoreExec(store, "COMMIT;", NULL, 0);
}

int AirSessionStoreRollback(AirSessionStore *store) {
    if (!store) {
        return -1;
    }
    return AirStoreExec(store, "ROLLBACK;", NULL, 0);
}

int AirSessionStoreUpsertSession(AirSessionStore *store,
                                 const char *sessionID,
                                 const char *parentID,
                                 const char *title,
                                 const char *mode,
                                 long long createdAt,
                                 long long updatedAt) {
    if (!store || !sessionID) {
        return -1;
    }
    static const char *kSQL =
        "INSERT INTO sessions(id, parent_id, title, mode, created_at, updated_at)"
        " VALUES(?,?,?,?,?,?)"
        " ON CONFLICT(id) DO UPDATE SET"
        " parent_id=excluded.parent_id, title=excluded.title,"
        " mode=excluded.mode, updated_at=excluded.updated_at;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    AirStoreBindTextOrNull(stmt, 1, sessionID);
    AirStoreBindTextOrNull(stmt, 2, parentID);
    AirStoreBindTextOrNull(stmt, 3, title);
    AirStoreBindTextOrNull(stmt, 4, mode);
    sqlite3_bind_int64(stmt, 5, createdAt);
    sqlite3_bind_int64(stmt, 6, updatedAt);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    return 0;
}

int AirSessionStoreDeleteSession(AirSessionStore *store, const char *sessionID) {
    if (!store || !sessionID) {
        return -1;
    }
    /* 级联删除该会话的全部行（SQLite 未声明外键时手动清理） */
    static const char *kSQL[] = {
        "DELETE FROM parts WHERE message_id IN"
        " (SELECT id FROM messages WHERE session_id=?);",
        "DELETE FROM messages WHERE session_id=?;",
        "DELETE FROM todos WHERE session_id=?;",
        "DELETE FROM usage WHERE session_id=?;",
        "DELETE FROM events WHERE session_id=?;",
        "DELETE FROM sessions WHERE id=?;",
    };
    if (AirSessionStoreBegin(store) != 0) {
        return -1;
    }
    for (size_t i = 0; i < sizeof(kSQL) / sizeof(kSQL[0]); i++) {
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(store->db, kSQL[i], -1, &stmt, NULL) != SQLITE_OK) {
            AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
            AirSessionStoreRollback(store);
            return -1;
        }
        sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT);
        int rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) {
            AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
            AirSessionStoreRollback(store);
            return -1;
        }
    }
    return AirSessionStoreCommit(store);
}

int AirSessionStoreListSessions(AirSessionStore *store, AirSessionStoreRowFn cb, void *ctx) {
    if (!store) {
        return -1;
    }
    static const char *kSQL =
        "SELECT id, parent_id, title, mode FROM sessions ORDER BY created_at ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    if (cb) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            cb((const char *)sqlite3_column_text(stmt, 0),
               (const char *)sqlite3_column_text(stmt, 1),
               (const char *)sqlite3_column_text(stmt, 2),
               (const char *)sqlite3_column_text(stmt, 3), ctx);
        }
    }
    sqlite3_finalize(stmt);
    return 0;
}

int AirSessionStoreListChildren(AirSessionStore *store,
                                const char *parentID,
                                AirSessionStoreRowFn cb,
                                void *ctx) {
    if (!store) {
        return -1;
    }
    const char *kSQLWithParent =
        "SELECT id, parent_id, title, mode FROM sessions"
        " WHERE parent_id=? ORDER BY created_at ASC;";
    const char *kSQLRoots =
        "SELECT id, parent_id, title, mode FROM sessions"
        " WHERE parent_id IS NULL ORDER BY created_at ASC;";
    sqlite3_stmt *stmt = NULL;
    const char *sql = (parentID && parentID[0] != '\0') ? kSQLWithParent : kSQLRoots;
    if (sqlite3_prepare_v2(store->db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    if (parentID && parentID[0] != '\0') {
        sqlite3_bind_text(stmt, 1, parentID, -1, SQLITE_TRANSIENT);
    }
    if (cb) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            cb((const char *)sqlite3_column_text(stmt, 0),
               (const char *)sqlite3_column_text(stmt, 1),
               (const char *)sqlite3_column_text(stmt, 2),
               (const char *)sqlite3_column_text(stmt, 3), ctx);
        }
    }
    sqlite3_finalize(stmt);
    return 0;
}

int AirSessionStoreGetSessionParent(AirSessionStore *store,
                                    const char *sessionID,
                                    char *outBuf,
                                    size_t outLen) {
    if (!store || !sessionID || !outBuf || outLen == 0) {
        return -1;
    }
    static const char *kSQL = "SELECT parent_id FROM sessions WHERE id=?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return -2;
    }
    const char *parent = (const char *)sqlite3_column_text(stmt, 0);
    strncpy(outBuf, parent ? parent : "", outLen - 1);
    outBuf[outLen - 1] = '\0';
    sqlite3_finalize(stmt);
    return 0;
}

int AirSessionStoreInsertMessage(AirSessionStore *store,
                                 const char *messageID,
                                 const char *sessionID,
                                 const char *role,
                                 long long createdAt) {
    if (!store || !messageID || !sessionID) {
        return -1;
    }
    static const char *kSQL =
        "INSERT OR REPLACE INTO messages(id, session_id, role, created_at, reverted)"
        " VALUES(?,?,?,?,0);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, messageID, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, sessionID, -1, SQLITE_TRANSIENT);
    AirStoreBindTextOrNull(stmt, 3, role);
    sqlite3_bind_int64(stmt, 4, createdAt);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    return 0;
}

int AirSessionStoreListMessages(AirSessionStore *store,
                                const char *sessionID,
                                AirSessionStoreRowFn cb,
                                void *ctx) {
    if (!store || !sessionID) {
        return -1;
    }
    static const char *kSQL =
        "SELECT id, role, created_at, reverted FROM messages"
        " WHERE session_id=? ORDER BY created_at ASC, rowid ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT);
    if (cb) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            char createdBuf[32];
            char revertedBuf[8];
            snprintf(createdBuf, sizeof(createdBuf), "%lld",
                     sqlite3_column_int64(stmt, 2));
            snprintf(revertedBuf, sizeof(revertedBuf), "%d",
                     sqlite3_column_int(stmt, 3));
            cb((const char *)sqlite3_column_text(stmt, 0),
               (const char *)sqlite3_column_text(stmt, 1),
               createdBuf, revertedBuf, ctx);
        }
    } else {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
        }
    }
    sqlite3_finalize(stmt);
    return 0;
}

int AirSessionStoreDeleteMessagesAfter(AirSessionStore *store,
                                       const char *sessionID,
                                       long long createdAtExclusive) {
    if (!store || !sessionID) {
        return -1;
    }
    if (AirSessionStoreBegin(store) != 0) {
        return -1;
    }
    static const char *kDeleteParts =
        "DELETE FROM parts WHERE message_id IN"
        " (SELECT id FROM messages WHERE session_id=? AND created_at>?);";
    static const char *kDeleteMessages =
        "DELETE FROM messages WHERE session_id=? AND created_at>?;";
    const char *steps[] = { kDeleteParts, kDeleteMessages };
    for (size_t i = 0; i < 2; i++) {
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(store->db, steps[i], -1, &stmt, NULL) != SQLITE_OK) {
            AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
            AirSessionStoreRollback(store);
            return -1;
        }
        sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, createdAtExclusive);
        int rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) {
            AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
            AirSessionStoreRollback(store);
            return -1;
        }
    }
    return AirSessionStoreCommit(store);
}

int AirSessionStoreMarkMessageReverted(AirSessionStore *store,
                                       const char *messageID,
                                       int reverted) {
    if (!store || !messageID) {
        return -1;
    }
    static const char *kSQL = "UPDATE messages SET reverted=? WHERE id=?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_int(stmt, 1, reverted ? 1 : 0);
    sqlite3_bind_text(stmt, 2, messageID, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    return 0;
}

int AirSessionStoreInsertPart(AirSessionStore *store,
                              const char *partID,
                              const char *messageID,
                              const char *kind,
                              const char *text,
                              const char *metaJSON,
                              long long tokens,
                              long long costMicro) {
    if (!store || !partID || !messageID) {
        return -1;
    }
    static const char *kSQL =
        "INSERT OR REPLACE INTO parts(id, message_id, kind, text, meta_json, tokens, cost_micro)"
        " VALUES(?,?,?,?,?,?,?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, partID, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, messageID, -1, SQLITE_TRANSIENT);
    AirStoreBindTextOrNull(stmt, 3, kind);
    AirStoreBindTextOrNull(stmt, 4, text);
    AirStoreBindTextOrNull(stmt, 5, metaJSON);
    sqlite3_bind_int64(stmt, 6, tokens);
    sqlite3_bind_int64(stmt, 7, costMicro);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    return 0;
}

int AirSessionStoreListParts(AirSessionStore *store,
                             const char *messageID,
                             AirSessionStorePartFn cb,
                             void *ctx) {
    if (!store || !messageID) {
        return -1;
    }
    static const char *kSQL =
        "SELECT id, kind, text, meta_json, tokens, cost_micro FROM parts"
        " WHERE message_id=? ORDER BY rowid ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, messageID, -1, SQLITE_TRANSIENT);
    if (cb) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            cb((const char *)sqlite3_column_text(stmt, 0),
               (const char *)sqlite3_column_text(stmt, 1),
               (const char *)sqlite3_column_text(stmt, 2),
               (const char *)sqlite3_column_text(stmt, 3),
               sqlite3_column_int64(stmt, 4),
               sqlite3_column_int64(stmt, 5), ctx);
        }
    } else {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
        }
    }
    sqlite3_finalize(stmt);
    return 0;
}

int AirSessionStoreDeletePartsOfMessage(AirSessionStore *store, const char *messageID) {
    if (!store || !messageID) {
        return -1;
    }
    static const char *kSQL = "DELETE FROM parts WHERE message_id=?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, messageID, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    return 0;
}

int AirSessionStoreUpsertTodo(AirSessionStore *store,
                              const char *todoID,
                              const char *sessionID,
                              const char *content,
                              const char *status,
                              long long sortOrder) {
    if (!store || !todoID || !sessionID) {
        return -1;
    }
    static const char *kSQL =
        "INSERT INTO todos(id, session_id, content, status, sort_order)"
        " VALUES(?,?,?,?,?)"
        " ON CONFLICT(id) DO UPDATE SET"
        " content=excluded.content, status=excluded.status,"
        " sort_order=excluded.sort_order;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, todoID, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, sessionID, -1, SQLITE_TRANSIENT);
    AirStoreBindTextOrNull(stmt, 3, content);
    AirStoreBindTextOrNull(stmt, 4, status);
    sqlite3_bind_int64(stmt, 5, sortOrder);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    return 0;
}

int AirSessionStoreDeleteTodosOfSession(AirSessionStore *store, const char *sessionID) {
    if (!store || !sessionID) {
        return -1;
    }
    static const char *kSQL = "DELETE FROM todos WHERE session_id=?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    return 0;
}

int AirSessionStoreListTodos(AirSessionStore *store,
                             const char *sessionID,
                             AirSessionStoreRowFn cb,
                             void *ctx) {
    if (!store || !sessionID) {
        return -1;
    }
    static const char *kSQL =
        "SELECT id, content, status, sort_order FROM todos"
        " WHERE session_id=? ORDER BY sort_order ASC, rowid ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT);
    if (cb) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            char orderBuf[32];
            snprintf(orderBuf, sizeof(orderBuf), "%lld", sqlite3_column_int64(stmt, 3));
            cb((const char *)sqlite3_column_text(stmt, 0),
               (const char *)sqlite3_column_text(stmt, 1),
               (const char *)sqlite3_column_text(stmt, 2),
               orderBuf, ctx);
        }
    } else {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
        }
    }
    sqlite3_finalize(stmt);
    return 0;
}

int AirSessionStoreAddUsage(AirSessionStore *store,
                            const char *sessionID,
                            long long tokensIn,
                            long long tokensOut,
                            long long costMicro) {
    if (!store || !sessionID) {
        return -1;
    }
    static const char *kSQL =
        "INSERT INTO usage(session_id, tokens_in, tokens_out, cost_micro)"
        " VALUES(?,?,?,?)"
        " ON CONFLICT(session_id) DO UPDATE SET"
        " tokens_in=tokens_in+excluded.tokens_in,"
        " tokens_out=tokens_out+excluded.tokens_out,"
        " cost_micro=cost_micro+excluded.cost_micro;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 2, tokensIn);
    sqlite3_bind_int64(stmt, 3, tokensOut);
    sqlite3_bind_int64(stmt, 4, costMicro);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    return 0;
}

int AirSessionStoreGetUsage(AirSessionStore *store,
                            const char *sessionID,
                            long long *tokensIn,
                            long long *tokensOut,
                            long long *costMicro) {
    if (!store || !sessionID) {
        return -1;
    }
    static const char *kSQL =
        "SELECT tokens_in, tokens_out, cost_micro FROM usage WHERE session_id=?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT);
    long long inValue = 0, outValue = 0, costValue = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        inValue = sqlite3_column_int64(stmt, 0);
        outValue = sqlite3_column_int64(stmt, 1);
        costValue = sqlite3_column_int64(stmt, 2);
    }
    sqlite3_finalize(stmt);
    if (tokensIn) {
        *tokensIn = inValue;
    }
    if (tokensOut) {
        *tokensOut = outValue;
    }
    if (costMicro) {
        *costMicro = costValue;
    }
    return 0;
}

int AirSessionStoreAppendEvent(AirSessionStore *store,
                               const char *eventID,
                               const char *sessionID,
                               const char *kind,
                               const char *payloadJSON,
                               long long createdAt) {
    if (!store || !eventID || !sessionID) {
        return -1;
    }
    static const char *kSQL =
        "INSERT OR IGNORE INTO events(id, session_id, kind, payload_json, created_at)"
        " VALUES(?,?,?,?,?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, eventID, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, sessionID, -1, SQLITE_TRANSIENT);
    AirStoreBindTextOrNull(stmt, 3, kind);
    AirStoreBindTextOrNull(stmt, 4, payloadJSON);
    sqlite3_bind_int64(stmt, 5, createdAt);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    return 0;
}

int AirSessionStoreListEvents(AirSessionStore *store,
                              const char *sessionID,
                              AirSessionStoreRowFn cb,
                              void *ctx) {
    if (!store || !sessionID) {
        return -1;
    }
    static const char *kSQL =
        "SELECT id, kind, payload_json, created_at FROM events"
        " WHERE session_id=? ORDER BY created_at ASC, rowid ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(store->db, kSQL, -1, &stmt, NULL) != SQLITE_OK) {
        AirStoreSetError(store, sqlite3_errmsg(store->db), NULL, 0);
        return -1;
    }
    sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT);
    if (cb) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            char createdBuf[32];
            snprintf(createdBuf, sizeof(createdBuf), "%lld",
                     sqlite3_column_int64(stmt, 3));
            cb((const char *)sqlite3_column_text(stmt, 0),
               (const char *)sqlite3_column_text(stmt, 1),
               (const char *)sqlite3_column_text(stmt, 2),
               createdBuf, ctx);
        }
    } else {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
        }
    }
    sqlite3_finalize(stmt);
    return 0;
}
