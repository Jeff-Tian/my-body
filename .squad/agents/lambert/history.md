# Project Context

- **Owner:** Jeff Tian
- **Project:** my-body — iOS native app that scans the photo library for InBody body composition reports, extracts the data, syncs to the user's Apple Account (iCloud), and writes results into Apple Health (HealthKit).
- **Stack:** Swift, SwiftUI, Vision (OCR), PhotosUI/PHPicker, HealthKit, CloudKit / iCloud
- **Created:** 2026-05-15

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-05-24 — Single-photo import (HomeView FAB Menu)
- **PhotosPicker + PHAsset dedup:** When `PhotosPicker(photoLibrary: .shared())` is used, the resulting `PhotosPickerItem.itemIdentifier` returns the PHAsset `localIdentifier`. This lets us reuse the existing batch-scan pipeline (which dedups on `photoAssetIdentifier`) for picker-selected photos — no schema change required.
- **Menu-based FAB pattern:** When adding an alternative entry point to an existing primary action, prefer `Menu` over a confirmation dialog. The FAB label stays the same ("导入报告"), and tapping reveals two options ("扫描相册" / "选择单张照片"). Discoverable, system-native, doesn't break muscle memory.
- **Dual-path import in ScanViewModel.startSingleImport:** Fast path uses PHAsset (reuses `parseNextPhoto`, preserves dedup + creation-date fallback). Slow path falls back to raw `Data` via `item.loadTransferable` when `itemIdentifier` is nil (limited-access album scenarios) — saves with `assetIdentifier: nil`, scanDate left blank for user fix-up.
- **SinglePhotoImportView:** Standalone sheet that hosts only the parsing UI (mirror of PhotoScanView's `parsingView`) — keeps PhotoScanView untouched and avoids mixing batch + single concerns in one view. Owns its own `ScanViewModel` instance; dismisses on `viewModel.batchFinished`.
- **xcodegen auto-pickup:** `project.yml` uses `sources: [path: MyBody]`, so new `.swift` files under `MyBody/` are auto-included after `make gen` — no manual project edits.

## Codebase (discovered 2026-05-15)

- iOS 17+ Xcode project at root: `MyBody.xcodeproj` (generated via xcodegen — `project.yml`).
- Source: `MyBody/` (MyBodyApp.swift, Models, Services, ViewModels, Views, Utilities).
- Persistence: **SwiftData** (currently offline-only per README — "完全离线"). CloudKit/iCloud sync is a planned future capability, not yet implemented.
- Already implemented: OCR pipeline (`MyBody/Services/OCRService.swift`), HealthKit integration (`MyBody/Services/HealthKitService.swift`), photo scanning (`PhotoScanService.swift`), OCR learning corrections (`OCRCorrection.swift` + `OCRCorrectionStore.swift`).
- Build: `make run` (simulator), `make run_device`, `make gen` (xcodegen), `make screenshots` (fastlane), `make release`.
- Fastlane for App Store screenshots + release automation.
- Localization: `MyBody/Localizable.xcstrings` (zh-Hans primary per README).
- Roadmaps: `docs/ocr-learning-roadmap.md`, `docs/i18n-roadmap.md`, `docs/release.md`.

## Learnings

### 2026-05-24 — 重新识别 (re-OCR) 按钮 (DetailView)

- **Task:** 在报告详情页 toolbar 加 "重新识别" 按钮：确认 alert → 进度遮罩 → 成功 banner / 错误 alert。
- **File changed:** `MyBody/Views/Detail/DetailView.swift` (+~95 行净增)
- **Key field name:** 原始照片标识用 `record.photoAssetIdentifier`（spawn 提示里的 `assetId` 不存在）。
- **Button placement:** `topBarTrailing` 内排列为「重新识别 → 编辑 → 删除」，从自动→手动→破坏性。
- **Disable rules:** 无 `photoAssetIdentifier` 或 `isReparsing` 时禁用；执行中也禁用 edit / delete。
- **Visual style:** `ultraThinMaterial` 圆角进度遮罩；`Color.appGreen` capsule banner；`move(.top).combined(.opacity)` 过渡。
- **Error handling pattern:** 先 `as? ScanViewModel.ReparseError`（已是 `LocalizedError`，中文文案完整），再 Photos 域兜底，最后 `localizedDescription`。
- **Coordination:** Ash 并行交付 `ScanViewModel.reparseExistingReport(_:context:ocrService:) async throws -> OCRService.ParsedReport`；UI 用 `_ = try await` 丢弃返回值。
- **Test status:** `make test-unit` 通过（2 tests, 0 failures）。

## 2026-05-24: Trends 体重→Health 写入入口 — UI survey (Phase 1)

- TrendsView 的 metric 选择是 **horizontal ScrollView + 胶囊 Button**，不是 Picker；状态在 `TrendsViewModel.selectedMetric: MetricType`（@Observable）。判定「当前选中体重」= `viewModel.selectedMetric == .weight`，无需新增 binding。
- `HealthKitService.shared.saveWeight(_:date:)` + `requestAuthorization()` 已存在；`SettingsView` 已有「同步体重到健康」总开关（控制自动同步）。本入口语义是「手动补写历史」，应独立于全局开关。
- UI 推荐：**NavigationBar toolbar item**（`heart.text.square`），仅当 selectedMetric==.weight 时显示。优于 chart 下方 section（避免切换 metric 时滚动跳动）和 History row swipe（与 metric 条件不匹配）。
- 已落 design note 到 `.squad/decisions/inbox/lambert-weight-health-ui-options.md`，含 7 个 i18n key (zh-Hans + en)、a11y 注意点、4 个待 Ripley 决定的开放问题（写入范围 / 去重 / 错误反馈 / 进度）。
- 等 Ripley 架构提案合并后进 Phase 2（实现 toolbar button + confirm dialog + 反馈）。

## 2026-05-24 — Team note: Trends Weight → Health Phase 1
Cross-agent Phase 1 planning landed in `.squad/decisions.md` (4 entries dated 2026-05-24). Before any Phase 2 implementation:
- Read Ripley's architecture proposal (entry point, scope, dedup strategy, auth flow).
- Read Ash's HealthKitService survey + proposed `writeWeightSamples(_:)` API + 2 open metadata questions.
- Read Lambert's UI options (Toolbar item A chosen) + 7 i18n keys to add.
- Read Parker's test plan + `HealthKitWriting` protocol seam + `MyBodyTests` target blocker.
Two open arbitrations (dedup mechanism, `HKMetadataKeyWasUserEntered`) must be resolved by Ripley before Ash freezes the API.

## 2026-05-24 — Trends 体重→健康 写入 UI (Phase 2)

实现了 `TrendsView` 的 NavBar 工具栏「写入健康」按钮 + 范围选择 + 进度 + 结果/错误对话框。Ash 的 `writeWeightSamples(_:) async throws -> HealthKitWriteResult` 已在 `HealthKitService.swift` 落地（确认存在 `written/skippedInvalid/skippedDuplicate/failed` 四字段；构造器默认全 0；`failed: [(UUID, Error)]`）。

**关键模式 / 复用价值**:
- **`WeightHealthWriteController` 独立 `@Observable`**: 把工具栏交互、状态机、Service 调用从 `TrendsView` 抽出。`TrendsView.body` 只多了一个 `.toolbar` + 一个 `.modifier(...)`。将来 Body Fat / 其它指标做同样的 HK 写入只需复制此 controller。
- **`recordsForRange: @escaping (Range) -> [InBodyRecord]`**: 控制器不依赖 `TrendsViewModel` / SwiftData / `TimeFilter`，外部注入选择器闭包。`onAppear` 里捕获 `viewModel.records` / `viewModel.filteredRecords` 做范围解析。
- **`ViewModifier` 收纳 dialog/overlay/alert**: 4 个 modifier 链堆在 body 里会很难读，抽到 `WeightHealthWriteOverlay: ViewModifier` 之后只剩一行 `.modifier(...)`。
- **`Phase` 枚举不要写 `Equatable`**: 因为 `case error(message: String, isAuthDenied: Bool)` + `case result(HealthKitWriteResult)` 间接含 `Error`（non-Equatable）和元组（不能合成 Equatable）。改用 helper（`isWriting` / `resultForDisplay`）做派生状态。
- **工具栏条件 `selectedMetric == .weight && HealthKitService.shared.isAvailable`**: 切到其它指标自动隐藏；模拟器上 HealthKit 不可用时也隐藏，避免点了报错。
- **`UIApplication.openSettingsURLString` 深链系统设置**: `HealthKitError.notAuthorized` 时按钮直接打开本 app 的设置页（含「健康」开关）。
- **`Localizable.xcstrings` 用 zh-Hans 原文做 key**: 项目源语言 `zh-Hans`，代码里直接写中文（如 `Text("写入健康")`），xcstrings 只补 `en` localization 即可，无需 zh-Hans 条目。19 个新 key 已加。

**坑**:
- 第一次构建报 `HealthKitWriteResult` 构造器参数顺序错 —— 字段定义顺序是 `written / skippedInvalid / skippedDuplicate / failed`，不是 `written / skippedDuplicate / skippedInvalid / failed`（我按 Ash 早先 survey 写的）。`HealthKitWriteResult()` 全默认值最稳。
- `presenting:` modifier 要求 `Identifiable`，所以 error alert 用了私有 `ErrorPayload` 包装一下 `(message, isAuthDenied)`。

**文件**:
- `MyBody/Views/Trends/TrendsView.swift` — 加 toolbar / state / onAppear 初始化 controller / `.modifier`
- `MyBody/Views/Trends/WeightHealthWriteSheet.swift` — 新文件: controller + overlay modifier + ProgressOverlay + FailedRecordsSheet
- `MyBody/Localizable.xcstrings` — 19 个 EN 翻译

**构建状态**: `make build` 通过 ✅

## 2026-05-24 — Phase 2 shipped (team note)
Trends「写入健康」Phase 2 complete. My deliverable: `WeightHealthWriteController` + overlay modifier + TrendsView toolbar + 19 i18n keys. Post-build fix: corrected `HealthKitWriteResult` field order + `Phase: Equatable`. Pattern is reusable for future HK writes (body fat, water, etc.). Ash shipped the service; Parker shipped tests.

### 2026-05-24 — PhotoScanView 批量「重新识别」prompt
- 在 `MyBody/Views/Scan/PhotoScanView.swift` 给批量导入收尾接入「是否对去重跳过的报告重新识别」alert。
- 触发条件：`viewModel.batchFinished == true` 且 `viewModel.duplicateAssetIds.count > 0`；否则维持原行为直接 `dismiss()`。
- 复用 DetailView reparse 的视觉栈：`Color.black.opacity(0.35)` 全屏 dim + `.ultraThinMaterial` 圆角卡片 + `ProgressView().tint(.white)`；进度文案优先用 `viewModel.reparseIndex / reparseTotal`，未启动时退化为「重新识别中…」。
- 结果 banner 沿用 capsule 风格：成功 `appGreen` + checkmark；含失败 `appOrange` + warning triangle，2.5s 后自动 `dismiss()`。
- `cancel` 按钮在 `isReparsing` 期间禁用，避免用户中途丢上下文。
- Ash 的 ViewModel API 已落地（`duplicateAssetIds: [String]`、`reparseIndex/reparseTotal`、`reparseDuplicateRecords() -> (succeeded, failed, errors)`），UI 直接绑。
- 教训：嵌套于 `View` 内的 `private struct ReparseSummary` 在 file-private 的 `BatchReparseBanner` 里不可访问，必须显式 `fileprivate` —— Swift 嵌套类型默认沿用包含类型的可见性。
