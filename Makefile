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
	@xcodegen generate

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
