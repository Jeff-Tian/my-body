# Project Context

- **Owner:** Jeff Tian
- **Project:** my-body — iOS native app that scans the photo library for InBody body composition reports, extracts the data, syncs to the user's Apple Account (iCloud), and writes results into Apple Health (HealthKit).
- **Stack:** Swift, SwiftUI, Vision (OCR), PhotosUI/PHPicker, HealthKit, CloudKit / iCloud
- **Created:** 2026-05-15

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

## Codebase (discovered 2026-05-15)

- iOS 17+ Xcode project at root: `MyBody.xcodeproj` (generated via xcodegen — `project.yml`).
- Source: `MyBody/` (MyBodyApp.swift, Models, Services, ViewModels, Views, Utilities).
- Persistence: **SwiftData** (currently offline-only per README — "完全离线"). CloudKit/iCloud sync is a planned future capability, not yet implemented.
- Already implemented: OCR pipeline (`MyBody/Services/OCRService.swift`), HealthKit integration (`MyBody/Services/HealthKitService.swift`), photo scanning (`PhotoScanService.swift`), OCR learning corrections (`OCRCorrection.swift` + `OCRCorrectionStore.swift`).
- Build: `make run` (simulator), `make run_device`, `make gen` (xcodegen), `make screenshots` (fastlane), `make release`.
- Fastlane for App Store screenshots + release automation.
- Localization: `MyBody/Localizable.xcstrings` (zh-Hans primary per README).
- Roadmaps: `docs/ocr-learning-roadmap.md`, `docs/i18n-roadmap.md`, `docs/release.md`.

### 2026-05-24: Architecture decision pending — OCR parsing refactor
Ash proposed Plan A (per-row candidate scoring inside `OCRService.findValue`) + Plan B (parse printed "正常范围" box to tighten per-field `expected`). Both are local to `OCRService`, no public API change. Review for architectural fit (esp. how this interacts with Phase 5 personalization in `docs/ocr-learning-roadmap.md`) before implementation lands. Details: decisions.md entry "InBody 横向柱状图坐标轴刻度被误读为字段值".

- 2026-05-24: **OCR scoring approach landed inline in `OCRService`** (Ash). Plan A (candidate scoring: unit +4 / decimal +2 / height +2 / rightmost +1 / equidistant-int-group -5) + Plan B (printed-range narrowing via `parsePrintedRange`). Build passes. Architecture call: kept inside `OCRService` rather than extracting `OCRScorer` — only one consumer, surgical. Pure-functional shape preserved if extraction needed later. **Pending Jeff:** add `MyBodyTests` target to `project.yml` so Parker's regression harness (`MyBodyTests/Services/OCRServiceInBody230Tests.swift`) can run.

## Learnings

### Xcode 26.5 + missing iOS 26.5 runtime — test action blocked
- Patched `test` / `test-unit` Makefile targets to pick the newest *installed* iOS runtime via `xcrun simctl list runtimes -j` + python3 (deterministic, sorts by version tuple, falls back to creating a sim if none exists). Echoes UDID/name/version.
- Pass `-destination "platform=iOS Simulator,id=<UDID>"` for reliability.
- **Caveat (Xcode 26.5):** `xcodebuild test` enforces SDK↔runtime build-version pairing. iPhoneSimulator 26.5 SDK (build 23F73) requires iOS 26.5 runtime; rejects iOS 26.4.1 (23E254a) with "No simulator runtime version from [...] available to use with iphonesimulator SDK version 23F73". `make run` works because `build` action is lenient. Resolution requires either installing iOS 26.5 runtime (~6GB) or a side-by-side older Xcode.
- 26.4 and 26.4.1 share runtime identifier `com.apple.CoreSimulator.SimRuntime.iOS-26-4`; sorting by version string still selects the 26.4.1 record first.

### 2026-05-24: 中文 PRODUCT_NAME 导致 @testable import 失败 — PRODUCT_MODULE_NAME 锁定
- `MyBody` target 的 `PRODUCT_NAME` 是中文 "身记"。Swift 模块名默认由 PRODUCT_NAME 派生为 C 标识符，中文字符没有合法映射 → 测试 target 报 `error: unable to resolve module dependency: 'MyBody'`。
- 修复：在 `project.yml` 的 `MyBody.settings.base` 显式加 `PRODUCT_MODULE_NAME: MyBody`。bundle/二进制名仍是中文，只锁模块标识符。
- 验证：`make gen` → `make test-unit` 编译通过，测试在 iOS 26.5 模拟器上运行；`make build` 仍 `Build Succeeded`。
- 启示：任何非 ASCII PRODUCT_NAME 上线测试 target 时都要先显式 PRODUCT_MODULE_NAME，否则 `@testable import` 必炸。

### 2026-05-24: Trends → Apple Health weight write — architected
Proposed Trends 页面在选中 weight 时通过 toolbar 「写入健康」+ confirmation dialog 触发批量写入。**关键架构决定：去重用 HealthKit metadata key `com.jefftian.mybody.recordID = UUID` + 写前 HKSampleQuery**，**不**在 `InBodyRecord` 上增加 `syncedSampleIDs` 字段。理由：HealthKit 自身是真相源，跨设备/重装/iCloud 同步天然一致；不污染 SwiftData schema；Scan/Edit 现有写入路径也能回填同一 key 向后兼容。新 API `saveWeightIfNew(_:date:recordID:)` 返回是否真写入，调用方可统计 written/skipped/failed。授权延迟到首次点击（非进入 Trends 时），denied 跳系统设置。Entitlement 已 OK（empty `healthkit.access` 数组对 bodyMass 正确，仅临床记录类需要项）。提案文件：`.squad/decisions/inbox/ripley-weight-health-write-proposal.md`。下一步 Lambert 实现 UI/VM、Ash 实现 dedup API、Parker 加 mock store 测试。

## 2026-05-24 — Team note: Trends Weight → Health Phase 1
Cross-agent Phase 1 planning landed in `.squad/decisions.md` (4 entries dated 2026-05-24). Before any Phase 2 implementation:
- Read Ripley's architecture proposal (entry point, scope, dedup strategy, auth flow).
- Read Ash's HealthKitService survey + proposed `writeWeightSamples(_:)` API + 2 open metadata questions.
- Read Lambert's UI options (Toolbar item A chosen) + 7 i18n keys to add.
- Read Parker's test plan + `HealthKitWriting` protocol seam + `MyBodyTests` target blocker.
Two open arbitrations (dedup mechanism, `HKMetadataKeyWasUserEntered`) must be resolved by Ripley before Ash freezes the API.
