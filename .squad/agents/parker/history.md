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

- 2026-05-24: New single-photo import path landed via HomeView FAB Menu + `SinglePhotoImportView` + `ScanViewModel.startSingleImport`. Test surface to consider: PHAsset fast path (with identifier) vs Data fallback (assetIdentifier: nil, limited-access albums); new sheet UI on HomeView.

### 2026-05-24: Heads-up — OCR axis-scale misread fixture incoming
Ash diagnosed an `OCRService.findValue` first-match bug on InBody 230 `IMG_2245.HEIC` (parses weight as 55 instead of 68.1 kg). Once Jeff approves Plan A/B, you'll be asked to author a regression fixture: dump the `[TextBox]` JSON for that image and lock `weight=68.1 / skeletalMuscle=31.7 / bodyFatMass=12.0` as a snapshot test. See decisions.md entry "InBody 横向柱状图坐标轴刻度被误读为字段值".
