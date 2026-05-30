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

### 2026-05-24: HealthKitWriting protocol seam + FakeHealthKitWriter (Phase 2.5)

Ripley arbitration GO. Extracted minimal testable seam so Parker's 6 `XCTSkip`'d tests can run without touching `HKHealthStore`.

**Surface (`MyBody/Services/HealthKitService.swift`):**
- `protocol HealthKitWriting`: `isAvailable`, `bodyMassWriteStatus`, `requestAuthorization()`, `writeWeightSamples(_:) -> HealthKitWriteResult`, `saveWeight(_:date:recordID:)`. ONLY what Trends/Edit/Scan need — no `saveWeight(_:date:)` legacy overload, no internal query helpers.
- `HealthKitService: HealthKitWriting` (single-line conformance; methods already matched).
- `static func partitionForWrite(_:now:) -> (writable:[InBodyRecord], skippedInvalid:[InBodyRecord])` — extracted from `writeWeightSamples` so production AND `FakeHealthKitWriter` reuse one filter. `now: Date = Date()` injectable for future-date tests. `writeWeightSamples` now calls it then `compactMap`s candidates.

**Signature changes:** none to existing public methods. Call sites (`ScanViewModel` ×2, `EditRecordView`, `TrendsView`, `SettingsView`) untouched per task; `HealthKitService.shared` still concrete singleton.

**Fake (`MyBodyTests/Services/FakeHealthKitWriter.swift`):**
- `@unchecked Sendable` + `NSLock` for thread-safe call recording.
- Knobs: `isAvailable`, `bodyMassWriteStatus`, `authorizationError`, `onRequestAuthorization` (mutate status mid-prompt to simulate user denial), `preExistingRecordIDs` (→ `skippedDuplicate`), `failingRecordIDs` (→ `failed`), `saveError`.
- Records: `authorizationCallCount`, `saveWeightCalls`, `writeWeightSamplesCalls`.
- `writeWeightSamples` mirrors production pre-flight (device → auth → partition), then categorizes writables via the knob sets. **Reuses `HealthKitService.partitionForWrite`** so fake/prod cannot drift.

**Wiring notes for Parker:**
- Tests that exercise `writeWeightSamples` directly: instantiate `FakeHealthKitWriter()`, set knobs, `try await fake.writeWeightSamples(records)`. No injection into `HealthKitService.shared` needed for unit-only tests.
- For `metadataIncludesSyncIdentifier` / `dateBoundariesPreserved`: the fake doesn't construct `HKQuantitySample` (it just categorizes). If you need to assert metadata/date roundtrips, either (a) trust the production code path (covered by integration) and assert call recording instead, or (b) ask Ash to add a `capturedSamples: [(syncId:String, start:Date, end:Date)]` recording hook on the fake.
- `concurrentWrites_serialize`: HealthKitWriting itself doesn't promise serialization — that's an HKHealthStore property. Either drop the test or restate it as "calls don't crash under concurrency" (the lock guarantees that).
- `notAuthorized_throwsBeforeWrite`: set `bodyMassWriteStatus = .sharingDenied`; assert throws + `saveWeightCalls.isEmpty`.

**Results:** `make build` ✅. `make test-unit` ✅ 18 tests, 0 failures, 6 skipped (Parker's queue).

### 2026-05-24: Phase 2.5 complete — HealthKitWriting protocol seam shipped
Extracted protocol + lifted `partitionForWrite` to static + created `FakeHealthKitWriter`. Build green. Parker activated all 6 XCTSkip tests against the fake → 18/0/0. Source not yet committed (Jeff manual). Drift note: fake records bulk `[InBodyRecord]` call args, not per-sample HKQuantitySample saves; HK metadata invariants deferred to integration tests.

### 2026-05-25: Cross-device OCR misread — root cause was UNPINNED Vision revision

Same printed InBody 230 report photographed on two iPhones: device A read 体重 68.1 kg correctly; device B read 60.0 kg + 体脂肪 100.0 kg (impossible) + 身体水分 23.8 kg. Not a digit drop — a device-dependent field-association divergence.

- **ROOT CAUSE — `VNRecognizeTextRequest.revision` was never set.** Vision selects the NEWEST model revision available on each device's iOS version. Two phones on different iOS builds → different text-recognition models → different box segmentation / geometry / reading order for the identical photo. Our whole parser (`parseBoxes`/`findValue`) is geometry+text dependent, so divergent boxes cascade into divergent field associations. This fully explains "68.1 on A, 60.0+garbage on B." **Fix:** pin `request.revision = VNRecognizeTextRequestRevision3` (iOS 16+; app min iOS 17 so always available) guarded by `supportedRevisions.contains(...)`. OCR is now deterministic across devices. THIS is the cross-device fix.

- **SECONDARY — no cross-field numeric validation.** Per-field `expected` ranges are single-field hard bounds only. `bodyFatMass.expected = 1...100` literally let `100.0 kg` through; nothing checked a mass component must be < body weight. **Fix:** new `applyCrossFieldValidation(&report)` — every mass component (skeletalMuscle/bodyFatMass/totalBodyWater/leanBodyMass) must be < weight × 1.02; violators drop to nil + go to `failedFields` + stripped from `rawTexts`, so the UI shows "未识别" instead of persisting garbage into HealthKit. Only runs when `weight` parsed (need a trusted anchor). Existing fixture (68.1/31.7/12.0/41.2/56.1) all pass the ceiling.

- **Lesson — determinism before heuristics.** We spent a whole prior session tuning scoring weights (Patterns A–F) on ONE device's box layout. Those heuristics are only as stable as the boxes feeding them; an unpinned Vision revision silently invalidates all of it on a different phone. Pin the model FIRST, then tune. Any future OCR heuristic work must assume revision is pinned.

- **Deferred to Ripley — layout fingerprint / coordinate-anchor (roadmap Phase 4).** The parser remains geometry-fragile even with a pinned revision (rowTol/competitorRight/scoring all sensitive to box jitter). The durable answer is an InBody-230 layout template anchoring values to normalized coordinate regions. Flagged, not implemented this session.

- **Files:** `MyBody/Services/OCRService.swift` — `runRecognition` (revision pin) + new `applyCrossFieldValidation` (called at end of `parseBoxes`). `make build` ✅.
