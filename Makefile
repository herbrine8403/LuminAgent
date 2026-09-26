SHELL := /bin/bash
.SHELLFLAGS = -ec
# 使用 `make VERBOSE=1` 打印原始命令。
$(VERBOSE).SILENT:

# 前置变量
SOURCEDIR   := $(shell printf "%q\n" "$(shell pwd)")
OUTPUTDIR   := $(SOURCEDIR)/artifacts
WORKINGDIR  := $(SOURCEDIR)/Natives/build
DETECTPLAT  := $(shell uname -s)
DETECTARCH  := $(shell uname -m)
VERSION     := 1.0
BRANCH      := $(shell git branch --show-current)
COMMIT      := $(shell git log --oneline | sed '2,10000000d' | cut -b 1-7)
PLATFORM    ?= 2

# Release 与 Debug 切换
RELEASE ?= 0

# 是否运行在 GitHub runner 上
RUNNER ?= 0

# 是否构建精简包（排除模型运行时）
SLIMMED ?= 0

# 是否只构建精简包（跳过正常包）
SLIMMED_ONLY ?= 0

# TrollStore 专用包开关（切换 tipa 后缀与 trollstore entitlements）
TROLLSTORE_JIT_ENT ?= 0

# 无 Git 仓库时的兜底值，保证编译不失败
BRANCH ?= "unknown"
COMMIT ?= "unknown"

# 签名 TeamID 与描述文件，缺省跳过 codesign
SIGNING_TEAMID ?= -1
TEAMID ?= -1
PROVISIONING ?= -1

ifeq (1,$(RELEASE))
CMAKE_BUILD_TYPE := Release
else
CMAKE_BUILD_TYPE := Debug
endif

# 区分构建主机平台（仅 macOS 可出 iOS 包，Linux/其他直接报错）
ifeq ($(DETECTPLAT),Darwin)
OSVER       := $(shell sw_vers -productVersion | cut -b 1-2)
ifeq ($(shell sw_vers -productName),macOS)
IOS         := 0
SDKPATH     ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
SIMSDKPATH  ?= $(shell xcrun --sdk iphonesimulator --show-sdk-path)
BOOTJDK     ?= $(shell /usr/libexec/java_home -v 1.8 2>/dev/null)/bin
$(warning 在 macOS 上构建 LuminAgent。)
else
IOS         := 1
SDKPATH     ?= /usr/share/SDKs/iPhoneOS.sdk
BOOTJDK     ?= /usr/lib/jvm/java-8-openjdk/bin
$(warning 在 iOS 本机上构建，部分目标可能不可用。)
endif
else ifeq ($(DETECTPLAT),Linux)
IOS         := 0
BOOTJDK     ?= /usr/bin
$(warning 在 Linux 上构建，仅允许校验性目标，完整 iOS 打包需 macOS。)
else
$(error 当前平台不支持构建 LuminAgent，请使用 macOS。)
endif

# 由 PLATFORM 推导 PLATFORM_NAME（首版支持 2=iOS 与 7=iOS Simulator，预留 tvOS/visionOS 编号）
ifeq ($(PLATFORM),2)
PLATFORM_NAME := ios
SDKACTIVE   := $(SDKPATH)
$(warning PLATFORM=2，即 iOS 真机。)
else ifeq ($(PLATFORM),3)
PLATFORM_NAME := tvos
SDKACTIVE   := $(SDKPATH)
$(warning PLATFORM=3，即 tvOS（预留）。)
else ifeq ($(PLATFORM),7)
PLATFORM_NAME := iossimulator
SDKACTIVE   := $(SIMSDKPATH)
$(warning PLATFORM=7，即 iOS 模拟器。)
else ifeq ($(PLATFORM),11)
PLATFORM_NAME := xros
SDKACTIVE   := $(SDKPATH)
$(warning PLATFORM=11，即 visionOS（预留）。)
else
$(error PLATFORM 无效，仅支持 2（iOS）/7（模拟器），预留 3/11。)
endif

APP_NAME            ?= LuminAgent
BUNDLE_ID           ?= com.luminagent.ios
LUMIN_BUNDLE_DIR    ?= $(OUTPUTDIR)/$(APP_NAME).app
LUMIN_EXECUTABLE    ?= $(WORKINGDIR)/$(APP_NAME)
MODEL_RUNTIME_DIR   ?= $(SOURCEDIR)/depends/model_runtimes

# 依赖检查函数
METHOD_DEPCHECK   = $(shell $(1) >/dev/null 2>&1 && echo 1)

# Mach-O 平台重打标函数（iOS=2，iOS Simulator=7）
# 全量重打标，保证侧载/模拟器产物平台标记正确
METHOD_CHANGE_PLAT = \
	if [ '$(1)' != '11' ] && [ '$(1)' != '12' ]; then \
		vtool -arch arm64 -set-build-version $(1) 15.0 16.0 -replace -output $(2) $(2); \
		ldid -S -M $(2); \
	else \
		vtool -arch arm64 -set-build-version $(1) 1.0 1.0 -replace -output $(2) $(2); \
	fi

# 打包函数：zip --symlinks 出 ipa；TROLLSTORE_JIT_ENT=1 时出 tipa；slim 变体排除模型运行时
METHOD_PACKAGE = \
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		IPA_SUFFIX="-trollstore.tipa"; \
	else \
		IPA_SUFFIX=".ipa"; \
	fi; \
	rm -f $(OUTPUTDIR)/$(BUNDLE_ID)-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX; \
	rm -f $(OUTPUTDIR)/$(BUNDLE_ID).slimmed-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX; \
	if [ '$(SLIMMED_ONLY)' = '0' ]; then \
		zip --symlinks -r $(OUTPUTDIR)/$(BUNDLE_ID)-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX Payload; \
	fi; \
	if [ '$(SLIMMED)' = '1' ] || [ '$(SLIMMED_ONLY)' = '1' ]; then \
		zip --symlinks -r $(OUTPUTDIR)/$(BUNDLE_ID).slimmed-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX Payload --exclude='Payload/$(APP_NAME).app/model_runtimes/*'; \
	fi

# 签名函数（TEAMID/PROVISIONING 缺省 -1 时由调用方跳过）
METHOD_CODESIGN = \
	codesign --remove-signature $(2); \
	codesign -f -s $(1) --generate-entitlement-der --entitlements entitlements.codesign.xml $(2); \
	printf 'File: '; printf $(2); printf ', Codesigned with team: '; printf $(1); printf '\n'

# 对目录下所有 Mach-O 执行给定命令
METHOD_MACHO = \
	for file in $$(find $(1)); do \
		if [[ "$$(file $$file)" == *"Mach-O"* ]]; then \
			$(2); \
		fi; \
	done

# 目录检查函数（不存在则创建，存在则清空）
METHOD_DIRCHECK   = \
	if [ ! -d '$(1)' ]; then \
		mkdir -p $(1); \
	else \
		rm -rf $(1)/*; \
	fi

# 并行任务数：macOS 取 sysctl，其他取 nproc，兜底 2
ifneq ($(filter sysctl,$(shell sysctl -n hw.logicalcpu 2>/dev/null)),)
ifneq ($(call METHOD_DEPCHECK,nproc --version),1)
ifneq ($(call METHOD_DEPCHECK,gnproc --version),1)
$(warning 无法确定线程数，默认使用 2。)
JOBS   ?= 2
else
JOBS   ?= $(shell gnproc)
endif
else
JOBS   ?= $(shell nproc)
endif
else
JOBS   ?= $(shell sysctl -n hw.ncpu 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 2)
endif

ifndef SDKPATH
$(error 需要指定 SDKPATH（iPhoneOS.sdk 路径，版本 15.0+）。macOS 下自动由 xcrun 推导。)
endif

# 主目标链（对标 Amethyst all，去 java/jre、留模型运行时位）
all: clean native assets payload package dsym

help:
	echo 'Makefile 编译 LuminAgent（唯一构建入口）'
	echo ''
	echo 'Usage:'
	echo '    make                                执行 all'
	echo '    make help                           显示本帮助'
	echo '    make all                            完整构建（clean native assets payload package dsym）'
	echo '    make native                         构建原生层（CMake）'
	echo '    make assets                         编译 Assets.xcassets'
	echo '    make payload                        组装 Payload/LuminAgent.app'
	echo '    make package                        生成 ipa/tipa'
	echo '    make dsym                           生成调试符号 dSYM'
	echo '    make deploy                         拷贝产物到本地 iDevice（需连接设备）'
	echo '    make codesign                       用 TEAMID 重签名 app'
	echo '    make check                          打印全部变量供检查'
	echo '    make clean                          清理构建目录与产物'
	echo ''
	echo 'Flags: RELEASE=1 PLATFORM=2/7 VERBOSE=1 SLIMMED=1 SLIMMED_ONLY=1 TROLLSTORE_JIT_ENT=1 RUNNER=1 TEAMID=xxx PROVISIONING=xxx'

check:
	$(foreach v, \
		$(shell echo "$(filter-out METHOD_% .% MAKEFILE_LIST MAKEFLAGS CURDIR,$(.VARIABLES))" | tr ' ' '\n' | sort), \
		$(if $(filter file,$(origin $(v))), \
		$(info $(shell printf "%-20s" "$(v)") = $(value $(v)))) \
	)

# 原生层：CMake 交叉编译（固定参数见下方，部署目标 15.0）
native:
	echo '[LuminAgent v$(VERSION)] native - start'
	mkdir -p $(WORKINGDIR)
	cmake -S $(SOURCEDIR) -B $(WORKINGDIR) \
		-DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT=$(shell xcrun --sdk iphoneos --show-sdk-path) \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
		-DCMAKE_C_FLAGS="-arch arm64 -miphoneos-version-min=15.0" \
		-DCMAKE_OBJC_FLAGS="-arch arm64 -miphoneos-version-min=15.0" \
		-DCONFIG_BRANCH="$(BRANCH)" \
		-DCONFIG_COMMIT="$(COMMIT)" \
		-DCONFIG_RELEASE=$(RELEASE)
	cmake --build $(WORKINGDIR) --config $(CMAKE_BUILD_TYPE) -j$(JOBS)
	echo '[LuminAgent v$(VERSION)] native - end'

# 资源编译：仅编 catalog，无 storyboard
assets: native
	echo '[LuminAgent v$(VERSION)] assets - start'
	$(call METHOD_DIRCHECK,$(SOURCEDIR)/build-resources)
	find $(SOURCEDIR)/Resources/Assets.xcassets -type f | sort
	xcrun actool $(SOURCEDIR)/Resources/Assets.xcassets --compile $(SOURCEDIR)/build-resources --platform iphoneos --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist $(SOURCEDIR)/build-resources/AssetInfo.plist --output-format human-readable-text --errors --warnings --notices
	ls -la $(SOURCEDIR)/build-resources
	echo '[LuminAgent v$(VERSION)] assets - end'

# 组装 .app：clang 链接 Core 静态库 + 系统库，ldid 打标，组装 Payload
payload: native assets
	echo '[LuminAgent v$(VERSION)] payload - start'
	$(call METHOD_DIRCHECK,$(OUTPUTDIR)/Payload)
	rm -rf $(LUMIN_BUNDLE_DIR)
	mkdir -p $(LUMIN_BUNDLE_DIR)
	cp $(LUMIN_EXECUTABLE) $(LUMIN_BUNDLE_DIR)/$(APP_NAME)
	cp $(SOURCEDIR)/Natives/Info.plist $(LUMIN_BUNDLE_DIR)/Info.plist
	if [ ! -f '$(SOURCEDIR)/build-resources/Assets.car' ]; then \
		echo 'assets 产物缺失：build-resources/Assets.car 不存在，拒绝组包' >&2; \
		exit 1; \
	fi
	cp -R $(SOURCEDIR)/build-resources/* $(LUMIN_BUNDLE_DIR)/
	cp -R $(SOURCEDIR)/Resources/*.lproj $(LUMIN_BUNDLE_DIR)/ 2>/dev/null || true
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		ldid -S$(SOURCEDIR)/entitlements.trollstore.xml $(LUMIN_BUNDLE_DIR)/$(APP_NAME); \
	else \
		ldid -S$(SOURCEDIR)/entitlements.sideload.xml $(LUMIN_BUNDLE_DIR)/$(APP_NAME); \
	fi
	mkdir -p $(SOURCEDIR)/Payload
	rm -rf $(SOURCEDIR)/Payload/*
	cp -R $(LUMIN_BUNDLE_DIR) $(SOURCEDIR)/Payload/
	echo '[LuminAgent v$(VERSION)] payload - end'

# 打包：标准 ipa / trollstore tipa / slim 变体
package: payload
	echo '[LuminAgent v$(VERSION)] package - start'
	mkdir -p $(OUTPUTDIR)
	cd $(SOURCEDIR) && bash scripts/package-ipa.sh
	$(call METHOD_PACKAGE)
	echo '[LuminAgent v$(VERSION)] package - end'

# 调试符号：dsymutil 抽取 arm64 符号
dsym: payload
	echo '[LuminAgent v$(VERSION)] dsym - start'
	bash scripts/collect-dsym.sh
	rm -rf $(OUTPUTDIR)/$(APP_NAME).dSYM
	dsymutil --arch arm64 $(LUMIN_BUNDLE_DIR)/$(APP_NAME) -o $(OUTPUTDIR)/$(APP_NAME).dSYM
	echo '[LuminAgent v$(VERSION)] dsym - end'

# 部署到本地已连接 iDevice（越狱/开发者模式，需 ideviceinstaller）
deploy: package
	echo '[LuminAgent v$(VERSION)] deploy - start'
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		ls $(OUTPUTDIR)/*-trollstore.tipa; \
	else \
		ls $(OUTPUTDIR)/*.ipa; \
	fi
	echo '请将上述产物经 AltStore/SideStore 或 TrollStore 安装到设备。'
	echo '[LuminAgent v$(VERSION)] deploy - end'

# 用开发者证书重签名（需 TEAMID 与 PROVISIONING）
codesign:
	echo '[LuminAgent v$(VERSION)] codesign - start'
	if [ '$(TEAMID)' = '-1' ]; then \
		echo 'TEAMID 未设置，跳过 codesign。用法：make codesign TEAMID=XXXXXXXXXX'; \
	else \
		$(call METHOD_CODESIGN,$(TEAMID),$(LUMIN_BUNDLE_DIR)); \
	fi
	echo '[LuminAgent v$(VERSION)] codesign - end'

clean:
	echo '[LuminAgent v$(VERSION)] clean - start'
	rm -rf $(WORKINGDIR)/* $(OUTPUTDIR)/Payload $(OUTPUTDIR)/*.ipa $(OUTPUTDIR)/*.tipa $(OUTPUTDIR)/*.dSYM $(OUTPUTDIR)/$(APP_NAME).app $(SOURCEDIR)/Payload $(SOURCEDIR)/build-resources
	echo '[LuminAgent v$(VERSION)] clean - end'

.PHONY: all help check native assets payload package dsym deploy codesign clean
