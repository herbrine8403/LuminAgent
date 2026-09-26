# LuminAgent 1.0 Release 说明

Bundle：`com.luminagent.ios`（三套 entitlements 与 development.yml 一致，最低 iOS 15.0）。

## 产物一览（artifacts/）

| 产物 | 说明 |
|------|------|
| `com.luminagent.ios-1.0-ios.ipa` | 标准侧载包：经 sideload entitlements 签名，AltStore / SideStore 安装 |
| `com.luminagent.ios-1.0-ios-trollstore.tipa` | TrollStore 包：`TROLLSTORE_JIT_ENT=1` 构建，trollstore entitlements（含 `no-sandbox` / JIT），经 TrollStore 安装 |
| `LuminAgent.dSYM` | 调试符号：arm64，崩溃符号化用，不随包分发 |
| `com.luminagent.ios.slimmed-*.ipa/tipa` | 精简包（`SLIMMED=1`）：排除 `model_runtimes/`，需用户自备模型运行时 |

## AltStore 安装步骤

1. iPhone 与电脑同 Wi-Fi，电脑安装 AltServer 并登录同一 Apple ID；
2. 手机安装 AltStore（经 AltServer 侧载）；
3. 将 `.ipa` 传到手机，用 AltStore 打开并安装；
4. 首次启动若提示开发者信任：设置 → 通用 → VPN 与设备管理 → 信任。

## TrollStore 安装步骤

1. 确认设备系统版本在 TrollStore 支持范围；
2. 将 `.tipa` 传到手机，用 TrollStore 直接安装；
3. tipa 包自带 JIT 权限，无需额外配置。

## 版本字段（Natives/Info.plist）

- `CFBundleIdentifier` = `com.luminagent.ios`
- `CFBundleShortVersionString` = `1.0`，`CFBundleVersion` = `1`
- `MinimumOSVersion` = `15.0`，`UIDeviceFamily` = 1+2（iPhone/iPad）
- 横竖屏全支持（iPad 含上下倒置），`arm64` 必备能力

## 本版内容

- 会话/构建/规划双模式，轨迹审计事件流，权限确认卡；
- Bento 会话列表 + 聊天 + 轨迹 + 设置全套中文界面；
- 未编译验证声明：Windows 无 Xcode，仅文件清单 + 自检 + grep 复核，CI（development.yml，macOS 14 / Xcode 15.4）为准。
