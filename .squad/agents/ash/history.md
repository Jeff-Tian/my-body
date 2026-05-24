# Project Context

- **Owner:** Jeff Tian
- **Project:** my-body — iOS native app that scans the photo library for InBody body composition reports, extracts the data, syncs to the user's Apple Account (iCloud), and writes results into Apple Health (HealthKit).
- **Stack:** Swift, SwiftUI, Vision (OCR), PhotosUI/PHPicker, HealthKit, CloudKit / iCloud
- **Created:** 2026-05-15

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-05-24: InBody 230 OCR — three diagnostic patterns (Patterns A/B/C)

Captured during the InBody 230 misread fix session. Single diagnostic-first session that fixed all 4 remaining field misreads (weight, sm, bfm, tbw, lbm now all pass `OCRServiceInBody230Tests`).

- **Pattern A — Vision splits decimals with a literal space.** Vision sometimes returns `"68. 1kg"` / `"56. 1 kg"` instead of `"68.1kg"`. The numeric regex inside `primaryNumber` would then capture only `68` and drop `.1`. **Fix:** rejoin `(\d)\.\s+(\d)` → `$1.$2` at the very top of `primaryNumber`, BEFORE key removal / unit stripping. Always normalize text first, then parse numbers.

- **Pattern B — same-row FieldSpec labels bleed into each other.** On InBody 230, `身体水分含量` (tbw, cy≈0.657) and `去脂体重` (lbm, cy≈0.653) sit on the same printed row. Without a column cap, tbw's pool absorbs lbm's value box (and vice-versa). **Fix:** at the top of the per-label loop, compute `competitorRight` = `min(left)` of any OTHER FieldSpec's label box that's right-of-this-label AND within rowTol; then add `.filter { $0.left < competitorRight }` to BOTH `rowCandidates` (no-range) AND `rowNumbersIncludingRange` (includes-range) chains. Competitor labels supplied via new `competitorKeys` parameter on `findValue`, populated from `specs.flatMap{$0.keys}` minus current spec's keys at call site.

- **Pattern C — `rowRange` picked the wrong adjacent reference range via `.first`.** On the bfm row (`体脂肪` cy=0.695), both `7.6~15.1` (bfm range, cy=0.688) and `26.8~32.7` (body-water range, cy=0.719) fall within rowTol (0.026). `.first` happened to pick `26.8~32.7`, narrowing expected to `[13.4, 49.05]` — which EXCLUDES the real value `12.0` but INCLUDES axis tick `40`. **Fix:** sort isPureRange candidates by `abs($0.cy - label.cy)` ascending, then take `.first`. Closest-by-row-distance wins.

- **Meta-lesson — always dump raw boxes BEFORE bumping scoring weights.** All three patterns were invisible to the old "tweak weights" approach. Capturing the 216-box dump (`OCRServiceInBody230DumpTests`, env-guarded `OCR_SKIP_DUMP`) was what made the diagnoses possible. Coordinator rule "Do NOT just bump scoring weights and pray" earned its keep — every fix here is a TARGETED edit driven by actual box geometry, not a heuristic tuning knob.

### 2026-05-24: Tooling traps to remember

- **xcbeautify 3.2.1 swallows test stdout** and reports crashes as `Executed 0 tests`. Bypass: pipe xcodebuild raw output through `grep`/`tail` directly, no `xcbeautify`. Or read `xcresulttool` from the `.xcresult` bundle.
- **`String(format: "%s", swiftString)` CRASHES on non-ASCII text.** Vision returns UTF-8 Chinese strings. Always use `%@` for Swift String formatting.
- **Swift `Double.truncatingRemainder(dividingBy: 1)` returns 0 for `12.0`** — so the "has decimal" bonus in scoring fires `(text.contains(".") && value % 1 != 0)`, but `12.0 % 1 == 0`. Not a bug — just remember when scoring tied candidates.

## Codebase (discovered 2026-05-15)

- iOS 17+ Xcode project at root: `MyBody.xcodeproj` (generated via xcodegen — `project.yml`).
- Source: `MyBody/` (MyBodyApp.swift, Models, Services, ViewModels, Views, Utilities).
- Persistence: **SwiftData** (currently offline-only per README — "完全离线"). CloudKit/iCloud sync is planned, not yet implemented.
- Already implemented: OCR pipeline (`MyBody/Services/OCRService.swift`), HealthKit (`HealthKitService.swift`), photo scanning (`PhotoScanService.swift`), OCR learning corrections (`OCRCorrection.swift` + `OCRCorrectionStore.swift`).
- Build: `make run` (simulator), `make run_device`, `make gen` (xcodegen), `make screenshots` (fastlane), `make release`.
- Localization: `MyBody/Localizable.xcstrings` (zh-Hans primary).
- Roadmaps: `docs/ocr-learning-roadmap.md`, `docs/i18n-roadmap.md`, `docs/release.md`.

- 2026-05-24: New single-photo import path landed (`ScanViewModel.startSingleImport(itemIdentifier:fallbackImageData:)` + `parseSingleDataImage`). PHAsset fast path reuses existing OCR pipeline (dedup intact); Data fallback path bypasses PHAsset (assetIdentifier nil) — relevant for any OCR/learning-correction work that assumes a non-nil asset id.

### 2026-05-24: InBody 230 横向柱状图轴刻度被误读为字段值 — diagnostic
`OCRService.findValue` used `rowFiltered.first(where: expected.contains)` — InBody 230 每行布局 `[label] [axis ticks 40 55 70 85 ...] [实测值 68.1 kg] [正常范围 X.X~Y.Y]`，轴刻度整数全落在宽松的 `expected` 区间内，**第一个轴刻度就胜出**。Lesson: **宽 `expected` 区间 + first-match-wins 是 OCR 字段解析的反模式**。区间过滤 + first → 区间过滤 + 候选评分。Full Plan A/B implementation details archived to `.squad/agents/ash/history-archive.md` (2026-05-24).

### 2026-05-24: InBody OCR axis-scale fix landed — Plan A + B shipped (summary)
Two-stage pipeline replaces `first-match-wins` in `OCRService.findValue`: **Plan B** narrows expected via same-row `isPureRange` box (× 0.5/1.5 buffer); **Plan A** scores remaining candidates (+4 unit, +2 decimal, +2 Q3 height, +1 rightmost, **-5 equidistant integer group**). Fields with bar charts now expected-correct. `make build` ✅. **Full design notes + edge cases archived in `history-archive.md`.**

### 2026-05-24: Pattern D + E + Fix 3 + Fix 4 + Pattern F + reparseExistingReport — archived
Full session notes in `.squad/agents/ash/history-archive.md`. Headline:
- Pattern D/E/Fix3/Fix4 surgical fixes recovered 3/5 IMG_2245 assertions; weight + bodyFatMass blocked by Vision.
- Pattern F: "运动处方" footer is **trusted-override** for weight when bar-chart row emits plausible-but-wrong values (`238.0`, `w00.1kg`). Use trusted override when an authoritative alternative source exists in the document.
- `ScanViewModel.reparseExistingReport` static @MainActor method — UI escape hatch for re-OCRing existing records; bypasses dedup, overwrites numeric fields in place. Lambert wired DetailView toolbar button.

### 2026-05-24: HealthKit batch-write — Phases 1 & 2 (summary; full notes archived)
Phase 1 survey + Phase 1 cross-agent team note + Phase 2 implementation details all moved to `history-archive.md`. Key surface delivered:
- `HealthKitWriteResult` (written / skippedInvalid / skippedDuplicate / failed:[(UUID,Error)])
- `writeWeightSamples(_:[InBodyRecord]) async throws -> HealthKitWriteResult` (batch backfill)
- Single-sample dedup overload `saveWeight(_ kg:Double, date:Date, recordID:UUID)`; kept legacy non-dedup overload for back-compat
- All writes now `HKMetadataKeyWasUserEntered = false` (corrected — OCR is not manual entry)
- Dedup = **query-first + save-with-SyncIdentifier** double protection (UUID as `HKMetadataKeySyncIdentifier`, `HKMetadataKeySyncVersion = 1`)
- All 3 legacy `try? saveWeight(...)` call sites refactored to pass `recordID:`. Extract id/weight/date as Sendable primitives BEFORE `Task.detached` (SwiftData `@Model` cross-actor restriction).

## 2026-05-24 — Phase 2 shipped (team note)
Trends「写入健康」Phase 2 complete. My deliverable: `writeWeightSamples` + `HealthKitWriteResult` + dedup-enabled `saveWeight(_:date:recordID:)`. Lambert built UI on top; Parker shipped 10 active tests. **Open:** Ripley arbitration on `HealthKitWriting` protocol seam — extracting it unlocks Parker's 6 skipped unit tests.

## 2026-05-24 — Batch re-parse for skipped duplicates (ScanViewModel)

Extended `ScanViewModel` so the batch-import flow can offer end-of-batch "重新识别" for records that were silently skipped as duplicates.

**Public surface added (VM):**
- `var duplicateAssetIds: [String] = []` — populated in the dedup branch of `parseNextPhoto()`, in lock-step with `duplicateCount`.
- `var reparseIndex: Int = 0`, `var reparseTotal: Int = 0` — dedicated progress fields so batch-import progress (`currentParseIndex` / `selectedPhotos.count`) is not mutated during the reparse sweep.
- `@MainActor func reparseDuplicateRecords() async -> (succeeded: Int, failed: Int, errors: [(assetId: String, error: Error)])` — loops over `duplicateAssetIds`, fetches each `InBodyRecord` by `photoAssetIdentifier` predicate, delegates to existing `Self.reparseExistingReport(...)`, writes Chinese progress messages into `parseStageMessage`, best-effort (failures recorded, loop continues). Does NOT clear `duplicateAssetIds` so UI can show summary.

**Resets:** added the three new fields to `reset()`.
**Dedup branch:** only one new line — `duplicateAssetIds.append(assetId)`.
**Reparse method:** ~50 lines added at file tail, reusing `OCRCorrection` snapshot pipeline via the static `reparseExistingReport`.

**Contract handed to Lambert:**
```swift
let result = await scanVM.reparseDuplicateRecords()
// result.succeeded, result.failed, result.errors
// Progress while running: scanVM.reparseIndex / scanVM.reparseTotal + scanVM.parseStageMessage
```

**Test status:** `make test-unit` — 18 tests, 0 failures, 6 expected skips. Bundle fixture 5/5 still green (OCRServiceInBody230 + Dump suites pass).

**Files touched:**
- `MyBody/ViewModels/ScanViewModel.swift` (~60 lines added, 0 removed; no behavior change to existing dedup/initial scan path)
