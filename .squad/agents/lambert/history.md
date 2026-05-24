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
