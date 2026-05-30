# 身记 (MyBody)

一款极简的 iOS 健康记录 App，用来追踪 InBody 体脂仪的报告数据。

- 📸 扫描相册中的 InBody 报告图片，使用 Vision OCR 自动识别
- 💾 使用 SwiftData 本地持久化，完全离线
- 📈 使用 Swift Charts 展示体重、体脂、肌肉量等趋势
- 🎨 绿色/白色健康风格，SwiftUI 原生 UI
- 🌏 中文界面

**技术栈**：SwiftUI · SwiftData · Swift Charts · Vision · PhotosUI · iOS 17+

## 快速开始

无需打开 Xcode，一条命令即可在模拟器中运行：

```bash
make run
```

首次运行会自动：
1. 用 [xcodegen](https://github.com/yonaskolb/XcodeGen) 生成 `MyBody.xcodeproj`
2. 启动 iPhone 16 模拟器
3. 构建、安装并启动 App

随时 `make help` 可列出全部命令。

## 依赖安装

| 工具 | 用途 | 安装 |
|---|---|---|
| `xcodegen` | 由 `project.yml` 生成 `.xcodeproj`（必需） | `brew install xcodegen` |
| `xcbeautify` | 美化 `xcodebuild` 日志（可选） | `brew install xcbeautify` |
| `ios-deploy` | 真机部署（Xcode 15+ 自带 `devicectl`，仅当 `devicectl` 不可用时回退使用） | `brew install ios-deploy` |
| `bundler` + fastlane | 截图、发版（首次会自动 `bundle install`） | `gem install bundler` |
| `gh` CLI | `make secrets-sync` 推送 GitHub Secrets | `brew install gh && gh auth login` |
| Pillow (Python) | `make gen` 自动生成 1024×1024 App Icon | `python3 -m pip install --user --break-system-packages Pillow` |

跑 `make deps` 可检测可选依赖是否缺失。

## 命令总览

按场景分类。每条命令的完整说明都在 [`Makefile`](Makefile) 里以 `## name: 描述` 形式注释，`make help` 会原样打印。

### 工程 / 构建

| 命令 | 作用 |
|---|---|
| `make help` | 列出全部命令 |
| `make gen` | 用 xcodegen 生成 `.xcodeproj`，自动注入 `DEVELOPMENT_TEAM` + 关闭 Metal Validation + 按需补 1024 App Icon |
| `make build` | 仅为模拟器构建（不安装、不启动） |
| `make clean` | 清空 `build/` 目录（派生数据 + archive + IPA） |
| `make resolve-team` | 打印解析出的 Apple Developer Team ID（调试用） |
| `make deps` | 检查 xcodegen / xcbeautify 等可选依赖 |

### 运行 / 调试

| 命令 | 作用 |
|---|---|
| `make run` | 生成 → 构建 → 启动模拟器 → 安装 → 启动（默认 iPhone 16） |
| `make run-mac` | "Designed for iPhone on Mac" 模式预构建，然后让 Xcode 触发 Cmd+R 启动（已规避 Metal 断言） |
| `make run_device` / `make run-device` | 在已配对的真机（USB / WiFi）上构建 → 安装 → 启动；多设备时用 `UDID=...` 指定 |
| `make xcode` | 生成工程并在 Xcode 中打开（Team 已预填，直接 Cmd+R） |
| `make logs` | 实时跟踪当前 App 的 `os_log`（Ctrl+C 退出） |
| `make stop` | 终止模拟器中的 App |

### 测试

| 命令 | 作用 |
|---|---|
| `make test` | 全量测试（unit + UI），自动挑选最新可用的 iPhone 模拟器 |
| `make test-unit` | 只跑 `MyBodyTests`（单元测试，快速迭代） |
| `make test-ocr-dump` | 只跑 `OCRServiceInBody230DumpTests` 诊断 dump；加 `VERBOSE=1` 看完整 xcodebuild 日志 |

### 截图 / 营销页

| 命令 | 作用 |
|---|---|
| `make screenshots` | 用 fastlane snapshot 自动生成 App Store 截图 → `fastlane/screenshots/<lang>/*.png` |
| `make market` | 启动本地 HTTP 服务器预览 `marketing/`；`SNAPSHOT=1` 先重拍截图，`PORT=8080` 指定端口 |

### 发版（App Store Connect）

| 命令 | 作用 |
|---|---|
| `make install_asc_key` | 半自动安装 ASC API Key（打开浏览器 → 监听 Downloads → 写 `.env`）；可用 `ASC_P8=/path/AuthKey.p8` 指定已下载的 Key |
| `make check_asc_env` | 校验 ASC API Key 三元组环境变量是否注入 |
| `make check_app_exists` | 用 API Key 查询 App 是否已在 ASC 建档 |
| `make register_bundle_id` | 在 Developer Portal 注册 Bundle ID（无需 Apple ID） |
| `make update_fastlane` | 24h 内增量升级 fastlane（`FASTLANE_SKIP_UPDATE_CHECK=1` 跳过） |
| `make screenshots_if_stale` | 按需重拍截图（源码变过 / 超过 `SNAPSHOT_MAX_AGE` 小时才重拍） |
| `make push_metadata` | 仅上传元数据 + 截图，不打包、不提审 |
| `make release_metadata_only` | `screenshots_if_stale` + `push_metadata` 的组合（等同旧版 `release` 行为） |
| `make release` | **一键发版**：校验 Key → 刷新截图 → 构建 IPA → 上传二进制 + 文案 + 截图 → 提审 → 审核通过后自动发布 |

### CI / Secrets

| 命令 | 作用 |
|---|---|
| `make secrets-sync` | 读取本地 `.env`，将其中非空变量通过 `gh` 推送为当前仓库的 GitHub Actions secrets（upsert，空值跳过） |
| `make secrets-list` | 列出当前仓库已有的 secret 名称（不显示值） |

## 推荐工作流

### 日常开发（改代码 → 看效果）

```bash
make run                # 起模拟器看效果
make logs               # 另开终端实时看日志（可选）
# 改完代码再次 make run 即可，无需打开 Xcode
```

修改了 `project.yml`（加文件 / 改 target 配置）后：

```bash
make gen                # 重新生成 .xcodeproj
make run
```

### 在真机上调试

```bash
# 一次性：连 USB 后在手机上「信任此电脑」；或在 Xcode → Devices and Simulators 勾选「Connect via network」
make run_device                                # 自动选可达设备
UDID=00008120-xxxxxxxxxxxxxxxx make run_device # 多台设备时手动指定
```

### 在 Mac 上运行（"Designed for iPhone on Mac"）

```bash
make run-mac            # 预构建后自动打开 Xcode 并触发 Cmd+R（可能需要授予辅助功能权限）
```

直接 `open MyBody.app` **不行** —— macOS LaunchServices 只认 Mac 原生包格式，必须借 Xcode 的 installd。`make run-mac` 在 `make gen` 时已把 Metal API / Shader Validation 关掉，避免 Vision 的 shared-storage 纹理触发 `synchronizeResource` 断言崩溃。

### 跑测试

```bash
make test-unit          # 日常 TDD：只跑单元测试
make test               # 全量（unit + UI），发版前 / CI 跑
make test-ocr-dump VERBOSE=1   # OCR 调参时看完整 OCR dump
```

### 截图 + 营销页本地预览

```bash
make screenshots                              # 用默认机型
SNAPSHOT_DEVICE="iPhone 16 Pro Max" make screenshots
make market                                   # 复用现有截图，打开 http://localhost:8000
make market SNAPSHOT=1 PORT=8080              # 重拍 + 自定义端口
```

### 发版（首次）

```bash
# 1. 一次性准备 ASC API Key（详见 docs/release.md）
make install_asc_key                          # 半自动：浏览器 → Downloads → 写 .env

# 2. 校验 + 确认 App 已在 ASC 建档
make check_asc_env
make check_app_exists                         # 若提示未建档，按提示去 ASC 手动新建

# 3. 一键发版
make release
```

### 发版（后续迭代）

```bash
make release                                  # 代码 / 资源有改 → 完整发版
SKIP_BINARY=1 make release                    # 只改文案 / 截图，复用 ASC 已有 build
SKIP_BINARY=1 SKIP_SCREENSHOTS=1 make release # 只改 metadata
make release_metadata_only                    # 不提审，只推文案 + 截图
make clean && make release                    # 改了图标 / 显示名 / Info.plist，必须清缓存
```

详细场景判断与所有开关说明见下方 [本地发版](#本地发版一键完成构建--上传--提审--自动发布make-release) 一节。

### 同步 Secrets 到 GitHub Actions

```bash
cp .env.example .env
$EDITOR .env                                  # 填真实值，空值会被跳过
make secrets-sync                             # upsert 到当前仓库
make secrets-list                             # 校验
```

## 环境变量与默认值

Makefile 顶部声明的变量都可通过命令行覆盖：`make run SIMULATOR_DEVICE="iPhone 15 Pro" CONFIG=Release`。

| 变量 | 默认 | 用途 |
|---|---|---|
| `SCHEME` | `MyBody` | Xcode scheme |
| `PROJECT` | `MyBody.xcodeproj` | 工程文件 |
| `SIMULATOR_DEVICE` | `iPhone 16` | `make run` 用的模拟器（找不到时自动 fallback 到首个可用 iPhone） |
| `CONFIG` | `Debug` | 构建配置；`make run CONFIG=Release` 切到 Release |
| `BUNDLE_ID` | `brickverse.MyBodyApp` | App Bundle ID |
| `PRODUCT_NAME` | `身记` | 产品名 / `.app` 文件名 |
| `DERIVED_DATA` | `build/DerivedData` | 派生数据路径 |
| `DEVELOPMENT_TEAM` | 自动解析 | 覆盖自动解析出的 Apple Developer Team |
| `UDID` | 自动检测 | `make run_device` 手动指定设备 |
| `PORT` | `8000` | `make market` HTTP 端口 |

`.env` 文件（若存在）会被 Makefile 自动 `include`，里面的 `KEY=VALUE` 会同时成为 make 变量和子进程环境变量 —— **不要加 `export` 前缀或引号**（参考 `.env.example`）。

发版相关开关（`SKIP_BINARY` / `SKIP_METADATA` / `SKIP_SCREENSHOTS` / `SKIP_SUBMIT` / `MANUAL_RELEASE` / `FORCE_SNAPSHOT` / `SKIP_SNAPSHOT` / `SNAPSHOT_MAX_AGE` / `SKIP_BUMP_BUILD`）详见下方表格。

## Team 与 Metal Validation 自动化

- **Team 自动注入**：`make gen` 会从 Xcode 的 `IDEProvisioningTeams` 偏好里自动挑选付费 Team（跳过 `Personal Team`），写进 `project.pbxproj`。再也不会出现 Xcode GUI 里 Team 为 `None` 导致签名失败的问题。
- **Metal API / Shader Validation**：生成 scheme 后自动改写 `<LaunchAction>`，把两项 Metal Validation 都置为 Disabled（避免在 "Designed for iPhone on Mac" 下 Vision 的 shared-storage 纹理触发 `synchronizeResource` 断言崩溃）。

## 自动生成 App Store 截图（详解）

```bash
make screenshots
# 指定机型：
SNAPSHOT_DEVICE="iPhone 16 Pro Max" make screenshots
# 需要 xcresult 排查时：
SNAPSHOT_RESULT_BUNDLE=1 make screenshots
```

- 由 `MyBodyUITests/SnapshotScreenshotsUITests.swift` 依次切换「首页 / 趋势 / 设置」Tab 完成截图。
- UI 测试通过启动参数 `-UITestScreenshots 1` 让 App 注入示例 `InBodyRecord`（`MyBody/Utilities/ScreenshotSampleData.swift`），保证首页和趋势页有真实的数据曲线。
- 产物路径：`fastlane/screenshots/zh-Hans/*.png`；`make market` 会自动把它们复制到 `marketing/screenshots/` 以供本地预览。

## 本地发版：一键完成构建 + 上传 + 提审 + 自动发布（`make release`）

从零到 App Store 只需要一条命令。`make release` 会自动:

- 生成 / 刷新 App Store 截图（`make screenshots`,按需重拍）
- 在 ASC 上建 / 复用 App 记录、草稿版本、审核联系方式
- 用 Release 配置构建 IPA（自动签名,ASC API Key 授权）
- 上传二进制到 App Store Connect 并等待处理完成
- 推送完整的文案、截图、分级信息与 App 审核信息
- 提交审核 + 勾选「审核通过后自动发布」

```bash
make release
```

**一次性准备**（只做一次,步骤见 [docs/release.md](docs/release.md)）:

1. 在 ASC 创建 API Key（Role = App Manager）,下载 `.p8` 文件
2. `cp .env.example .env` 并填入 API Key 三元组

之后每次发版只要 `make release`。全流程：

```
make release
├── check_asc_env          # 校验 API Key + .p8 路径
├── check_app_exists       # 核对 ASC 侧 App 记录
├── update_fastlane        # 24h 内增量升级 fastlane
├── gen                    # xcodegen 刷新 pbxproj(含 DEVELOPMENT_TEAM / Metal)
├── screenshots_if_stale   # 必要时用 fastlane snapshot 重拍
└── fastlane release
    ├── ensure_app_on_asc     # produce: 建 App、建草稿版本、建审核联系人(幂等)
    ├── increment_build_number_in_xcodeproj   # 使用时间戳 build number
    ├── build_app             # gym: Release 配置 → app-store IPA(-allowProvisioningUpdates)
    ├── upload_to_testflight  # pilot: 上传 IPA + 等 ASC 完成处理
    └── upload_to_app_store   # deliver: 文案 + 截图 + 分级 + 提审 + 自动发布
```

**可选开关**:

```bash
SKIP_SNAPSHOT=1    make release   # 不重拍截图
FORCE_SNAPSHOT=1   make release   # 强制重拍截图
SKIP_BINARY=1      make release   # 跳过构建 / 上传二进制(此时无法提审)
SKIP_METADATA=1    make release   # 跳过文案上传
SKIP_SCREENSHOTS=1 make release   # 跳过截图上传
SKIP_SUBMIT=1      make release   # 传完就停,不提审 / 不发布
MANUAL_RELEASE=1   make release   # 审核通过后改为手动发布
SKIP_BUMP_BUILD=1  make release   # 不自动递增 build number
```

#### 常用场景速查

| 场景 | 怎么跑 | 说明 |
|---|---|---|
| **首次发版 / 日常发版** | `make release` | 全自动:刷新截图 → 构建新 build → 上传 → 提审 → 自动发布。|
| **上一次只是 metadata / 分级 / 截图失败,二进制已上传** | `SKIP_BINARY=1 make release` | 复用 ASC 上那条处理好的 build,省掉 20 分钟左右的构建 + altool 上传。**适用前提:ASC 里最新 build 与当前代码一致。** |
| **改了 Swift 源代码 / Info.plist / xcodeproj** | `make release` | 必须重新打包一份新 build,不能 `SKIP_BINARY`,否则审核拿到的是旧代码。|
| **改了 bundle 里的资源/图标/ CFBundleDisplayName** | `make clean && make release` | 清掉 `build/` 里的旧 archive 和 DerivedData,避免 xcodebuild 命中旧缓存把老 icon/名字打进新 IPA。|
| **只想更新文案 / 截图,不想提审** | `make release_metadata_only` 或 `SKIP_SUBMIT=1 make release` | 前者不构建二进制;后者构建并上传 build 但不点提审。|
| **只改了 `fastlane/metadata/**.txt`(描述、关键词)** | `SKIP_BINARY=1 SKIP_SCREENSHOTS=1 make release` | 秒级完成,只走文案 diff。|
| **重拍截图但不发版** | `FORCE_SNAPSHOT=1 SKIP_BINARY=1 SKIP_SUBMIT=1 make release` | 也可直接 `make screenshots`。|
| **想先人工校稿,不自动发布** | `MANUAL_RELEASE=1 make release` | 审核通过后留在 "Pending Developer Release",去 ASC 手动点「发布」。|
| **Pipeline 挂在 "Waiting for build processing"** | 先到 ASC → TestFlight 确认 build 状态,再 `SKIP_BINARY=1 make release` | 通常是 ASC 后台慢,build 其实已经 ready。|
| **报错 `Missing required icon`** | `make clean && make release` | 重新生成 AppIcon(脚本会在 `gen` 阶段自动补)再打包。|
| **报错 `App name is already being used`** | 改 `fastlane/metadata/zh-Hans/name.txt`、`project.yml` 的 `PRODUCT_NAME` / `CFBundleDisplayName` 等一系列字段,再 `make clean && make release` | bundle 里的显示名变了,必须重新构建,不能 `SKIP_BINARY`。|
| **报错 `missing ... violenceCartoonOrFantasy ... pricing ... data usages`** | `SKIP_BINARY=1 make release` 再跑一次 | 分级配置 / 价格 / 隐私声明由 `make release` 自动写入,重跑即可。|
| **CI / 无人值守** | `make release` | Makefile 自动载入 `.env`,无需 `source`;脚本幂等,可重复触发。|

> 「需不需要 `make clean`」的判断口诀:只改了 `fastlane/metadata/`、`fastlane/screenshots/` 或 `fastlane/Fastfile` 的分支逻辑 → 不用 clean;只要碰到 `MyBody/`、`project.yml`、`Assets.xcassets/`、`Info.plist` → `make clean` 再 `make release`。

如果只想像旧版一样「只推文案 + 截图,不打包不提审」：

```bash
make release_metadata_only
```

**多语言支持计划**详见 [docs/i18n-roadmap.md](docs/i18n-roadmap.md)。当前 Primary Language = Simplified Chinese（不可改），已铺好 String Catalog 和 `developmentLanguage` 配置，未来加英文/日文只需 4 步增量操作。

## 同步 GitHub Actions Secrets（`make secrets-sync`）详解

当某个 GitHub Actions workflow 需要 token 时，用 `.env` 本地管理、`make secrets-sync` 一键推送到仓库 secrets：

```bash
# 1. 首次：从模板创建 .env（已 gitignore，不会被提交）
cp .env.example .env

# 2. 填入真实值
$EDITOR .env

# 3. 同步到当前仓库的 GitHub Actions secrets（upsert，空值跳过）
make secrets-sync

# 查看已有 secrets 名称（不显示值）
make secrets-list
```

- 依赖 `gh` CLI：`brew install gh && gh auth login`。
- `.env` 中**空值的 KEY 会跳过**，不会覆盖已有 secret；要真正删除请到 GitHub Settings 或用 `gh secret delete`。
- 支持的变量见 [.env.example](.env.example)。
- **Vercel DNS（[infra/terraform/](infra/terraform/README.md)）不需要 GitHub secrets**：plan/apply 跑在 HCP Terraform 上，Vercel token 配在 HCP workspace 的 Variables 里。`.env` 里的 `VERCEL_API_TOKEN` 仅供本地 `terraform plan` 使用。

## 项目结构

```
MyBody/
├── Models/           # SwiftData 模型 + 枚举（InBodyRecord, ScanRange, ...）
├── Services/         # OCRService, PhotoScanService
├── ViewModels/       # @Observable MVVM 视图模型
├── Views/
│   ├── Home/         # 首页 + 最新报告
│   ├── Trends/       # Swift Charts 趋势图
│   ├── Detail/       # 报告详情与编辑
│   ├── Scan/         # 相册扫描、确认、字段解析
│   └── SettingsView.swift
└── Resources/        # Assets.xcassets, Info.plist
```

## 设置项

- **扫描范围**：最近 30 天 / 90 天（默认）/ 一年 / 全部 — 限制扫描的照片数，减少耗时
- **iCloud 照片**：默认关闭；开启后会下载 iCloud 中未缓存的原图参与识别

## 开发说明

- `project.yml` 是工程定义源，修改后执行 `make gen` 重新生成 `.xcodeproj`
- Bundle ID：`brickverse.MyBodyApp`
- 最低部署版本：iOS 17.0
- 在 "My Mac (Designed for iPhone)" 上运行，推荐使用 `make run-mac`；已自动关闭 Metal API / Shader Validation，避免 Vision 的模拟器/Mac 断言崩溃

## License

[MIT](LICENSE)
