# Project Context

- **Owner:** Jeff Tian
- **Project:** my-body — iOS native app that scans the photo library for InBody body composition reports, extracts the data, syncs to the user's Apple Account (iCloud), and writes results into Apple Health (HealthKit).
- **Stack:** Swift, SwiftUI, Vision (OCR), PhotosUI/PHPicker, HealthKit, CloudKit / iCloud
- **Created:** 2026-05-15

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

### 2026-05-24: InBody 230 OCR — three diagnostic patterns (Patterns A/B/C)

Captured during the InBody 230 misread fix session (requested by Jeff Tian). Single diagnostic-first session that fixed all 4 remaining field misreads (weight, sm, bfm, tbw, lbm now all pass `OCRServiceInBody230Tests`).

- **Pattern A — Vision splits decimals with a literal space.** Vision sometimes returns `"68. 1kg"` / `"56. 1 kg"` instead of `"68.1kg"`. The numeric regex inside `primaryNumber` would then capture only `68` and drop `.1`. **Fix:** rejoin `(\d)\.\s+(\d)` → `$1.$2` at the very top of `primaryNumber`, BEFORE key removal / unit stripping. Always normalize text first, then parse numbers.

- **Pattern B — same-row FieldSpec labels bleed into each other.** On InBody 230, `身体水分含量` (tbw, cy≈0.657) and `去脂体重` (lbm, cy≈0.653) sit on the same printed row. Without a column cap, tbw's pool absorbs lbm's value box (and vice-versa). **Fix:** at the top of the per-label loop, compute `competitorRight` = `min(left)` of any OTHER FieldSpec's label box that's right-of-this-label AND within rowTol; then add `.filter { $0.left < competitorRight }` to BOTH `rowCandidates` (no-range) AND `rowNumbersIncludingRange` (includes-range) chains. Competitor labels supplied via new `competitorKeys` parameter on `findValue`, populated from `specs.flatMap{$0.keys}` minus current spec's keys at call site.

- **Pattern C — `rowRange` picked the wrong adjacent reference range via `.first`.** On the bfm row (`体脂肪` cy=0.695), both `7.6~15.1` (bfm range, cy=0.688) and `26.8~32.7` (body-water range, cy=0.719) fall within rowTol (0.026). `.first` happened to pick `26.8~32.7`, narrowing expected to `[13.4, 49.05]` — which EXCLUDES the real value `12.0` but INCLUDES axis tick `40`. **Fix:** sort isPureRange candidates by `abs($0.cy - label.cy)` ascending, then take `.first`. Closest-by-row-distance wins.

- **Meta-lesson — always dump raw boxes BEFORE bumping scoring weights.** All three patterns were invisible to the old "tweak weights" approach. Capturing the 216-box dump (`OCRServiceInBody230DumpTests`, env-guarded `OCR_SKIP_DUMP`) was what made the diagnoses possible. Coordinator rule "Do NOT just bump scoring weights and pray" earned its keep — every fix here is a TARGETED edit driven by actual box geometry, not a heuristic tuning knob.

### 2026-05-24: Tooling traps to remember

- **xcbeautify 3.2.1 swallows test stdout** and reports crashes as `Executed 0 tests`. Bypass: pipe xcodebuild raw output through `grep`/`tail` directly, no `xcbeautify`. Or read `xcresulttool` from the `.xcresult` bundle.
- **`String(format: "%s", swiftString)` CRASHES on non-ASCII text.** Vision returns UTF-8 Chinese strings. Always use `%@` for Swift String formatting. Bit me once in the dump test; never again.
- **Swift `Double.truncatingRemainder(dividingBy: 1)` returns 0 for `12.0`** — so the "has decimal" bonus in scoring fires `(text.contains(".") && value % 1 != 0)`, but `12.0 % 1 == 0`. The bonus is correct conceptually (rewards genuine fractions) but means whole-number-with-trailing-zero values get no decimal bonus. Not a bug — just remember when scoring tied candidates.

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

- 2026-05-24: **InBody OCR axis-scale fix landed (Plan A + B)** in `OCRService.swift`. Replaced `rowFiltered.first(where: expected.contains)` with a two-stage pipeline:
  1. **Plan B (range narrowing)**: scan same-row `isPureRange` boxes, parse first one via new `parsePrintedRange` → `(low, high)`, narrow field's expected to `[low×0.5, high×1.5]` ∩ original. Kills far axis ticks pre-scoring.
  2. **Plan A (scoring)**: new `pickHighestScoring(pool, allRowCandidates)`. Weights: +4 unit (`kg|%|kcal`), +2 decimal (text contains `.` AND non-integer), +2 Q3 box height, +1 rightmost cx, **-5 equidistant integer group** (3+ ints, gap-spread < 0.4 → axis ticks). Tie-break: rightmost. Negative winner → bypass to legacy fallback.
  - **Design call (recorded in `.squad/decisions/inbox/ash-ocr-scoring-impl.md`)**: kept scoring inline in `OCRService` rather than extracting an `OCRScorer` service — only one consumer, surgical change. If Ripley wants it moved later, the function shape is already pure-functional (no instance state).
  - **Q3 height fallback**: `q3Height = 0` if degenerate → skip the +2 bonus instead of div-by-zero.
  - **Equidistant detection**: requires `meanGap > 0.001` to guard against all-zero-cx degraded inputs.
  - Build: `make build` (iphonesimulator) → Succeeded; only pre-existing `usesCPUOnly` warning.
  - Fields with bar charts now expected-correct: weight, skeletalMuscle, bodyFatMass, totalBodyWater, leanBodyMass, bodyFatPercent. BMI/WHR/BMR/inbodyScore/visceralFatLevel unaffected (no `isPureRange` box on those rows → Plan B no-ops, scoring still right because those fields have no axis ticks).
  - **Lesson reinforced**: scoring with explicit penalties for distractors (axis-tick -5) is more robust than narrowing the legitimate signal. Don't tighten `expected` permanently — narrow per-row via printed evidence.
  - Pending: Parker's `IMG_2245.HEIC` box-dump fixture for regression lock-in (decisions.md target: weight=68.1 / skeletalMuscle=31.7 / bodyFatMass=12.0).
