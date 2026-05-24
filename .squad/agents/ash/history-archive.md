# Ash — History Archive

Entries archived from `history.md` to keep the active file under 15KB. These entries are also recorded in `.squad/decisions.md`.

### 2026-05-24 — Pattern D + E + Fix 3 + Fix 4 (IMG_2245 axisScaleRegression)

**Empirical state on main HEAD at session start:** RED — 3 of 5 assertions failed
(weight=160, skeletalMuscle=25.7, bodyFatMass=31.7). "Green baseline" was stale.

**Vision OCR limits for this fixture (unrecoverable by parser):**
- Vision read `w00.1kg` where the bar value should read `68.1kg` → weight truth absent.
- Vision did NOT emit any box containing `12.0` for bodyFatMass row → truth absent.
- Only `m31.7kg` (skeletalMuscle) is surgically recoverable.

**Fixes applied to `MyBody/Services/OCRService.swift`:**
- **Pattern D — hard-narrowing skip** (`pickInRow`): when `rowRange != nil` and
  `inNarrowed.isEmpty`, `continue` instead of falling back to `inExpected`.
  Suppresses axis-tick / cross-row "kg" bleed for chart-bearing fields.
  Stays lenient for chart-less fields (BMI/WHR/BMR — `rowRange == nil`).
- **Pattern E — cy-proximity bonus** (`pickHighestScoring`): +2 when
  `|cand.cy − labelCy| ≤ rowTol × 0.4`. Tightens "same-row" beyond `rowTol=1.8×height`
  which admits adjacent rows. Signature extended with `labelCy, rowTol`.
- **Fix 3 — formula-label skip** (`findValue`): drop labels whose text contains
  `=`, `×`, or `÷`. Stops `=一体脂肪×100` formula line from being treated as a
  bodyFatMass label.
- **Fix 4 — competitor-key substring guard** (`findValue`): drop labels where any
  `competitorKey` matches with LONGER substring than the field's own keys. Stops
  `去脂体重` (leanBodyMass) from being treated as a `体重` (weight) label via
  substring containment.

**Result after all fixes:** 3/5 PASS — skeletalMuscle=31.7 ✓, totalBodyWater=41.2 ✓,
leanBodyMass=56.1 ✓. weight + bodyFatMass return nil because Vision didn't read
the truth values from this photo.

**FieldSpec key collisions documented (substring cross-contamination):**
- `体重` ⊂ `去脂体重`
- `体脂肪` ⊂ `体脂肪百分比` ⊂ multiple
- `体脂` ⊂ `体脂肪`, `体脂肪量`, `体脂肪百分比`, `体脂百分比`, `体脂率`
- `身体水分` ⊂ `身体水分总量`
- `骨骼肌` ⊂ `骨骼肌量`

Fix 4 makes substring containment SAFE — any field whose competitor key matches
longer wins exclusion. Risk: a legit label whose text also contains a competitor
key of EQUAL or longer length would be filtered. Current key sets are designed
so own keys are at least as long as competitor matches inside legit label boxes.

**Fixture/photo equivalence:** `MyBodyTests/Fixtures/InBody/inbody230-sample-01.heic`
yields the same Vision OCR boxes as user's IMG_2245 photo. Diagnosing against
the bundle fixture is sufficient.

**Tests file:** `MyBodyTests/Services/OCRServiceInBody230Tests.swift` uses
`?? .nan` (NOT force-unwrap `!`), so nil parses surface as "nan" in failure
messages rather than runtime traps.

### 2026-05-24: Pattern F — Exercise-prescription footer as trusted weight source

Follow-up session on IMG_2245.HEIC (Jeff's personal HEIC, gitignored). After Patterns D/E/3/4 from the previous session, weight was still wrong — chart-row pathway returned junk **238.0** (a chart-axis scale digit that happened to be in the 20-250 range and bypassed every nil-fallback). The print-quality "基础体重：68.1 kg" line inside the **运动处方** (exercise prescription) paragraph reads reliably; that paragraph sits at cy≈0.30 h≈0.019 with normal-sized type.

**Fix shape:**
- New helper `extractWeightFromExercisePrescription(boxes:expected:)` with two passes:
  1. Single-box regex `基础体重[：:]\s*(\d+(?:\.\d+)?)\s*kg` (case-insensitive).
  2. Cross-box: locate "基础体重" label boxes, scan same-row right neighbors using `rowTol = max(label.box.height, 0.012) * 1.8`, capture via `(\d+(?:\.\d+)?)\s*kg`.
- Normalizes `"68. 1 kg"` → `"68.1 kg"` via `replacingOccurrences(of: #"(\d)\s*\.\s+(\d)"#, with: "$1.$2", options: .regularExpression)`.
- Validates against expected range.
- **Critically — treat as TRUSTED OVERRIDE, not nil-fallback.** If the helper returns a value, it replaces whatever the chart-row pathway produced. The bar-chart row's value is junk often enough (and not-nil often enough) that nil-gating is insufficient.
- If the prescription paragraph is absent (older/cropped reports), helper returns nil and the chart-row pathway passes through unchanged — zero regression risk for fixtures that don't include this paragraph.

**Validation:**
- IMG_2245.HEIC dump test: weight=68.1 ✅ (was 238.0), tbw=41.2, lbm=56.1, sm=31.7. bodyFatMass still nil — Jeff's mandate was "只要体重正确就行", so partial victory acceptable.
- Bundle fixture `inbody230-sample-01.heic`: pre-existing `bodyFatMass=nan` baseline failure (NOT caused by Pattern F — confirmed by stashing the change and re-running). All other 4 fields including weight still pass.

**Takeaway:** When a parser pathway can emit *plausible-but-wrong* numbers (in-range, but semantically junk), `nil`-gated fallbacks won't save you. Either the fallback must be a trusted override, or the primary path needs stricter validation (e.g., require "kg" suffix in rawText). Trusted override is the lower-risk choice when an authoritative alternative source exists in the document.

## 2026-05-24 — Add reparseExistingReport for "重新识别" flow

**Task:** Provide UI-callable function to re-OCR an existing `InBodyRecord` against its stored PHAsset and overwrite numeric fields in place. Existing dedup-by-localIdentifier path stays unchanged; this is the explicit user-action escape hatch.

**Signature landed:**
```swift
@MainActor
static func reparseExistingReport(
    _ record: InBodyRecord,
    context: ModelContext,
    ocrService: OCRService = OCRService()
) async throws -> OCRService.ParsedReport
```
Lives on `ScanViewModel` (static — no need to instantiate full VM). Error type `ScanViewModel.ReparseError` (LocalizedError, 中文 messages).

**Pattern reuse:**
- Same OCRCorrection snapshot + lookup closure as `parseNextPhoto`, same useCount bump.
- Same `Task.detached(priority: .userInitiated)` for `parseReport` to keep main actor free.
- `PhotoScanService().loadFullImage(for:)` to fetch original image (same call as batch path).
- scanDate fallback chain: parsed → asset.creationDate → existing record value.

**Did NOT touch:**
- Dedup logic (`recordExists(forAssetId:in:)`) — unchanged. Silent-skip on reimport stays.
- Manual-edit-tracking — model has no `wasManuallyEdited` field. UI confirms before calling.
- toRecord() — not used here; we mutate the existing `InBodyRecord` in place.

**Files:** `MyBody/ViewModels/ScanViewModel.swift` (+128 lines, single file).

**Tests:** `make test-unit` 2/2 green. No regression in OCRServiceInBody230Dump or InBody230 axis-scale tests.


---

## 2026-05-24 — InBody OCR axis-scale fix landed (Plan A + B) [archived from history.md]

Replaced `rowFiltered.first(where: expected.contains)` in `OCRService.swift` with a two-stage pipeline:
1. **Plan B (range narrowing)**: scan same-row `isPureRange` boxes, parse first one via new `parsePrintedRange` → `(low, high)`, narrow field's expected to `[low×0.5, high×1.5]` ∩ original. Kills far axis ticks pre-scoring.
2. **Plan A (scoring)**: new `pickHighestScoring(pool, allRowCandidates)`. Weights: +4 unit (`kg|%|kcal`), +2 decimal (text contains `.` AND non-integer), +2 Q3 box height, +1 rightmost cx, **-5 equidistant integer group** (3+ ints, gap-spread < 0.4 → axis ticks). Tie-break: rightmost. Negative winner → bypass to legacy fallback.

- Design call: kept scoring inline in `OCRService` rather than extracting `OCRScorer` — only one consumer, surgical change. Function shape is pure-functional (no instance state) if Ripley wants it moved later.
- `q3Height = 0` if degenerate → skip the +2 bonus instead of div-by-zero.
- Equidistant detection requires `meanGap > 0.001` (guard against all-zero-cx degraded inputs).
- Build: `make build` (iphonesimulator) ✅; only pre-existing `usesCPUOnly` warning.
- Fields with bar charts now expected-correct: weight, skeletalMuscle, bodyFatMass, totalBodyWater, leanBodyMass, bodyFatPercent. BMI/WHR/BMR/inbodyScore/visceralFatLevel unaffected.
- **Lesson reinforced:** scoring with explicit penalties for distractors (axis-tick -5) is more robust than narrowing the legitimate signal. Don't tighten `expected` permanently — narrow per-row via printed evidence.
- **Future:** If we add `wasManuallyEdited: Bool` per-field flags, the function should preserve manually-edited fields by default.

## 2026-05-24 — HealthKit batch-write survey (Phase 1) [archived]
- Existing `HealthKitService` writes one bodyMass sample per call via `saveWeight(_:date:)`; no dedupe metadata, no batch API. All 3 callers (ScanVM × 2, EditRecordView) use `try?`.
- Entitlements + Info.plist already correct (HealthKit cap on, NSHealthUpdateUsageDescription / NSHealthShareUsageDescription cover writes).
- Data model is `InBodyRecord`; weight `Double?` (kg), date `scanDate: Date`, identity `id: UUID` → use UUID as `HKMetadataKeySyncIdentifier` for idempotent re-writes.
- Phase-2 API drafted: `writeWeightSamples(_ records:[InBodyRecord]) async throws -> HealthKitWriteResult` (written / skippedDuplicate / skippedInvalid / failed). Pre-flight throws; per-sample errors collected.
- Flagged for Ripley: `HKMetadataKeyWasUserEntered=true` for OCR-derived samples is questionable; whether single-record callers should migrate to the batch API.

## 2026-05-24 — Team note: Trends Weight → Health Phase 1 [archived]
Cross-agent Phase 1 planning landed in `.squad/decisions.md` (4 entries dated 2026-05-24). Two open arbitrations (dedup mechanism, `HKMetadataKeyWasUserEntered`) resolved by Ripley before API freeze.

## 2026-05-24 — Weight→Health Phase 2 implementation [archived]
- Added `HealthKitWriteResult` (written / skippedInvalid / skippedDuplicate / failed:[(UUID,Error)]) + `writeWeightSamples(_:[InBodyRecord]) async throws` for batch backfill.
- Added single-sample dedup overload `saveWeight(_ kg:Double, date:Date, recordID:UUID)`; kept legacy `saveWeight(_:date:)` for back-compat.
- All writes now `HKMetadataKeyWasUserEntered = false` (was `true` — wrong, OCR is not manual entry).
- Dedup path: **query-first by SyncIdentifier + save-with-SyncIdentifier double protection** — query gives accurate `skippedDuplicate` count for the UI, save covers query→save races via HK's replace-by-version semantics (`HKMetadataKeySyncIdentifier = record.id.uuidString` + `HKMetadataKeySyncVersion = 1`).
- Refactored all 3 legacy `try? saveWeight(weight, date:)` call sites (EditRecordView L118, ScanViewModel L189/L324) to pass `recordID: record.id`. Extract id/weight/date as Sendable primitives BEFORE `Task.detached` to avoid sending SwiftData `@Model` across actors.
- `writeWeightSamples` reads `record.weight/scanDate/id` synchronously into local `Candidate` structs before the first `await` (Swift 6 isolation).
- Pre-flight auth: `.notDetermined` triggers a single prompt; `.sharingDenied` after prompt → throws `HealthKitError.notAuthorized`. Per-sample errors aggregate into `result.failed` (never thrown).
- Batch save atomic via `store.save([HKObject])`; on failure falls back to per-sample save to locate which records failed.
- `make build` ✅.
