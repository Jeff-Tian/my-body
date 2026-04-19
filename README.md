# 我的身体 (MyBody)

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

### 依赖

```bash
brew install xcodegen
brew install xcbeautify    # 可选，用于美化构建日志
brew install ios-deploy    # 仅 `make run_device` 需要（或 npm install -g ios-deploy）
gem install bundler        # 仅 `make screenshots` 需要（首次会自动 bundle install fastlane）
```

### 常用命令

| 命令 | 说明 |
|---|---|
| `make run` | 生成工程 → 构建 → 启动模拟器 → 安装 → 运行 |
| `make run_device` | 在连接的真实 iPhone 上构建 → 安装 → 启动（自动解析 Team 与 UDID） |
| `make run-mac` | 以 "My Mac (Designed for iPhone)" 模式构建，并通过 Xcode 启动（Team/Metal Validation 已自动处理）|
| `make xcode` | 生成工程并在 Xcode 中打开（Team 已预填，直接 Cmd+R） |
| `make build` | 仅构建（模拟器） |
| `make gen` | 仅运行 xcodegen 生成 Xcode 工程（自动注入 `DEVELOPMENT_TEAM` + 关闭 Metal API / Shader Validation） |
| `make resolve-team` | 打印自动解析出的 Apple Developer Team ID（调试用） |
| `make logs` | 实时跟踪 App 日志 |
| `make stop` | 终止模拟器中的 App |
| `make clean` | 清理 `build/` 目录 |
| `make screenshots` | 使用 fastlane snapshot 在模拟器中自动生成 App Store 截图（输出 `fastlane/screenshots/<lang>/*.png`） |
| `make release` | 一键发版:构建 IPA → 上传二进制 + 文案 + 截图 → 提审 → 审核通过后自动发布 |
| `make market` | 启动本地 HTTP 预览 `marketing/` 页面；加 `SNAPSHOT=1` 先重跑截图 |
| `make secrets-sync` | 读取本地 `.env`，将其中非空变量通过 `gh` CLI 同步为当前仓库的 GitHub Actions secrets（upsert，空值跳过）|
| `make secrets-list` | 列出当前仓库已配置的 GitHub Actions secrets 名称（不显示值）|
| `make deps` | 检查 xcodegen / xcbeautify 等可选依赖 |
| `make help` | 查看全部命令 |

### 覆盖默认值

```bash
make run SIMULATOR_DEVICE="iPhone 15 Pro"
make run CONFIG=Release

# 如果自动解析的 Team ID 不对，可手动指定：

# 真机运行时手动指定设备 UDID（多台设备同时连接时）：
UDID=00008120-xxxxxxxxxxxxxxxx make run_device
DEVELOPMENT_TEAM=XXXXXXXXXX make gen
```

### Team 与 Metal Validation 自动化

- **Team 自动注入**：`make gen` 会从 Xcode 的 `IDEProvisioningTeams` 偏好里自动挑选付费 Team（跳过 `Personal Team`），写进 `project.pbxproj`。再也不会出现 Xcode GUI 里 Team 为 `None` 导致签名失败的问题。
- **Metal API / Shader Validation**：生成 scheme 后自动改写 `<LaunchAction>`，把两项 Metal Validation 都置为 Disabled（避免在 "Designed for iPhone on Mac" 下 Vision 的 shared-storage 纹理触发 `synchronizeResource` 断言崩溃）。

### 自动生成 App Store 截图

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

### 本地发版：一键完成构建 + 上传 + 提审 + 自动发布（`make release`）

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

如果只想像旧版一样「只推文案 + 截图,不打包不提审」：

```bash
make release_metadata_only
```

**多语言支持计划**详见 [docs/i18n-roadmap.md](docs/i18n-roadmap.md)。当前 Primary Language = Simplified Chinese（不可改），已铺好 String Catalog 和 `developmentLanguage` 配置，未来加英文/日文只需 4 步增量操作。

### 同步 GitHub Actions Secrets（`make secrets-sync`）

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
