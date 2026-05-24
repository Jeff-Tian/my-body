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

- 2026-05-24: New single-photo import path landed (`ScanViewModel.startSingleImport(itemIdentifier:fallbackImageData:)` + `parseSingleDataImage`). PHAsset fast path reuses existing OCR pipeline (dedup intact); Data fallback path bypasses PHAsset (assetIdentifier nil) — relevant for any OCR/learning-correction work that assumes a non-nil asset id.

- 2026-05-24: **InBody 230 横向柱状图轴刻度被误读为字段值(诊断)**。`OCRService.findValue` (MyBody/Services/OCRService.swift:268-367) 用 `rowFiltered.first(where: expected.contains)` 在 label 右侧同行第一个落在期望区间的数字胜出。InBody 230 每行布局是 `[label] [axis ticks 40 55 70 85 ...] [实测值 68.1 kg] [正常范围 X.X~Y.Y]`,轴刻度整数全部落在宽松的 `expected` 区间内(weight 20...250 / skeletalMuscle 5...60 / bodyFatMass 1...100),所以 **第一个轴刻度就胜出**,实测值永远拿不到。佐证:Jeff 看到的 55 / 60 / 40 全是整数;实测值 68.1 / 31.7 / 12.0 全是小数。
  - 修复路径(诊断 written to `.squad/decisions/inbox/ash-inbody-ocr-axis-scale-misread.md`):
    1. **方案 A**:`findValue` 行内候选改成评分(含单位 +大、小数 +中、box 高度 +中、最右侧 +小、等距整数群 -大),取最高分。
    2. **方案 B**:扫描行内被 `isPureRange` 过滤的"正常范围"box(如 `53.4~72.3`),按 `cy` 配对到 label,把字段 expected 临时收紧到 `low×0.5 ... up×1.5`,把远端轴刻度(115/130/145)直接砍掉。
    3. 加 Parker 回归 fixture:用 `IMG_2245.HEIC` 的 OCR `[TextBox]` dump 锁住 `weight=68.1 / skeletalMuscle=31.7 / bodyFatMass=12.0`。
  - 经验教训:**`expected` 区间太宽 + first-match-wins 是 OCR 字段解析的常见反模式**。宽区间为机型差异留余地是对的,但选择器必须从"区间过滤 + first" 升级为"区间过滤 + 候选评分"。下次设计任何 spatial-OCR 字段解析时直接上评分函数,别再用 first。
  - 受影响字段范围:所有带横向 bar chart 的主指标(weight / skeletalMuscle / bodyFatMass / 可能还有 totalBodyWater / bodyFatPercent / leanBodyMass)。BMI / WHR / BMR / 内脏脂肪等级等纯文本字段不受影响。
