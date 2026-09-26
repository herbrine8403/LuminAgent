#include "AirPluginRegistry.h"

#include <stdio.h>
#include <string.h>

/* 插件注册表实现：纯 C 内存常驻表，无第三方依赖。
 * JSON 清单只做最小键抽取（id/slot/version/enabled），不引入完整 JSON 库；
 * 动态生成插件驻内存（重启消失），落盘靠 profile+patch 文件（调用方负责）。 */

/* 单条插件记录 */
typedef struct AirPluginEntry {
    char id[AIR_PLUGIN_ID_MAX];     /* 插件唯一 ID */
    AirPluginSlot slot;             /* 所属槽位 */
    char version[AIR_PLUGIN_VER_MAX]; /* 版本字符串 */
    int enabled;                    /* 开关位：1 启用，0 禁用 */
} AirPluginEntry;

/* 注册表静态存储 */
static AirPluginEntry g_plugins[AIR_PLUGIN_MAX_COUNT];
static int g_pluginCount = 0;
static char g_active[AIR_PLUGIN_SLOT_COUNT][AIR_PLUGIN_ID_MAX];
static int g_inited = 0;

/* 槽位名表（小写，与 JSON 清单取值一致） */
static const char *kSlotNames[AIR_PLUGIN_SLOT_COUNT] = {
    "models", "tools", "skills", "sessions", "sandbox",
    "storage", "loop", "scheduling", "ui"
};

int AirPluginSlotFromName(const char *name) {
    int i;
    if (!name) return -1;
    for (i = 0; i < AIR_PLUGIN_SLOT_COUNT; i++) {
        if (strcmp(name, kSlotNames[i]) == 0) return i;
    }
    return -1;
}

const char *AirPluginSlotName(AirPluginSlot slot) {
    if (slot < 0 || slot >= AIR_PLUGIN_SLOT_COUNT) return NULL;
    return kSlotNames[slot];
}

int AirPluginRegistryInit(void) {
    int i;
    g_pluginCount = 0;
    for (i = 0; i < AIR_PLUGIN_SLOT_COUNT; i++) g_active[i][0] = '\0';
    memset(g_plugins, 0, sizeof(g_plugins));
    g_inited = 1;
    return 0;
}

int AirPluginRegistryReset(void) {
    return AirPluginRegistryInit();
}

int AirPluginRegistryCount(void) {
    return g_pluginCount;
}

/* 在 JSON 文本中抽取字符串键值：找 "key" : "value"，拷贝到 out（截断保护）。 */
static int ExtractJSONStr(const char *json, const char *key, char *out, size_t outLen) {
    char pat[64];
    const char *p, *q;
    size_t n;
    if (!json || !key || !out || outLen == 0) return -1;
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    p = strstr(json, pat);
    if (!p) return -1;
    p = strchr(p + strlen(pat), ':');
    if (!p) return -1;
    p++;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    if (*p != '"') return -1;
    p++;
    q = strchr(p, '"');
    if (!q) return -1;
    n = (size_t)(q - p);
    if (n >= outLen) n = outLen - 1;
    memcpy(out, p, n);
    out[n] = '\0';
    return 0;
}

/* 抽取布尔键：找 "key" : true/false/1/0，缺省返回 def。 */
static int ExtractJSONBool(const char *json, const char *key, int def) {
    char pat[64];
    const char *p;
    if (!json || !key) return def;
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    p = strstr(json, pat);
    if (!p) return def;
    p = strchr(p + strlen(pat), ':');
    if (!p) return def;
    p++;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    if (strncmp(p, "true", 4) == 0 || *p == '1') return 1;
    if (strncmp(p, "false", 5) == 0 || *p == '0') return 0;
    return def;
}

/* 查找插件下标，不存在返回 -1。 */
static int FindPlugin(const char *pluginID) {
    int i;
    if (!pluginID) return -1;
    for (i = 0; i < g_pluginCount; i++) {
        if (strcmp(g_plugins[i].id, pluginID) == 0) return i;
    }
    return -1;
}

/* 注册/覆盖单条记录（同 ID 整行替换，非深度合并）。 */
static int UpsertEntry(const char *pid, AirPluginSlot slot, const char *ver, int enabled) {
    int idx = FindPlugin(pid);
    if (idx < 0) {
        if (g_pluginCount >= AIR_PLUGIN_MAX_COUNT) return -1;
        idx = g_pluginCount++;
    }
    strncpy(g_plugins[idx].id, pid, AIR_PLUGIN_ID_MAX - 1);
    g_plugins[idx].id[AIR_PLUGIN_ID_MAX - 1] = '\0';
    g_plugins[idx].slot = slot;
    if (ver) {
        strncpy(g_plugins[idx].version, ver, AIR_PLUGIN_VER_MAX - 1);
        g_plugins[idx].version[AIR_PLUGIN_VER_MAX - 1] = '\0';
    } else {
        g_plugins[idx].version[0] = '\0';
    }
    g_plugins[idx].enabled = enabled ? 1 : 0;
    return 0;
}

int AirPluginRegistryRegisterJSON(const char *json, char *errBuf, size_t errLen) {
    char pid[AIR_PLUGIN_ID_MAX];
    char slotName[AIR_PLUGIN_SLOT_NAME_MAX];
    char ver[AIR_PLUGIN_VER_MAX];
    int slot, enabled;
    if (!g_inited) AirPluginRegistryInit();
    if (!json) {
        if (errBuf && errLen) snprintf(errBuf, errLen, "清单为空");
        return -1;
    }
    if (ExtractJSONStr(json, "id", pid, sizeof(pid)) != 0 || pid[0] == '\0') {
        if (errBuf && errLen) snprintf(errBuf, errLen, "清单缺 id");
        return -1;
    }
    if (ExtractJSONStr(json, "slot", slotName, sizeof(slotName)) != 0) {
        if (errBuf && errLen) snprintf(errBuf, errLen, "清单缺 slot");
        return -1;
    }
    slot = AirPluginSlotFromName(slotName);
    if (slot < 0) {
        if (errBuf && errLen) snprintf(errBuf, errLen, "未知槽位");
        return -1;
    }
    if (ExtractJSONStr(json, "version", ver, sizeof(ver)) != 0) ver[0] = '\0';
    enabled = ExtractJSONBool(json, "enabled", 1);
    if (UpsertEntry(pid, (AirPluginSlot)slot, ver, enabled) != 0) {
        if (errBuf && errLen) snprintf(errBuf, errLen, "注册表已满");
        return -1;
    }
    return 0;
}

int AirPluginRegistryRegisterJSONArray(const char *jsonArray, char *errBuf, size_t errLen) {
    const char *p;
    int count = 0, firstErr = 0;
    char item[1024];
    if (!g_inited) AirPluginRegistryInit();
    if (!jsonArray) {
        if (errBuf && errLen) snprintf(errBuf, errLen, "清单为空");
        return 0;
    }
    /* 简易切分：按花括号配对抽取对象段，逐段注册。 */
    p = jsonArray;
    while (*p) {
        const char *s = strchr(p, '{');
        const char *e;
        size_t n;
        int depth = 0;
        const char *q;
        if (!s) break;
        depth = 0;
        for (q = s; *q; q++) {
            if (*q == '{') depth++;
            else if (*q == '}') {
                depth--;
                if (depth == 0) break;
            }
        }
        if (depth != 0) break;
        e = q;
        n = (size_t)(e - s + 1);
        if (n >= sizeof(item)) n = sizeof(item) - 1;
        memcpy(item, s, n);
        item[n] = '\0';
        if (AirPluginRegistryRegisterJSON(item, NULL, 0) == 0) {
            count++;
        } else if (!firstErr) {
            firstErr = 1;
            if (errBuf && errLen) snprintf(errBuf, errLen, "部分条目注册失败");
        }
        p = e + 1;
    }
    return count;
}

int AirPluginRegistryRegisterFile(const char *path, char *errBuf, size_t errLen) {
    FILE *fp;
    static char buf[8192];
    size_t n;
    if (!g_inited) AirPluginRegistryInit();
    if (!path) {
        if (errBuf && errLen) snprintf(errBuf, errLen, "路径为空");
        return -1;
    }
    fp = fopen(path, "r");
    if (!fp) {
        if (errBuf && errLen) snprintf(errBuf, errLen, "清单文件打不开");
        return -1;
    }
    n = fread(buf, 1, sizeof(buf) - 1, fp);
    fclose(fp);
    buf[n] = '\0';
    /* 数组形式走批量，单对象走单条。 */
    if (strchr(buf, '[') && strchr(buf, '{') &&
        strchr(buf, '[') < strchr(buf, '{')) {
        return AirPluginRegistryRegisterJSONArray(buf, errBuf, errLen);
    }
    return AirPluginRegistryRegisterJSON(buf, errBuf, errLen) == 0 ? 1 : -1;
}

int AirPluginRegistrySetEnabled(const char *pluginID, int enabled) {
    int idx = FindPlugin(pluginID);
    if (idx < 0) return -1;
    g_plugins[idx].enabled = enabled ? 1 : 0;
    return 0;
}

int AirPluginRegistryIsEnabled(const char *pluginID) {
    int idx = FindPlugin(pluginID);
    if (idx < 0) return 0;
    return g_plugins[idx].enabled;
}

int AirPluginRegistrySetActiveForSlot(AirPluginSlot slot, const char *pluginID) {
    int idx;
    if (slot < 0 || slot >= AIR_PLUGIN_SLOT_COUNT) return -1;
    if (!pluginID || pluginID[0] == '\0') {
        g_active[slot][0] = '\0';
        return 0;
    }
    idx = FindPlugin(pluginID);
    if (idx < 0) return -1;
    if (g_plugins[idx].slot != slot) return -1;
    strncpy(g_active[slot], pluginID, AIR_PLUGIN_ID_MAX - 1);
    g_active[slot][AIR_PLUGIN_ID_MAX - 1] = '\0';
    return 0;
}

int AirPluginRegistryActiveForSlot(AirPluginSlot slot, char *outID, size_t outLen) {
    if (slot < 0 || slot >= AIR_PLUGIN_SLOT_COUNT) return -1;
    if (outID && outLen) {
        strncpy(outID, g_active[slot], outLen - 1);
        outID[outLen - 1] = '\0';
    }
    return 0;
}

int AirPluginRegistryDumpBootTree(char *outBuf, size_t outLen) {
    int i, w = 0, n;
    if (!outBuf || outLen == 0) return -1;
    n = snprintf(outBuf + w, outLen - (size_t)w, "{");
    if (n < 0) return -1;
    w += n;
    for (i = 0; i < AIR_PLUGIN_SLOT_COUNT; i++) {
        const char *fmt = (i == 0) ? "\"%s\":" : ",\"%s\":";
        n = snprintf(outBuf + w, outLen - (size_t)w, fmt, kSlotNames[i]);
        if (n < 0 || (size_t)(w + n) >= outLen) return -1;
        w += n;
        if (g_active[i][0] != '\0') {
            n = snprintf(outBuf + w, outLen - (size_t)w, "\"%s\"", g_active[i]);
        } else {
            n = snprintf(outBuf + w, outLen - (size_t)w, "null");
        }
        if (n < 0 || (size_t)(w + n) >= outLen) return -1;
        w += n;
    }
    n = snprintf(outBuf + w, outLen - (size_t)w, "}");
    if (n < 0 || (size_t)(w + n) >= outLen) return -1;
    return 0;
}
