# Makefile for MyBody
# 统一封装常用命令，无需打开 Xcode 即可在模拟器中运行。

SCHEME ?= MyBody
PROJECT ?= MyBody.xcodeproj
SIMULATOR_DEVICE ?= iPhone 16
CONFIG ?= Debug
BUNDLE_ID ?= brickverse.MyBody
PRODUCT_NAME ?= 我的身体
DERIVED_DATA ?= build/DerivedData

# 日志美化（可选）
LOG_PIPE = | cat
ifeq ($(shell command -v xcbeautify >/dev/null 2>&1 && echo yes),yes)
	LOG_PIPE = | xcbeautify
else ifeq ($(shell command -v xcpretty >/dev/null 2>&1 && echo yes),yes)
	LOG_PIPE = | xcpretty
endif

YELLOW=\033[0;33m
GREEN=\033[0;32m
NC=\033[0m

.DEFAULT_GOAL := help

## help: 显示可用命令
.PHONY: help
help:
	@grep -E '^##' Makefile | sed -e 's/## //'

## gen: 使用 xcodegen 生成 Xcode 工程
.PHONY: gen
gen:
	@if ! command -v xcodegen >/dev/null 2>&1; then \
		echo "未检测到 xcodegen，安装：brew install xcodegen"; exit 70; \
	fi
	@TEAM="$${DEVELOPMENT_TEAM:-$$( $(MAKE) -s resolve-team )}"; \
	if [ -n "$$TEAM" ]; then \
		echo "[gen] 使用 DEVELOPMENT_TEAM=$$TEAM"; \
	else \
		echo "[gen] ⚠️  未检测到开发者 Team，字段将留空（模拟器构建不受影响）"; \
	fi; \
	DEVELOPMENT_TEAM=$$TEAM xcodegen generate
	@# 反勾 Metal 全部 4 项诊断(API Validation / Shader Validation /
	@# Show & Log Graphics Overview)。在 "Designed for iPhone on Mac" 上,
	@# Vision 使用 shared-storage Metal 纹理会触发 synchronizeResource 断言崩溃,
	@# 同时 GPU overview 日志也会污染 run-mac 的输出。
	@SCHEME_FILE="$(PROJECT)/xcshareddata/xcschemes/$(SCHEME).xcscheme"; \
	if [ -f "$$SCHEME_FILE" ]; then \
		/usr/bin/python3 scripts/patch_scheme_metal.py "$$SCHEME_FILE"; \
	fi

## resolve-team: 输出要使用的 DEVELOPMENT_TEAM（内部使用）
##   优先级：
##     1. 环境变量 $$DEVELOPMENT_TEAM
##     2. Xcode IDEProvisioningTeams 中 isFreeProvisioningTeam=false 的第一个付费 Team
##     3. Xcode IDEProvisioningTeams 中第一个 Team（Personal 也行）
##     4. Apple Development 证书 OU 字段
.PHONY: resolve-team
resolve-team:
	@if [ -n "$$DEVELOPMENT_TEAM" ]; then echo "$$DEVELOPMENT_TEAM"; exit 0; fi; \
	PLIST=$$HOME/Library/Preferences/com.apple.dt.Xcode.plist; \
	if [ -f "$$PLIST" ]; then \
		TEAM=$$(plutil -p "$$PLIST" 2>/dev/null | awk ' \
			/"IDEProvisioningTeams"/ { in_ipt=1 } \
			in_ipt && /"isFreeProvisioningTeam" => false/ { paid=1 } \
			in_ipt && /"isFreeProvisioningTeam" => true/ { paid=0 } \
			in_ipt && paid && /"teamID" =>/ { gsub(/[",]/,""); print $$3; exit } \
		'); \
		if [ -z "$$TEAM" ]; then \
			TEAM=$$(plutil -p "$$PLIST" 2>/dev/null | awk ' \
				/"IDEProvisioningTeams"/ { in_ipt=1 } \
				in_ipt && /"teamID" =>/ { gsub(/[",]/,""); print $$3; exit } \
			'); \
		fi; \
	fi; \
	if [ -z "$$TEAM" ]; then \
		TEAM=$$(security find-certificate -c 'Apple Development' -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU=([A-Z0-9]{10}).*/\1/p' | head -1); \
	fi; \
	echo "$$TEAM"

## build: 为模拟器构建应用
.PHONY: build
build: gen
	@echo "[build] 构建 $(SCHEME) ($(CONFIG) / iphonesimulator)"
	@xcodebuild -scheme $(SCHEME) -project $(PROJECT) -configuration $(CONFIG) \
		-sdk iphonesimulator -derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO build $(LOG_PIPE)

## run: 在模拟器中构建并启动应用（无需打开 Xcode）
.PHONY: run
run: gen
	@set -euo pipefail; \
	DEVICE_NAME="$(SIMULATOR_DEVICE)"; \
	if ! xcrun simctl list devices available | grep -q "$$DEVICE_NAME ("; then \
		DEVICE_NAME=$$(xcrun simctl list devices available | grep -E 'iPhone [0-9]+' | head -1 | sed -E 's/^ *//; s/ \(.*//'); \
		echo "[run] 指定模拟器不存在，自动改用: $$DEVICE_NAME"; \
	fi; \
	echo "[run] 使用模拟器: $$DEVICE_NAME"; \
	open -a Simulator >/dev/null 2>&1 || true; \
	xcrun simctl boot "$$DEVICE_NAME" >/dev/null 2>&1 || true; \
	xcrun simctl bootstatus "$$DEVICE_NAME" -b || true; \
	echo "[run] 构建应用 (scheme=$(SCHEME) config=$(CONFIG))"; \
	xcodebuild -scheme $(SCHEME) -project $(PROJECT) -configuration $(CONFIG) \
		-sdk iphonesimulator -derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO build $(LOG_PIPE); \
	APP_PATH="$(DERIVED_DATA)/Build/Products/$(CONFIG)-iphonesimulator/$(PRODUCT_NAME).app"; \
	if [ ! -d "$$APP_PATH" ]; then echo "构建失败：未找到 $$APP_PATH"; exit 1; fi; \
	echo "[run] 卸载旧版本 (忽略错误)"; \
	xcrun simctl uninstall booted $(BUNDLE_ID) >/dev/null 2>&1 || true; \
	echo "[run] 安装应用: $$APP_PATH"; \
	xcrun simctl install booted "$$APP_PATH"; \
	echo "[run] 启动应用"; \
	xcrun simctl launch booted $(BUNDLE_ID) || true; \
	echo "[run] ✅ 已启动 $(BUNDLE_ID) 于 $$DEVICE_NAME"

## logs: 跟踪当前应用的日志（Ctrl+C 退出）
.PHONY: logs
logs:
	@xcrun simctl spawn booted log stream --level=debug --predicate 'processImagePath CONTAINS "$(SCHEME)"'

## run-mac: 以 “My Mac (Designed for iPhone)” 模式构建，并通过 Xcode 启动
##   说明：原生 iOS .app 无法通过 `open` 直接在 Mac 上启动（macOS LaunchServices
##   只认 Mac 格式），但 Xcode 能借助内部 installd 机制运行。因此该目标会：
##     1. 用正确的 destination 预构建，确保 Team/签名无误
##     2. 打开 Xcode 并触发 Run（Team 已由 `make gen` 写入 pbxproj，不再弹窗）
.PHONY: run-mac
run-mac: gen
	@set -euo pipefail; \
	TEAM=$$( $(MAKE) -s resolve-team ); \
	if [ -z "$$TEAM" ]; then \
		echo "[run-mac] ❌ 未找到开发者 Team。请先在 Xcode 登录 Apple ID，或运行：export DEVELOPMENT_TEAM=XXXXXXXXXX"; exit 1; \
	fi; \
	echo "[run-mac] 使用 DEVELOPMENT_TEAM=$$TEAM"; \
	DEST='platform=macOS,arch=arm64,variant=Designed for iPad'; \
	echo "[run-mac] 预构建 (destination: Designed for iPhone on Mac)"; \
	xcodebuild -scheme $(SCHEME) -project $(PROJECT) -configuration $(CONFIG) \
		-destination "$$DEST" \
		-derivedDataPath $(DERIVED_DATA) \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$$TEAM \
		CODE_SIGN_STYLE=Automatic \
		build $(LOG_PIPE); \
	echo "[run-mac] ✅ 构建通过。打开 Xcode 并触发 Run…"; \
	open -a Xcode $(PROJECT); \
	sleep 2; \
	osascript -e 'tell application "Xcode" to activate' \
		-e 'tell application "System Events" to tell process "Xcode" to keystroke "r" using command down' \
		|| echo "[run-mac] ℹ️  自动按 Cmd+R 失败（可能需要辅助功能权限），请手动点 Run。"

## xcode: 生成工程并在 Xcode 中打开（Team 已自动写入）
.PHONY: xcode
xcode: gen
	@open -a Xcode $(PROJECT); \
	echo "[xcode] ✅ 已在 Xcode 中打开 $(PROJECT)。Team 已预填，直接 Cmd+R 即可。"

## stop: 终止模拟器中的应用
.PHONY: stop
stop:
	@xcrun simctl terminate booted $(BUNDLE_ID) || true

## clean: 清理构建产物
.PHONY: clean
clean:
	@rm -rf build
	@echo "[clean] 已清理 build/"

## deps: 提示安装可选日志美化工具
.PHONY: deps
deps:
	@if ! command -v xcodegen >/dev/null 2>&1; then \
		printf "$(YELLOW)未安装 xcodegen：brew install xcodegen$(NC)\n"; \
	else printf "$(GREEN)xcodegen 已安装$(NC)\n"; fi
	@if ! command -v xcbeautify >/dev/null 2>&1 && ! command -v xcpretty >/dev/null 2>&1; then \
		printf "$(YELLOW)（可选）日志美化：brew install xcbeautify$(NC)\n"; \
	fi
