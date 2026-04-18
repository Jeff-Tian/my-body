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
brew install xcbeautify   # 可选，用于美化构建日志
```

### 常用命令

| 命令 | 说明 |
|---|---|
| `make run` | 生成工程 → 构建 → 启动模拟器 → 安装 → 运行 |
| `make build` | 仅构建 |
| `make gen` | 仅运行 xcodegen 生成 Xcode 工程 |
| `make logs` | 实时跟踪 App 日志 |
| `make stop` | 终止模拟器中的 App |
| `make clean` | 清理 `build/` 目录 |
| `make help` | 查看全部命令 |

### 覆盖默认值

```bash
make run SIMULATOR_DEVICE="iPhone 15 Pro"
make run CONFIG=Release
```

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
- Bundle ID：`brickverse.MyBody`
- 最低部署版本：iOS 17.0
- ⚠️ 不要在 "My Mac (Designed for iPhone)" 运行 — Mac Catalyst 模式下 Metal 验证会误报崩溃；请使用 iPhone 模拟器或真机

## License

[MIT](LICENSE)
