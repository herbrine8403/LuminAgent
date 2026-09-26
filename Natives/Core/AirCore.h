#ifndef AIR_CORE_H
#define AIR_CORE_H

/* Core 桥接层总头文件：Session 存储 / 权限 / 插件注册表的 C 接口。*/

#include "AirSessionStore.h"
#include "AirPluginRegistry.h"

/* 返回 Core 版本字符串（静态常量，无需释放）。 */
const char *AirCoreVersion(void);

#endif /* AIR_CORE_H */
