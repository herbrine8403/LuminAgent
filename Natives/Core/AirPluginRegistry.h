#ifndef AIR_PLUGIN_REGISTRY_H
#define AIR_PLUGIN_REGISTRY_H

/* 插件注册表 C 接口：一切皆插件的可替换槽位管理。
 * 槽位覆盖 models/tools/skills/sessions/sandbox/storage/loop/scheduling/UI。
 * 注册方式为 JSON 清单（单个插件一段 JSON，或数组批量注册）；
 * 开关与替换只改配置，不改主干；启动树可 dump 成 JSON 供 UI/审计点查。
 * 本层为纯 C，无第三方依赖；ObjC 侧经 Harness/ 模块消费。 */

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 插件槽位：与 harness-plugins 规格一一对应，共 9 个。 */
typedef enum AirPluginSlot {
    AirPluginSlotModels     = 0, /* 模型供给（含 Zen/远端/本地预设） */
    AirPluginSlotTools      = 1, /* 工具集（含文件/远端 shell/网络） */
    AirPluginSlotSkills     = 2, /* Skills（含 Superpowers 离线包） */
    AirPluginSlotSessions   = 3, /* 会话存储后端 */
    AirPluginSlotSandbox    = 4, /* 沙盒执行后端（App 沙盒/XPC helper） */
    AirPluginSlotStorage    = 5, /* 通用存储后端（SQLite WAL 等） */
    AirPluginSlotLoop       = 6, /* AgentLoop 本体（可替换，非写死） */
    AirPluginSlotScheduling = 7, /* 调度策略（预算/并发/中断） */
    AirPluginSlotUI         = 8  /* UI 扩展位（卡片/轨迹点查） */
} AirPluginSlot;

/* 槽位总数，供调用方做边界检查。 */
#define AIR_PLUGIN_SLOT_COUNT 9

/* 单注册表容量上限（内存常驻，重启即失；落盘靠 profile+patch 文件）。 */
#define AIR_PLUGIN_MAX_COUNT 128

/* 插件 ID/版本/槽位名字符串长度上限（含终止符）。 */
#define AIR_PLUGIN_ID_MAX 96
#define AIR_PLUGIN_VER_MAX 32
#define AIR_PLUGIN_SLOT_NAME_MAX 24

/* 注册表初始化占位，成功返回 0（重复调用为幂等复位）。 */
int AirPluginRegistryInit(void);

/* 复位注册表（清空全部插件与槽位激活态），成功返回 0。 */
int AirPluginRegistryReset(void);

/* 注册单段 JSON 清单，形如：
 * {"id":"zen-default","slot":"models","version":"1.0","enabled":true}
 * slot 取值：models/tools/skills/sessions/sandbox/storage/loop/scheduling/ui。
 * 成功返回 0；失败返回非 0，错误摘要写入 errBuf（可空）。 */
int AirPluginRegistryRegisterJSON(const char *json, char *errBuf, size_t errLen);

/* 注册 JSON 数组清单（批量），元素格式同上；返回成功注册条数，errBuf 汇总首错。 */
int AirPluginRegistryRegisterJSONArray(const char *jsonArray, char *errBuf, size_t errLen);

/* 从文件路径加载清单（单段或数组均可），成功返回注册条数，失败返回负数。 */
int AirPluginRegistryRegisterFile(const char *path, char *errBuf, size_t errLen);

/* 开关插件（不改主干，只改配置位）；插件不存在返回非 0。 */
int AirPluginRegistrySetEnabled(const char *pluginID, int enabled);

/* 查询插件开关态：1=启用，0=禁用/不存在。 */
int AirPluginRegistryIsEnabled(const char *pluginID);

/* 指定槽位当前激活插件：同槽多插件时整行切换（非深度合并）。
 * 传空字符串或 NULL 表示清空该槽激活态；插件不存在或槽位非法返回非 0。 */
int AirPluginRegistrySetActiveForSlot(AirPluginSlot slot, const char *pluginID);

/* 查询槽位当前激活插件 ID；无激活返回 0 且 outID 置空；槽位非法返回非 0。 */
int AirPluginRegistryActiveForSlot(AirPluginSlot slot, char *outID, size_t outLen);

/* 槽位名与枚举互转：名字非法时返回 -1。 */
int AirPluginSlotFromName(const char *name);
const char *AirPluginSlotName(AirPluginSlot slot);

/* 启动树 dump：输出 profile+bundles+patch 层叠后的槽位→激活插件映射 JSON。
 * 形如 {"models":"zen-default","loop":"standard",...}（无激活槽位值为 null）。
 * 缓冲不足返回非 0；成功返回 0。 */
int AirPluginRegistryDumpBootTree(char *outBuf, size_t outLen);

/* 已注册插件数（审计用）。 */
int AirPluginRegistryCount(void);

#ifdef __cplusplus
}
#endif

#endif /* AIR_PLUGIN_REGISTRY_H */
