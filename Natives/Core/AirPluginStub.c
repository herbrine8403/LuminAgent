/* SHARED 插件占位源：保证多 SHARED target 有编译单元。
 * Harness 插件化落地后，真实实现在 AirPluginRegistry（含 9 槽位/JSON 清单/
 * 开关替换/启动树 dump）与 Harness/ 四模式/轨迹/编排/沙盒/Creator 模块；
 * 本文件仅保留无依赖占位符号，避免各 SHARED 目标空编译单元告警。 */

/* 占位符号：链接探针用，无副作用。 */
void AirPluginStubPlaceholder(void) {
}
