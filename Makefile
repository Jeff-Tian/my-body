# Makefile for MyBody
# 统一封装常用命令，无需打开 Xcode 即可在模拟器中运行。

# 自动载入 .env（若存在）—— 里面的 KEY=VALUE 同时成为 make 变量和 recipe 环境变量。
# 这样 `make release` 无需先手动 `source .env`。
# .env 必须使用 `KEY=VALUE` 形式，不要加 `export` 前缀或引号（参考 .env.example）。
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

SCHEME ?= MyBody
PROJECT ?= MyBody.xcodeproj
SIMULATOR_DEVICE ?= iPhone 16
CONFIG ?= Debug
BUNDLE_ID ?= brickverse.MyBodyApp
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

## run_device: 在真实 iPhone 上构建并安装+启动（支持 USB / WiFi 配对设备）
##   用法：
##     make run_device                   # 自动检测（USB 或 WiFi 配对）
##     UDID=xxxx-yyyy make run_device    # 手动指定设备
##   前置：Xcode 15+（自带 xcrun devicectl）。若无 devicectl 会回退到 ios-deploy。
##   WiFi 部署：需先在 Xcode → Window → Devices and Simulators 中勾选
##              "Connect via network"（设备须与 Mac 同一局域网）。
.PHONY: run_device run-device
run-device: run_device
run_device: gen
	@set -euo pipefail; \
	TEAM=$$( $(MAKE) -s resolve-team ); \
	if [ -z "$$TEAM" ]; then \
		echo "[run_device] ❌ 未找到开发者 Team，请先在 Xcode 登录 Apple ID，或 export DEVELOPMENT_TEAM=XXXXXXXXXX"; \
		exit 1; \
	fi; \
	echo "[run_device] 使用 DEVELOPMENT_TEAM=$$TEAM"; \
	HAVE_DEVICECTL=0; \
	if xcrun --find devicectl >/dev/null 2>&1; then HAVE_DEVICECTL=1; fi; \
	DEVICE_ID="$${UDID:-}"; \
	DEVICE_NAME=""; \
	if [ -z "$$DEVICE_ID" ]; then \
		echo "[run_device] 自动检测已连接的设备（USB + WiFi）..."; \
		if [ "$$HAVE_DEVICECTL" = "1" ]; then \
			TMP_JSON="/tmp/devicectl.$$$$.json"; \
			xcrun devicectl list devices --json-output "$$TMP_JSON" >/dev/null 2>&1 || true; \
			/usr/bin/python3 -c "import json; \
d=json.load(open('$$TMP_JSON')); \
cands=[x for x in d.get('result',{}).get('devices',[]) if x.get('hardwareProperties',{}).get('platform')=='iOS' and x.get('connectionProperties',{}).get('pairingState')=='paired']; \
[print(f\"  - {x['deviceProperties']['name']}  id={x['identifier']}  tunnel={x['connectionProperties'].get('tunnelState','?')}  transport={x['connectionProperties'].get('transportType','?')}\") for x in cands]" 2>/dev/null || true; \
			PICK=$$(/usr/bin/python3 -c "import json; \
d=json.load(open('$$TMP_JSON')); \
devs=d.get('result',{}).get('devices',[]); \
cands=[x for x in devs if x.get('hardwareProperties',{}).get('platform')=='iOS' and x.get('connectionProperties',{}).get('pairingState')=='paired']; \
reachable=[x for x in cands if x.get('connectionProperties',{}).get('tunnelState') in ('connected','available') or (x.get('connectionProperties',{}).get('transportType') or 'None') not in ('None','')]; \
pick=reachable[0] if reachable else None; \
print('\t'.join([pick.get('identifier',''), pick.get('deviceProperties',{}).get('name','')])) if pick else None" 2>/dev/null || true); \
			rm -f "$$TMP_JSON"; \
			DEVICE_ID=$$(echo "$$PICK" | awk -F'\t' '{print $$1}'); \
			DEVICE_NAME=$$(echo "$$PICK" | awk -F'\t' '{print $$2}'); \
			if [ -n "$$DEVICE_ID" ]; then \
				echo "[run_device] ✅ 选中: $$DEVICE_NAME ($$DEVICE_ID)"; \
				echo "[run_device]   （多台设备时可用 UDID=<identifier> make run-device 精确指定）"; \
			fi; \
		fi; \
		if [ -z "$$DEVICE_ID" ] && command -v ios-deploy >/dev/null 2>&1; then \
			DETECTED=$$(ios-deploy -c -t 2 2>&1 | grep 'Found' || true); \
			if [ -n "$$DETECTED" ]; then \
				echo "$$DETECTED" | head -5; \
				DEVICE_ID=$$(echo "$$DETECTED" | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{16}' | head -1 || true); \
				if [ -z "$$DEVICE_ID" ]; then \
					DEVICE_ID=$$(echo "$$DETECTED" | grep -oE '[0-9a-fA-F]{40}' | head -1 || true); \
				fi; \
				DEVICE_NAME=$$(echo "$$DETECTED" | head -1 | sed -nE "s/.*'([^']+)'.*/\1/p"); \
			fi; \
		fi; \
	else \
		if [ "$$HAVE_DEVICECTL" = "1" ]; then \
			TMP_JSON="/tmp/devicectl.$$$$.json"; \
			xcrun devicectl list devices --json-output "$$TMP_JSON" >/dev/null 2>&1 || true; \
			RESOLVED=$$(/usr/bin/python3 -c "import json; \
d=json.load(open('$$TMP_JSON')); \
devs=d.get('result',{}).get('devices',[]); \
m=[x for x in devs if x.get('identifier')=='$$DEVICE_ID' or x.get('hardwareProperties',{}).get('udid')=='$$DEVICE_ID']; \
print('\t'.join([m[0].get('identifier',''), m[0].get('deviceProperties',{}).get('name','')])) if m else None" 2>/dev/null || true); \
			rm -f "$$TMP_JSON"; \
			if [ -n "$$RESOLVED" ]; then \
				DEVICE_ID=$$(echo "$$RESOLVED" | awk -F'\t' '{print $$1}'); \
				DEVICE_NAME=$$(echo "$$RESOLVED" | awk -F'\t' '{print $$2}'); \
			fi; \
		fi; \
	fi; \
	if [ -z "$$DEVICE_ID" ]; then \
		echo "[run_device] ❌ 未找到当前可达的 iPhone。"; \
		echo "  已配对的设备（上面列出，但 tunnel=unavailable / transport=None 表示没有活跃连接）："; \
		echo "  修复方式（任选其一）："; \
		echo "    1. USB：连接设备并在设备上点「信任此电脑」，等几秒让 transport 变为 wired"; \
		echo "    2. WiFi：打开 Xcode → Window → Devices and Simulators → 勾选目标设备的「Connect via network」；"; \
		echo "       确保设备亮屏解锁、已连同一 WiFi，然后重试"; \
		echo "    3. 手动指定：UDID=<identifier> make run-device"; \
		exit 70; \
	fi; \
	if [ -n "$$DEVICE_NAME" ]; then \
		echo "[run_device] 使用设备: $$DEVICE_NAME ($$DEVICE_ID)"; \
	else \
		echo "[run_device] 使用设备 ID: $$DEVICE_ID"; \
	fi; \
	echo "[run_device] 构建 Debug（generic/platform=iOS）"; \
	xcodebuild -scheme $(SCHEME) -project $(PROJECT) -configuration Debug \
		-destination "generic/platform=iOS" \
		-derivedDataPath $(DERIVED_DATA) \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$$TEAM \
		CODE_SIGN_STYLE=Automatic \
		build $(LOG_PIPE); \
	APP_PATH="$$(find $(DERIVED_DATA)/Build/Products/Debug-iphoneos -type d -name '$(PRODUCT_NAME).app' -maxdepth 2 | head -1)"; \
	if [ -z "$$APP_PATH" ]; then \
		APP_PATH="$$(find $(DERIVED_DATA)/Build/Products/Debug-iphoneos -type d -name '*.app' -maxdepth 2 | head -1)"; \
	fi; \
	if [ -z "$$APP_PATH" ] || [ ! -d "$$APP_PATH" ]; then \
		echo "[run_device] ❌ 构建成功但未找到 .app，请检查派生数据路径：$(DERIVED_DATA)"; \
		exit 1; \
	fi; \
	echo "[run_device] 安装并启动: $$APP_PATH"; \
	if [ "$$HAVE_DEVICECTL" = "1" ]; then \
		xcrun devicectl device install app --device "$$DEVICE_ID" "$$APP_PATH"; \
		xcrun devicectl device process launch --device "$$DEVICE_ID" --terminate-existing $(BUNDLE_ID); \
	else \
		if ! command -v ios-deploy >/dev/null 2>&1; then \
			printf "$(YELLOW)devicectl 与 ios-deploy 均不可用。安装：brew install ios-deploy 或升级到 Xcode 15+$(NC)\n"; \
			exit 70; \
		fi; \
		ios-deploy --id "$$DEVICE_ID" --bundle "$$APP_PATH" --justlaunch; \
	fi; \
	echo "[run_device] ✅ 已在「$${DEVICE_NAME:-$$DEVICE_ID}」上安装并启动 $(BUNDLE_ID)"

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

## screenshots: 使用 fastlane snapshot 在模拟器中自动生成 App Store 截图
##   用法：
##     make screenshots                              # 使用默认模拟器
##     SNAPSHOT_DEVICE="iPhone 16 Pro Max" make screenshots
##     SNAPSHOT_RESULT_BUNDLE=1 make screenshots     # 生成 xcresult 便于排查
##   产物位于 fastlane/screenshots/<lang>/*.png
.PHONY: screenshots
screenshots: gen
	@set -euo pipefail; \
	if ! command -v bundle >/dev/null 2>&1; then \
		printf "$(YELLOW)[screenshots] 未安装 bundler：gem install bundler$(NC)\n"; exit 70; \
	fi; \
	if [ ! -f Gemfile.lock ]; then \
		printf "$(GREEN)[screenshots] 首次运行，执行 bundle install…$(NC)\n"; \
		bundle install; \
	fi; \
	printf "$(GREEN)[screenshots] 启动 fastlane snapshot…$(NC)\n"; \
	bundle exec fastlane screenshots

## market: 启动本地 HTTP 服务器预览 marketing 页面（SNAPSHOT=1 可先用 fastlane 生成截图）
##   用法：
##     make market                 # 直接启动预览（使用 marketing/screenshots 已有图片）
##     make market SNAPSHOT=1      # 先运行 fastlane snapshot 重新生成截图再预览
##     make market PORT=8080       # 指定端口
.PHONY: market
market:
ifeq ($(SNAPSHOT),1)
	@printf "$(GREEN)[market] 生成截图...$(NC)\n"
	@if ! command -v bundle >/dev/null 2>&1; then \
		printf "$(YELLOW)未安装 bundler/fastlane，跳过截图生成。安装：gem install bundler && bundle install$(NC)\n"; \
	else \
		SNAPSHOT_DEVICE=$$(xcrun simctl list devices available | grep -E 'iPhone.*Pro Max' | tail -1 | sed -E 's/^ *//; s/ \(.*//' || echo "iPhone 16 Pro Max"); \
		printf "$(YELLOW)[market] 使用模拟器: $$SNAPSHOT_DEVICE$(NC)\n"; \
		SNAPSHOT_DEVICE="$$SNAPSHOT_DEVICE" bundle exec fastlane snapshot 2>&1 \
			|| printf "$(YELLOW)[market] 截图生成失败，改用 marketing/screenshots 中已有图片$(NC)\n"; \
	fi
endif
	@mkdir -p marketing/screenshots
	@bash scripts/copy_screenshots.sh || true
	@PORT=$${PORT:-8000}; \
	printf "$(GREEN)[market] 启动本地预览服务器...$(NC)\n"; \
	printf "$(YELLOW)[market] 访问地址: http://localhost:$$PORT/$(NC)\n"; \
	printf "$(YELLOW)[market] 按 Ctrl+C 停止服务器$(NC)\n\n"; \
	cd marketing && (python3 -m http.server $$PORT || python -m SimpleHTTPServer $$PORT)

## secrets-sync: 从 .env 读取变量并同步到 GitHub repo secrets (通过 gh CLI)
##   - 忽略以 # 开头的注释行和空行
##   - 值为空的 KEY 会被跳过（不会清空已有 secret）
##   - 需要已安装 gh 且通过 `gh auth login` 登录
##   - 用法：先编辑 .env，再 `make secrets-sync`
.PHONY: secrets-sync
secrets-sync:
	@if ! command -v gh >/dev/null 2>&1; then \
		printf "$(YELLOW)未检测到 gh CLI。安装：brew install gh && gh auth login$(NC)\n"; exit 70; \
	fi
	@if [ ! -f .env ]; then \
		printf "$(YELLOW)未找到 .env，请先从 .env.example 复制：cp .env.example .env$(NC)\n"; exit 1; \
	fi
	@REPO=$$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null); \
	if [ -z "$$REPO" ]; then \
		printf "$(YELLOW)无法确定当前仓库 (gh repo view 失败)，请在仓库目录下执行$(NC)\n"; exit 1; \
	fi; \
	printf "$(GREEN)[secrets-sync] 目标仓库: $$REPO$(NC)\n"; \
	SET=0; SKIPPED=0; \
	while IFS= read -r line || [ -n "$$line" ]; do \
		case "$$line" in ''|\#*) continue ;; esac; \
		key=$${line%%=*}; \
		val=$${line#*=}; \
		key=$$(printf '%s' "$$key" | tr -d '[:space:]'); \
		case "$$val" in \"*\") val=$${val#\"}; val=$${val%\"} ;; esac; \
		case "$$val" in \'*\') val=$${val#\'}; val=$${val%\'} ;; esac; \
		if [ -z "$$key" ]; then continue; fi; \
		if [ -z "$$val" ]; then \
			printf "$(YELLOW)  - skip  $$key (empty)$(NC)\n"; \
			SKIPPED=$$((SKIPPED+1)); continue; \
		fi; \
		printf '%s' "$$val" | gh secret set "$$key" --repo "$$REPO" --body - >/dev/null; \
		printf "$(GREEN)  ✓ set   $$key$(NC)\n"; \
		SET=$$((SET+1)); \
	done < .env; \
	printf "$(GREEN)[secrets-sync] 完成：设置 $$SET 个，跳过 $$SKIPPED 个$(NC)\n"

## secrets-list: 列出当前仓库已有的 GitHub secrets（名称，不显示值）
.PHONY: secrets-list
secrets-list:
	@gh secret list

# ---------------------------------------------------------------------------
# 本地发版：上传 App Store 元数据 + 截图到 ASC（不打包、不提审）
# ---------------------------------------------------------------------------
# 一次性准备：
#   make install_asc_key             # 半自动：打开 ASC → 监听 Downloads →
#                                    # 移动 .p8 → chmod → 写 .env（一条命令搞定）
# 每次发版：
#   make release                     # Makefile 会自动载入 .env，无需 source
#
# 可选开关：
#   SKIP_SNAPSHOT=1    跳过重跑截图（直接用 fastlane/screenshots 里已有文件）
#   SKIP_METADATA=1    跳过元数据上传（只推截图）
#   SKIP_SCREENSHOTS=1 跳过截图上传（只推元数据）

## install_asc_key: 半自动安装 ASC API Key（打开浏览器 → 监听 Downloads → 写 .env）
##   用法：
##     make install_asc_key                              # 正常流程
##     make install_asc_key ASC_P8=/path/to/AuthKey.p8   # 已下载好，直接指定路径
.PHONY: install_asc_key
install_asc_key:
	@bash scripts/install_asc_key.sh $(ASC_P8)

## check_asc_env: 校验 ASC API Key 所需环境变量是否已注入
.PHONY: check_asc_env
check_asc_env:
	@set -eu; \
	missing=""; \
	for var in APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_PRIVATE_KEY_PATH; do \
		eval "val=\$${$$var:-}"; \
		if [ -z "$$val" ]; then missing="$$missing $$var"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		printf "$(YELLOW)[check_asc_env] 缺少环境变量:%s$(NC)\n" "$$missing"; \
		echo "请在 .env 填入 ASC API Key 三元组（参考 .env.example / docs/release.md）。"; \
		echo "Makefile 会在执行时自动载入 .env，无需手动 source。"; \
		exit 64; \
	fi; \
	if [ ! -f "$$APP_STORE_CONNECT_PRIVATE_KEY_PATH" ]; then \
		printf "$(YELLOW)[check_asc_env] .p8 文件不存在: $$APP_STORE_CONNECT_PRIVATE_KEY_PATH$(NC)\n"; \
		exit 65; \
	fi; \
	printf "$(GREEN)[check_asc_env] ASC API Key 齐全$(NC)\n"

## check_app_exists: 用 API Key 查询 App 是否已在 ASC 建档（不需要 Apple ID）
.PHONY: check_app_exists
check_app_exists: check_asc_env
	@set -eu; \
	if [ ! -f Gemfile.lock ]; then bundle install >/dev/null; fi; \
	bundle exec ruby -e 'require "spaceship"; \
	  t = Spaceship::ConnectAPI::Token.create( \
	    key_id: ENV["APP_STORE_CONNECT_KEY_IDENTIFIER"], \
	    issuer_id: ENV["APP_STORE_CONNECT_ISSUER_ID"], \
	    key: File.read(ENV["APP_STORE_CONNECT_PRIVATE_KEY_PATH"])); \
	  Spaceship::ConnectAPI.token = t; \
	  a = Spaceship::ConnectAPI::App.find("$(BUNDLE_ID)"); \
	  if a; puts "\e[0;32m[check_app_exists] ✅ 已建档: #{a.name} (id=#{a.id})\e[0m"; \
	  else; \
	    puts "\e[0;33m[check_app_exists] ❌ App 尚未在 ASC 建档\e[0m"; \
	    puts "请到 https://appstoreconnect.apple.com/apps 点 + → 新 App，填："; \
	    puts "  Bundle ID: $(BUNDLE_ID)"; \
	    puts "  名称     : $(PRODUCT_NAME)"; \
	    puts "  主要语言 : 简体中文"; \
	    puts "  SKU      : MyBody"; \
	    exit 66; \
	  end'

## register_bundle_id: 在 Developer Portal 注册 Bundle ID（用 ASC API Key，无需 Apple ID）
.PHONY: register_bundle_id
register_bundle_id: check_asc_env
	@set -eu; \
	if [ ! -f Gemfile.lock ]; then bundle install >/dev/null; fi; \
	printf "$(GREEN)[register_bundle_id] 注册 $(BUNDLE_ID) 到 Developer Portal…$(NC)\n"; \
	bundle exec fastlane register_bundle_id

## push_metadata: 仅上传 App Store 元数据 + 截图到 ASC（不打包、不提审）
.PHONY: push_metadata
push_metadata: check_asc_env
	@set -eu; \
	if ! command -v bundle >/dev/null 2>&1; then \
		printf "$(YELLOW)[push_metadata] 未安装 bundler：gem install bundler$(NC)\n"; exit 70; \
	fi; \
	if [ ! -f Gemfile.lock ]; then \
		printf "$(GREEN)[push_metadata] 首次运行，执行 bundle install…$(NC)\n"; \
		bundle install; \
	fi; \
	printf "$(GREEN)[push_metadata] 启动 fastlane push_metadata…$(NC)\n"; \
	bundle exec fastlane push_metadata

## update_fastlane: 升级 fastlane 到最新版（避免 ASC API 变更导致的兼容问题）
##   FASTLANE_SKIP_UPDATE_CHECK=1 跳过（默认每 24h 自动尝试一次）
.PHONY: update_fastlane
update_fastlane:
	@set -eu; \
	if [ "$${FASTLANE_SKIP_UPDATE_CHECK:-0}" = "1" ]; then \
		printf "$(YELLOW)[update_fastlane] 跳过 (FASTLANE_SKIP_UPDATE_CHECK=1)$(NC)\n"; \
		exit 0; \
	fi; \
	stamp=".fastlane-last-update"; \
	if [ -f "$$stamp" ] && [ $$(( $$(date +%s) - $$(stat -f %m "$$stamp" 2>/dev/null || stat -c %Y "$$stamp") )) -lt 86400 ]; then \
		printf "$(GREEN)[update_fastlane] 24h 内已检查过，跳过$(NC)\n"; \
		exit 0; \
	fi; \
	printf "$(GREEN)[update_fastlane] bundle update fastlane…$(NC)\n"; \
	bundle update fastlane || printf "$(YELLOW)[update_fastlane] 更新失败，继续使用当前版本$(NC)\n"; \
	touch "$$stamp"

## screenshots_if_stale: 按需重拍截图（上游源变过或超过 MAX_AGE_HOURS 才重拍）
##   FORCE_SNAPSHOT=1      强制重拍
##   SKIP_SNAPSHOT=1       无条件跳过
##   SNAPSHOT_MAX_AGE=24   小时数（默认 24h）
.PHONY: screenshots_if_stale
screenshots_if_stale:
	@set -eu; \
	if [ "$${SKIP_SNAPSHOT:-0}" = "1" ]; then \
		printf "$(YELLOW)[screenshots_if_stale] 跳过 (SKIP_SNAPSHOT=1)$(NC)\n"; \
		exit 0; \
	fi; \
	if [ "$${FORCE_SNAPSHOT:-0}" = "1" ]; then \
		printf "$(GREEN)[screenshots_if_stale] 强制重拍 (FORCE_SNAPSHOT=1)$(NC)\n"; \
		$(MAKE) screenshots; \
		exit 0; \
	fi; \
	shot_dir="fastlane/screenshots/zh-Hans"; \
	if [ ! -d "$$shot_dir" ] || [ -z "$$(ls -A "$$shot_dir" 2>/dev/null | grep -E '\\.png$$' || true)" ]; then \
		printf "$(YELLOW)[screenshots_if_stale] 截图目录空，首次生成…$(NC)\n"; \
		$(MAKE) screenshots; \
		exit 0; \
	fi; \
	max_age=$${SNAPSHOT_MAX_AGE:-24}; \
	newest_shot=$$(ls -t "$$shot_dir"/*.png 2>/dev/null | head -1); \
	newest_src=$$(find MyBody MyBodyUITests project.yml -type f \( -name '*.swift' -o -name '*.yml' -o -name '*.json' -o -name '*.xcstrings' \) -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1); \
	if [ -n "$$newest_src" ] && [ "$$newest_src" -nt "$$newest_shot" ]; then \
		printf "$(YELLOW)[screenshots_if_stale] 源码比截图新 ($$newest_src) → 重拍$(NC)\n"; \
		$(MAKE) screenshots; \
		exit 0; \
	fi; \
	age_sec=$$(( $$(date +%s) - $$(stat -f %m "$$newest_shot" 2>/dev/null || stat -c %Y "$$newest_shot") )); \
	age_hr=$$(( age_sec / 3600 )); \
	if [ "$$age_hr" -ge "$$max_age" ]; then \
		printf "$(YELLOW)[screenshots_if_stale] 截图已 $${age_hr}h 未更新 (>=$${max_age}h) → 重拍$(NC)\n"; \
		$(MAKE) screenshots; \
		exit 0; \
	fi; \
	printf "$(GREEN)[screenshots_if_stale] ✅ 截图新鲜 (最新 $${age_hr}h 前)，跳过重拍$(NC)\n"

## release: 一键发版 → 按需生成截图 → 上传元数据 + 截图到 ASC
##   FORCE_SNAPSHOT=1 强制重拍截图
##   SKIP_SNAPSHOT=1  无条件跳过截图
##   SNAPSHOT_MAX_AGE=24  截图新鲜度阈值（小时）
.PHONY: release
release: check_asc_env check_app_exists update_fastlane
	@printf "$(GREEN)==> [1/2] 检查 / 生成 App Store 截图$(NC)\n"
	@$(MAKE) screenshots_if_stale
	@printf "$(GREEN)==> [2/2] 上传元数据 + 截图到 App Store Connect$(NC)\n"
	@$(MAKE) push_metadata
	@printf "$(GREEN)🎉 发版完成（仅元数据 + 截图，未上传二进制）$(NC)\n"

