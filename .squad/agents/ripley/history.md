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
