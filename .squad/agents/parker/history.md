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

### 2026-05-24: OCR regression fixture harness scaffolded
- Created `MyBodyTests/Fixtures/InBody/README.md` + `.gitkeep` and `MyBodyTests/Services/OCRServiceInBody230Tests.swift`. Test skips with `XCTSkip` when the fixture image is missing, so it can land today and activate once Jeff drops `inbody230-sample-01.heic` into the fixtures directory.
- **OCR entry point used:** `OCRService.parseReport(from: UIImage) throws -> ParsedReport` — accepts `UIImage` directly, so HEIC/JPG/PNG all work via `UIImage(data:)`. Test bundle resource lookup tries `heic|HEIC|jpg|jpeg|png` in that order.
- **Expected fields asserted (5 numeric + 1 date):** `weight=68.1`, `skeletalMuscle=31.7`, `bodyFatMass=12.0`, `totalBodyWater=41.2`, `leanBodyMass=56.1` (all ±0.05), plus `scanDate=2026-05-22` via `Calendar.dateComponents`. `height/age/gender` from the task description are NOT currently surfaced by `ParsedReport`, so they're documented as out-of-scope in the README and not asserted.
- **Project state caveat:** `project.yml` only declares `MyBody` and `MyBodyUITests` (UI testing bundle). There is no `MyBodyTests` unit test target. Per Coordinator's "do not invent targets" rule, I did not edit `project.yml` — instead the README ships the exact YAML snippet Jeff must add (target block + scheme `test.targets` entry) and the regen command (`make project` / `xcodegen generate`). Until that lands, the test file compiles standalone but is not picked up by any scheme.
- **Why `XCTSkip` not `XCTFail`:** lets the harness be checked in immediately without breaking CI; activates the moment Jeff drops the desensitized image in. Standard fixture-driven pattern from charter.
- **Did NOT run `make build`:** new files are not in any Xcode target yet, so the build is unchanged. Skipping avoided spending CI time on a no-op verification.

- 2026-05-24: Your `IMG_2245.HEIC` InBody 230 regression fixture is now genuinely green (5/5 fields pass). Plan A (decimal-space rejoin) + Plan B (competitorRight column cap) + Plan C (cy-closest range selection) all landed in `OCRService.swift` via Ash. The OCR dump test (`OCRServiceInBody230DumpTests`, env-guarded `OCR_SKIP_DUMP=0`) is the canonical entry point for future OCR misreads — eyeball boxes first, edit second.
