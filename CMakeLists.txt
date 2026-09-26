# LuminAgent Core 原生层（CMake）
# 对标 Amethyst：单 executable + 多 SHARED dylib 结构。
# macOS 上由 Makefile 以交叉参数配置：
#   -DCMAKE_SYSTEM_NAME=Darwin
#   -DCMAKE_OSX_SYSROOT=$(xcrun --sdk iphoneos --show-sdk-path)
#   -DCMAKE_OSX_ARCHITECTURES=arm64
#   -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
cmake_minimum_required(VERSION 3.16)

project(LuminAgent VERSION 1.0 LANGUAGES C OBJC)

# 部署目标与架构默认值（Makefile 交叉参数优先，本地兜底）
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0")
endif()
if(NOT CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES "arm64")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_OBJC_STANDARD 11)

# 全仓 ARC：全部 .m 按 ARC 编写（weak delegate、__bridge_transfer），禁止 MRC
add_compile_options($<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>)

# config.h.in -> config.h（版本/分支/commit 经 -D 注入，避免 Make 展开破坏密钥）
set(CONFIG_BRANCH "unknown" CACHE STRING "构建分支名")
set(CONFIG_COMMIT "unknown" CACHE STRING "构建提交号")
set(CONFIG_RELEASE 0 CACHE STRING "是否为 Release 构建")
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/config.h.in"
  "${CMAKE_CURRENT_BINARY_DIR}/config.h"
  @ONLY
)

# Core 静态库：产物 libAirCore.a（Session/存储/插件注册表桥接的 C 层）
add_library(AirCore STATIC
  Natives/Core/AirCore.c
  Natives/Core/AirSessionStore.c
  Natives/Core/AirPluginRegistry.c
)
target_include_directories(AirCore PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/Core"
  "${CMAKE_CURRENT_BINARY_DIR}"
)
target_compile_options(AirCore PRIVATE -Wall -Wextra -miphoneos-version-min=15.0)
set_target_properties(AirCore PROPERTIES
  OUTPUT_NAME "AirCore"
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

# 可选 SHARED 插件位（多 SHARED 结构，后续 Phase B/C 填充实现）
add_library(AirProviderGateway SHARED Natives/Core/AirPluginStub.c)
add_library(AirToolRuntime SHARED Natives/Core/AirPluginStub.c)
set_target_properties(AirProviderGateway AirToolRuntime PROPERTIES
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "@executable_path/Frameworks"
  BUILD_WITH_INSTALL_NAME_DIR TRUE
  INSTALL_NAME_DIR "@rpath"
)

# 主可执行文件：单 executable（入口 Natives/main.m，经 AppDelegate/SceneDelegate/EngineLauncher 启动）
# 收敛 A：Natives 各组全部 .m 显式列入（Session/Provider/Tools/Skills/MCP/Harness/DesignSystem/UI），
# 与目录 glob 复核一致；跨组头引用经下方 include 目录解析。
add_executable(LuminAgent
  Natives/main.m
  Natives/AppDelegate.m
  Natives/SceneDelegate.m
  Natives/EngineLauncher.m
  # Session 组
  Natives/Session/LAAgent.m
  Natives/Session/LACompaction.m
  Natives/Session/LAErrors.m
  Natives/Session/LAMessage.m
  Natives/Session/LAMessagePart.m
  Natives/Session/LAPermissionCenter.m
  Natives/Session/LAQuestionSheet.m
  Natives/Session/LASession.m
  Natives/Session/LASessionManager.m
  Natives/Session/LASessionProvider.m
  Natives/Session/LASessionStore.m
  Natives/Session/LATodoStore.m
  Natives/Session/LAUndoRedo.m
  # Provider 组
  Natives/Provider/LAKeychainStore.m
  Natives/Provider/LAModelPicker.m
  Natives/Provider/LAModelPolicy.m
  Natives/Provider/LAProviderGateway.m
  Natives/Provider/LAZenCatalog.m
  # Tools 组
  Natives/Tools/LALSPDiagnoser.m
  Natives/Tools/LARemoteShellGateway.m
  Natives/Tools/LASandboxFileTools.m
  Natives/Tools/LAWebTools.m
  # Skills 组
  Natives/Skills/LACommandParser.m
  Natives/Skills/LAInputParser.m
  Natives/Skills/LASkillLoader.m
  Natives/Skills/LASlashCommands.m
  # MCP 组
  Natives/MCP/LAMCPManager.m
  Natives/MCP/LAMCPOAuth.m
  Natives/MCP/LAMultiSession.m
  Natives/MCP/LAUsageStats.m
  # Harness 组
  Natives/Harness/LAAgentLoop.m
  Natives/Harness/LACreator.m
  Natives/Harness/LASandboxPolicy.m
  Natives/Harness/LASubagentBroker.m
  Natives/Harness/LATrajectoryStore.m
  # DesignSystem 组
  Natives/DesignSystem/AirAnimation.m
  Natives/DesignSystem/AirOutline.m
  Natives/DesignSystem/AirSurface.m
  Natives/DesignSystem/EmptyStateView.m
  Natives/DesignSystem/FilterChipPanel.m
  Natives/DesignSystem/ShimmerView.m
  # UI 组
  Natives/UI/LAChatVC.m
  Natives/UI/LASessionListVC.m
  Natives/UI/LASettingsVC.m
  Natives/UI/LATrajectoryVC.m
  Natives/UI/VMTileBaseCell.m
)
target_include_directories(LuminAgent PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/Core"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/Session"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/Provider"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/Tools"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/Skills"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/MCP"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/Harness"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/DesignSystem"
  "${CMAKE_CURRENT_SOURCE_DIR}/Natives/UI"
  "${CMAKE_CURRENT_BINARY_DIR}"
)
# 链接 Core 静态库与 iOS 系统库
target_link_libraries(LuminAgent PRIVATE
  AirCore
  "-framework UIKit"
  "-framework Foundation"
  "-framework Security"
  "-framework Network"
  "sqlite3"
)
# rpath 指向 @executable_path/Frameworks，Info.plist 绑定到产物
set_target_properties(LuminAgent PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "@executable_path/Frameworks"
  MACOSX_BUNDLE TRUE
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Natives/Info.plist"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
)
