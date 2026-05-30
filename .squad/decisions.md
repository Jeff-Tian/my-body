# Squad Decisions

## Active Decisions

### 2026-05-24: InBody 横向柱状图坐标轴刻度被误读为字段值
**By:** Ash (Core Engineer)
**Status:** Diagnosis — proposing fix path, no code change yet.

## 现象 (Jeff 反馈)

扫描 InBody 230 报告 `IMG_2245.HEIC`:

| 字段 | App 解析 | 实际报告 | 备注 |
|---|---|---|---|
| 体重 | 55.0 kg | **68.1 kg** | 错 |
| 骨骼肌量 | 60.0 kg | **31.7 kg** | 错 |
| 体脂肪量 | 40.0 kg | **12.0 kg** | 错 |

## 根因

InBody 230 的每个主指标行布局是:

```
[体重]  40  55  70  85  100  115  130  ...           68.1 kg     53.4~72.3
 ↑       ↑─────── 坐标轴刻度 (整数 box) ──────↑     ↑─实测值─↑    ↑─正常范围─↑
 label                                              (gray bar end)
```

在 [`OCRService.parseBoxes` → `findValue`](MyBody/Services/OCRService.swift) 里,
当前匹配策略 (见 [OCRService.swift:324-334](MyBody/Services/OCRService.swift#L324-L334)):

```swift
let rowFiltered = boxes
    .filter { $0.left > label.right - 0.005 }     // 同行右侧
    .filter { abs($0.cy - label.cy) < rowTol }    // 同行
    .filter { !isPureRange($0.text) }             // 排除 "53.4~72.3"
    .compactMap { primaryNumber($0.text) }

if let hit = rowFiltered.first(where: { expected.contains($0.0) }) {
    return hit   // ⚠️ 第一个落在 expected 区间里的数字就胜出
}
```

字段的 `expected` 区间宽松 (`weight: 20...250`、`skeletalMuscle: 5...60`、
`bodyFatMass: 1...100`),把坐标轴刻度 (`40, 55, 70, 85, 100, 115` 等)
**全部包含在内**。`first(where:)` 又按数组顺序(≈ 阅读顺序、左到右),
所以 **第一个轴刻度** 就被当成字段值返回,实测值 `68.1` 根本没机会胜出。

App 看到的 `55 / 60 / 40` 全是整数,正好匹配三行的轴刻度。**实测值都是小数 (`68.1 / 31.7 / 12.0`),都被忽略。** 这是根因的另一条强证据。

## 哪些字段会中招

凡是带横向柱状图 + 顶部刻度的行都会中招,典型受影响字段:

- `weight` 体重
- `skeletalMuscle` 骨骼肌量
- `bodyFatMass` 体脂肪量
- 可能还有 `totalBodyWater`、`bodyFatPercent`、`leanBodyMass`(取决于具体机型版式)

不带柱状图的字段(BMI、WHR、BMR、InBody评分、内脏脂肪等级)目前不受影响。

## 修复方案 — 按效果/成本排序

### 方案 A · 行内候选评分(推荐先做,改动最小)

把 `rowFiltered.first(where:)` 改成一个 **scoring + 取最高分** 的选择:

| 信号 | 权重 | 理由 |
|---|---|---|
| 文本含 `kg` / `%`(或紧邻右侧 box 含单位) | +大 | 实测值几乎一定带单位 |
| 是小数(`含 "." 或末位非 0`) | +中 | 实测值是小数,刻度是整数 |
| box 高度(`box.height`)显著高于行内中位数 | +中 | 实测值字号通常 2-3× 于刻度 |
| 同行最右侧(在 `isPureRange` 已过滤后) | +小 | 实测值在 bar 末端 |
| 落在 `expected` 区间内 | 必要 | hard filter |
| 是行内整数候选群中"等距分布"的一员 | -大 | 检测到则是轴刻度 |

实施位置:[`OCRService.findValue`](MyBody/Services/OCRService.swift#L268-L367) 内,
不影响外部调用方,纯局部重构。**预计代码量:30-50 行新增 + 替换 first-match。**

**风险:** 评分需要兜底——所有候选都被打成负分时退回当前的 `distanceToRange` 逻辑。

### 方案 B · 利用印刷的"正常范围"做 sanity check(防御性,推荐与 A 一起做)

每行右端通常有 `正常范围 53.4~72.3` 这种 box(目前被 `isPureRange` 直接丢弃)。
**别丢——把它解析成一个区间,然后把每个字段的 `expected` 临时收紧到
`range.lowerBound × 0.5 ... range.upperBound × 1.5`**。

收紧后,体重行的候选区间会从 `20...250` 变成 `~26.7...108.5`,
轴刻度 `115, 130, 145` 直接被砍掉;`40, 55, 70` 仍然在区间内,
但配合方案 A 的"含单位 / 小数 / 字号大"权重就能正确选出 `68.1`。

实施位置:`parseBoxes` 在跑 specs 之前先扫一遍所有 `isPureRange == true` 的 box,
按 `cy` 配对到每行 label。**预计代码量:20-30 行。**

### 方案 C · 检测等距整数轴刻度并整体过滤(更稳但更重)

若同行有 4+ 个整数候选,且相邻差大致相等(等差数列),
判定这一串就是坐标轴并整体剔除,只留非整数 / 带单位的候选。

更鲁棒,但 InBody 不同行的刻度密度不一定均匀(`体脂肪` 可能更密),
易触发误判。**作为方案 A/B 之后的备选,不优先做。**

### 方案 D · 不做(明确否决)

- ❌ 把 `expected` 区间一刀切收得很窄:会破坏机型差异容忍度,违背 [docs/ocr-learning-roadmap.md](docs/ocr-learning-roadmap.md) Phase 5 的"个性化收紧"方向。
- ❌ 仅靠 `OCRCorrection`(Phase 1)兜底:用户每张新图都得手改一次,完全不符合"越用越准"的目标。

## 建议落地顺序

1. **先做方案 A**(评分函数)——单独就能把 `IMG_2245.HEIC` 这类问题解决,改动隔离。
2. **紧接着做方案 B**(印刷范围 sanity check)——把整列轴刻度直接打出区间外,
   作为方案 A 的"硬过滤"。两者叠加预计可把这一类误读消灭。
3. 写 Parker 的回归 fixture:用 `IMG_2245.HEIC` 的 OCR box 转储 (`[TextBox]` JSON)
   作为快照测试,锁住 `weight=68.1 / skeletalMuscle=31.7 / bodyFatMass=12.0`。
   后续任何 parser 改动都要跑这个 fixture。

## 待 Jeff 确认

- 是否 OK 先实施方案 A + B?
- 是否愿意把 `IMG_2245.HEIC`(脱敏处理后)作为 fixture 提交进仓库?
  如不愿,可以只提交 OCR `[TextBox]` JSON dump,不放原图。

### 2026-05-24T00:00:00Z: Single-photo import entry point on HomeView FAB
**By:** Lambert (iOS UI Developer)
**What:** Added a "选择单张照片" option to the HomeView "导入报告" FAB via a `Menu`. New `SinglePhotoImportView` runs one picker-selected photo through `ScanViewModel.startSingleImport`, which has a dual code path: PHAsset fast path (reuses batch pipeline, preserves dedup) and raw `Data` fallback (saves with `assetIdentifier: nil` when PHAsset access is limited).
**Why:**
- **Menu over confirmation dialog / inline twin buttons:** keeps the FAB visually unchanged ("导入报告" + icon), discoverable without crowding the home screen; menu items have icons so the choice is obvious.
- **Dual-path (PHAsset + Data) instead of single Data-only flow:** `PhotosPicker(photoLibrary: .shared())` exposes PHAsset `localIdentifier` via `itemIdentifier`, so picker-selected photos can flow through the same dedup-aware pipeline as full-library scans. The Data fallback only kicks in when the identifier is missing (limited-access album), where dedup isn't possible anyway. Net result: same import experience whether the user scans the library or hand-picks one photo, with no schema or service changes.
- **New sibling view instead of modifying PhotoScanView:** keeps batch-scan UI / state machine intact (no risk to existing flow); `SinglePhotoImportView` mirrors only the `parsingView` portion needed for one-shot import.

**Files touched:**
- `MyBody/Views/Home/HomeView.swift` — Menu FAB + PhotosPicker + sheet wiring
- `MyBody/ViewModels/ScanViewModel.swift` — `startSingleImport(itemIdentifier:fallbackImageData:)` + `parseSingleDataImage`
- `MyBody/Views/Scan/SinglePhotoImportView.swift` — new view (sheet host for single-import parsing UI)

**Verified:** `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` succeeded (only pre-existing OCR deprecation warnings).

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
# 2026-05-24: InBody OCR axis-scale fix — implementation (Plan A + B)

**By:** Ash (Core Engineer)

**What:** Implemented Plan A (candidate scoring) + Plan B (printed-range
sanity check) in `OCRService.findValue` to stop axis ticks from winning
over real measurements in `IMG_2245.HEIC`-class reports.

## Plan B — printed range narrowing (runs first per label row)

Scan same-row boxes that pass `isPureRange`, parse the first one back
into `(low, high)` via new `parsePrintedRange`. Narrow that field's
`expected` to `[low × 0.5, high × 1.5]` clipped to the original spec.
This kills far axis ticks (115/130/145 on the weight row) before
scoring even runs.

If no printed range is found on the row → keep the original `expected`.
Existing fields without bar charts (BMI/WHR/BMR/visceral fat) are
unaffected because they typically have no `isPureRange` box on the row.

## Plan A — scoring (replaces `rowFiltered.first(where:)`)

New `pickHighestScoring` takes the post-narrow candidate pool plus the
full row candidate set (for axis-tick detection). Weights chosen:

| Signal | Δ | Rationale |
|---|---|---|
| Text contains `kg` / `%` / `kcal` | +4 | Measured values carry units; ticks don't. |
| Value is a decimal (`.` in text AND non-integer) | +2 | Ticks are integers; measurements are decimals. |
| Box height ≥ row Q3 height | +2 | Printed measurement font is 2-3× tick font. |
| Rightmost cx in pool (±0.005) | +1 | Measurement sits at bar end. |
| Member of equidistant integer group (3+, spread<0.4) | -5 | Axis ticks. |

Pool selection:
- First try candidates in `narrowed` (Plan B) range.
- If empty (e.g. Plan B not applicable), fall back to `expected`.
- If the winner's score is negative → return nil → outer fallback chain
  takes over (distance-to-range, below-column).

Tie-break: highest score, then rightmost cx.

## Edge cases handled

- **No printed range on row** → Plan B no-op, scoring still runs on `expected`.
- **All candidates score negative** (e.g. only ticks present) → bypass
  scoring, run legacy distance-to-range fallback (preserves recovery
  for misaligned rows).
- **`pool` empty after narrowing but `expected` candidates exist** →
  fall back to `expected` pool. This protects against an overly tight
  printed range we shouldn't trust.
- **Q3 height degenerate** (single candidate or zero heights) → set
  to 0 and skip the +2 height bonus rather than divide-by-zero.
- **Equidistant detection requires meanGap > 0.001** → guards against
  all-zero cx in degraded data.

## What did NOT change

- Plan C (4+ integer axis filter) — only a piece of it lives in the -5
  weight; not a separate prefilter.
- `isPureRange` regex — unchanged.
- `primaryNumber` — unchanged.
- Outer fallback chain (below-column, allow-pure-range) — preserved.

## Verification

- `make build` (iphonesimulator, Debug) → **Build Succeeded** with only
  the pre-existing `usesCPUOnly` deprecation warning. No new warnings.
- Runtime verification pending Parker's `IMG_2245.HEIC` fixture
  (decisions.md, weight=68.1 / skeletalMuscle=31.7 / bodyFatMass=12.0).

## Follow-ups

- Parker: fixture-based snapshot test against the box dump.
- Ripley: confirm the scoring weights live in `OCRService` (not a
  separate `OCRScorer` service) — current shape keeps it surgical and
  inside the only consumer.
### 2026-05-24: Xcode 26.5 blocks `xcodebuild test` until iOS 26.5 runtime is installed
**By:** Ripley
**What:** Patched `test`/`test-unit` Makefile targets to JSON-pick newest installed iOS runtime + pass UDID destination (replaces fragile awk parsing). Verified picker on Jeff's machine: iPhone 17 Pro / iOS 26.4.1 / `A9F9CCA5-AE42-4400-AE52-16B081538192`.
**Blocker discovered:** `xcodebuild test` enforces strict SDK↔runtime pairing. Xcode 26.5's iphonesimulator SDK (build `23F73`) refuses to run on the iOS 26.4.1 runtime (build `23E254a`). Error: `No simulator runtime version from ["21F79","22C150","22F77","23B86","23C54","23E244","23E254a"] available to use with iphonesimulator SDK version 23F73`. `make run` is unaffected because the build action is lenient.
**Why:** OCRServiceInBody230Tests could not be evaluated until one of these is true:
1. Install iOS 26.5 simulator runtime (~6GB) via Xcode → Settings → Components.
2. Install a side-by-side older Xcode (e.g., 16.x) and point `DEVELOPER_DIR` to it for the test target only.
3. (Last resort) Run the test as an XCTest plugin against macOS — not viable for Vision-based HEIC OCR fixtures.
**Status:** Makefile patch staged (not committed). Test execution deferred until runtime/SDK gap is resolved.

### 2026-05-24T07:42:49Z: InBody 230 OCR — Patterns A/B/C fix landed

**By:** Ash (Core Engineer), requested by Jeff Tian
**Scope:** `MyBody/Services/OCRService.swift` only

**What changed (5 surgical edits, all dump-evidence driven, zero scoring-weight tweaks):**

1. **`primaryNumber` decimal-space rejoin** — added `(\d)\.\s+(\d)` → `$1.$2` regex at top of function BEFORE key/unit stripping. Fixes weight `"68. 1kg"` → `68.1` and any future Vision split-decimal output.
2. **`findValue` signature** — added `competitorKeys: [String] = []` parameter.
3. **Call site** — passes `specs.flatMap{$0.keys}` minus current spec's keys as competitorKeys.
4. **`competitorRight` computation** — inside per-label loop, finds nearest right-of-label competitor FieldSpec label within rowTol. Default `1.0` when none.
5. **Column cap on both candidate chains** — `rowCandidates` and `rowNumbersIncludingRange` both gain `.filter { $0.left < competitorRight }`.
6. **`rowRange` sort-by-cy-distance** — replaced `.first` with `.sorted { abs($0.cy - label.cy) < abs($1.cy - label.cy) }.first` so when two adjacent fields' reference ranges both fall within rowTol, the one geometrically closer to the label wins.

**Why this approach (not scoring weights):**

The coordinator's diagnostic-first directive applied here. The 216-box raw OCR dump (`OCRServiceInBody230DumpTests`, env-guarded `OCR_SKIP_DUMP`) revealed three distinct root causes:

- Pattern A: Vision text-shape bug (decimal split by literal space)
- Pattern B: layout collision (two FieldSpec labels share row 0.657)
- Pattern C: heuristic ambiguity (two valid pure-range boxes in same rowTol band, `.first` picks wrong one)

None of these would have been solved by reweighting the scoring function. Each got a TARGETED edit at the layer responsible for the failure (text normalization / column geometry / range selection ordering).

**Verification:**

`xcodebuild test -only-testing:MyBodyTests/OCRServiceInBody230Tests` — PASS (4.7s). All 5 fields read correctly: weight=68.1, sm=31.7, bfm=12.0, tbw=41.2, lbm=56.1 (±0.05).

**Decisions for the team to respect going forward:**

- **The OCR dump test is the diagnostic entry point.** Future OCR misreads → run `OCR_SKIP_DUMP=0 xcodebuild test -only-testing:MyBodyTests/OCRServiceInBody230DumpTests` (or analog for the failing report) FIRST. Eyeball the boxes. Then edit.
- **Do not "fix" OCR by adjusting scoring weights** unless the dump shows you've exhausted geometric/textual root causes. Scoring weights are last resort.
- **`competitorRight` is now a load-bearing invariant in findValue.** Any new FieldSpec must list ALL of its label aliases in `keys` so the competitor lookup is symmetric — otherwise siblings can bleed in either direction.
- **`rowRange` picks the cy-closest pure-range box, not the first one in iteration order.** Don't revert to `.first` without re-running the InBody 230 regression.


### 2026-05-24 — IMG_2245 axisScaleRegression: 4 surgical fixes, 2 fields unrecoverable
**By:** Ash (Core/Vision/OCR) — requested by Jeff Tian
**What changed in `MyBody/Services/OCRService.swift`:**
1. **Pattern D (hard-narrowing skip)** — when a printed range narrows the candidate pool to empty AND `rowRange != nil`, `continue` instead of falling back to the lenient `inExpected` pool. Scoped to chart-bearing fields so BMI/WHR/BMR-style fields (no rowRange) keep their lenient fallback.
2. **Pattern E (cy-proximity bonus)** — `pickHighestScoring` now awards +2 when candidate cy is within `rowTol × 0.4` of label cy. `rowTol = max(label.height, 0.012) × 1.8` is generous enough to admit adjacent rows, and the existing +1 "rightmost" bonus could tip ties to the wrong row. cy-proximity disambiguates.
3. **Fix 3 (formula-label skip)** — drop labels whose text contains `=`, `×`, or `÷`. InBody reports include formula text like `=一体脂肪×100`; substring matching wrongly admitted it as a `体脂肪` label.
4. **Fix 4 (competitor-key substring guard)** — drop labels where any competitor key matches with LONGER substring than the field's own keys. Stops `去脂体重` (leanBodyMass) being treated as a `体重` (weight) label.
**Result:** 3 of 5 assertions pass (skeletalMuscle=31.7, totalBodyWater=41.2, leanBodyMass=56.1). `weight` and `bodyFatMass` return nil because Vision's OCR output does not contain those truth values for IMG_2245 (`w00.1kg` not `68.1kg`; no box contains `12.0`). Pattern F (next entry) recovers `weight` via authoritative source.

### 2026-05-24 — Pattern F: Exercise Prescription Footer is Authoritative for Weight
**By:** Jeff Tian (via Ash)
**What:** In `OCRService.swift` parser, treat the "运动处方" footer text ("基础体重：68.1 kg") as the **trusted override** for the `weight` field. When the helper `extractWeightFromExercisePrescription` returns a value, it replaces whatever the bar-chart row produced (no nil-gating).
**Why:** The bar-chart row at cy≈0.75 is frequently misread by Vision (e.g. "w00.1kg", or chart-axis scale "238"). The exercise-prescription paragraph at cy≈0.30 is normal print-quality text and reads reliably. On IMG_2245.HEIC the chart-row pathway produced 238.0 (junk in valid range, no kg suffix), so the previous nil-fallback never fired. Switching to trusted override yields weight=68.1 on IMG_2245 with no regression on the bundle fixture.
**Notes:** Helper validates range 20…250 and normalizes "68. 1 kg" → "68.1 kg". If the prescription paragraph is absent (old/cropped reports), helper returns nil and the chart-row value passes through unchanged. **Meta-lesson:** when a parser pathway can emit plausible-but-wrong numbers, `nil`-gated fallbacks won't save you — use a trusted override when an authoritative alternative source exists in the document.

### 2026-05-24 — Re-OCR existing reports via `ScanViewModel.reparseExistingReport`
**By:** Ash
**What:** Added `@MainActor static func reparseExistingReport(_ record: InBodyRecord, context: ModelContext, ocrService: OCRService = OCRService()) async throws -> OCRService.ParsedReport` on `ScanViewModel`. Throws `ScanViewModel.ReparseError` (noOriginalPhoto / photoNotInAlbum / imageLoadFailed / ocrFailed) with 中文 messages.
**Why:** Records imported with the old parser still hold wrong values (e.g. 55kg vs 68.1kg). User triggers "重新识别" from `DetailView`; we fetch the original PHAsset via `photoAssetIdentifier`, re-OCR with the current parser + OCRCorrection snapshot, and overwrite numeric fields + `ocrRawTexts` in place. Dedup-by-localIdentifier path is untouched — this is the explicit escape hatch.
**Caveats:** No manual-edit-tracking yet. Overwrites unconditionally; UI layer is responsible for confirmation. Future: add per-field `wasManuallyEdited` flags to preserve user edits across re-parse.

### 2026-05-24 — "重新识别" toolbar button in DetailView
**By:** Lambert — requested by Jeff Tian
**Files:** `MyBody/Views/Detail/DetailView.swift` (+~95 lines net)
**What:** Toolbar button (placed before edit, before delete in `topBarTrailing`) triggers re-OCR flow: confirm alert → `ultraThinMaterial` progress overlay → success capsule banner (`Color.appGreen`, 1.8s, `move(.top).combined(.opacity)`) / error alert. Disabled when `record.photoAssetIdentifier == nil` or `isReparsing == true`; edit/delete also disabled during execution.
**Interface to Ash:** `_ = try await ScanViewModel.reparseExistingReport(record, context: modelContext, ocrService: OCRService())`. Errors prefer `as? ScanViewModel.ReparseError` (中文 LocalizedError), then Photos-domain fallback, then `localizedDescription`.
**Key decisions:** Used actual model field `photoAssetIdentifier` (spawn prompt incorrectly said `assetId`). Button order "重新识别 → 编辑 → 删除" progresses automatic → manual → destructive.
**Tests:** `make test-unit` 2/2 green.

### 2026-05-24 — Embed Git commit hash in app, display in Settings
**By:** Jeff Tian (coordinator-implemented, not via agent spawn)
**Files:** `project.yml` (postCompileScript "Embed Git Commit Hash"), `MyBody/Views/SettingsView.swift` (display row).
**Why:** Users / Jeff need to identify which build is installed when reproducing OCR misreads or other bugs. xcodegen postCompile writes the short SHA into Info.plist; SettingsView reads it back via `Bundle.main.infoDictionary`. No code-signed runtime fetch; pure build-time stamp.

### 2026-05-24 — Trends 体重→Apple Health 写入 (Phase 1: Architecture)
**By:** Ripley (Lead/Architect)
**Status:** Proposed — Lambert (UI) + Ash (HealthKit dedup) + Parker (tests) Phase 2.
**Requested by:** Jeff Tian

**Decisions:**
1. **Entry point:** `ToolbarItem(.topBarTrailing)` "写入健康" on `TrendsView`, **conditionally visible** when `viewModel.selectedMetric == .weight`. SF Symbol `heart.text.square`. Tap → `.confirmationDialog`「写入 N 条 / 取消」。
2. **Scope:** writes `viewModel.filteredRecords.filter { $0.weight != nil }` (current `timeFilter` range). User-controlled — no auto-write-all-history.
3. **Authorization:** request **on first tap**, not on view appear. On `.sharingDenied` → alert with deep-link to system Settings.
4. **Deduplication:** use HealthKit metadata key `"com.jefftian.mybody.recordID" = record.id.uuidString` (+ keep `HKMetadataKeyWasUserEntered`). Query-before-write via `NSPredicate(format: "metadata.%K == %@", ...)`. **Do NOT add `syncedSampleIDs` to `InBodyRecord`** — HK is the source of truth (survives reinstall / cross-device).
5. **Feedback:** inline `ProgressView` "写入中 X/N" → `.alert` "已写入 X，跳过 Y，失败 Z"。No rollback on partial failure (HK has no transactions).
6. **Entitlements:** ✅ already in place (`com.apple.developer.healthkit = true`, `NSHealth*UsageDescription` present).
7. **Relation to existing Settings "syncWeightToHealth" toggle:** Trends entry is **explicit补写**, NOT gated by the toggle (toggle only controls automatic scan-time write).

**Out of scope:** Health → MyBody read-back; non-weight metric write; backfilling Scan/Edit existing callers (separate follow-up issue).

---

### 2026-05-24 — HealthKit Write Survey & Phase-2 API (Phase 1: Service Layer)
**By:** Ash (Core Engineer)
**Status:** Survey complete — Phase 2 API proposed; awaiting Ripley arbitration on 2 metadata questions.

**Existing surface (`MyBody/Services/HealthKitService.swift`, ~80 lines):**
- Singleton `HealthKitService.shared` wrapping one `HKHealthStore`.
- `saveWeight(_ kg:Double, date:Date) async throws` — single sample, `HKMetadataKeyWasUserEntered: true`, no dedup.
- Three fire-and-forget callers via `try?`: `ScanViewModel.swift:189,324`, `EditRecordView.swift:118`. → **pre-existing bug: re-scans duplicate Health samples today.**
- Entitlements + `NSHealth*UsageDescription` already cover batch write — **no plist additions required**.

**Proposed Phase-2 API:**
```swift
struct HealthKitWriteResult {
    var written: Int
    var skippedDuplicate: Int
    var skippedInvalid: Int
    var failed: [(recordID: UUID, error: Error)]
}
extension HealthKitService {
    func writeWeightSamples(_ records: [InBodyRecord]) async throws -> HealthKitWriteResult
}
```
- Pre-flight `isAvailable` + auth (`.notDetermined` → prompt once before loop).
- Filter `weight == nil || weight <= 0` → bump `skippedInvalid`.
- Per-record metadata: `HKMetadataKeySyncIdentifier = "mybody.inbody.\(record.id.uuidString)"`, `HKMetadataKeySyncVersion = 1`.
- Single `HKHealthStore.save([HKObject])` round trip; HK dedupes by SyncIdentifier within same source.
- Throw only on pre-flight; per-sample errors → `result.failed`.
- Keep existing `saveWeight(_:date:)` for now (route ScanViewModel/EditRecordView through batch API in Phase 3).

**Open questions for Ripley:**
- Use `HKMetadataKeySyncIdentifier` (Ash) **OR** custom `"com.jefftian.mybody.recordID"` + query-before-write (Ripley)? — strategies are mutually exclusive; pick one.
- Drop `HKMetadataKeyWasUserEntered` (OCR ≠ manual) **OR** keep for parity?

---

### 2026-05-24 — Trends Write-to-Health UI Options (Phase 1: UI Survey)
**By:** Lambert (iOS UI Dev)
**Status:** Recommendation pending Ripley arbitration; Phase 2 implementation will follow chosen option.

**Recon — `TrendsView`:**
- Metric switcher is **horizontal ScrollView + capsule buttons** (not `Picker`/`SegmentedControl`), `ForEach(MetricType.allCases)`.
- State: `@State viewModel = TrendsViewModel()` (`@Observable`), field `selectedMetric: MetricType = .weight`.
- `MetricChartView` + insight text both read `viewModel.selectedMetric`; `HistoryListView` is metric-agnostic.
- → "current is weight" check is **literally `viewModel.selectedMetric == .weight`** — no new binding needed.

**Existing infra (avoid rebuilding):**
- `HealthKitService.saveWeight` + `requestAuthorization()` + `HealthKitError`.
- `SettingsView` already has "同步体重到健康" global toggle (auto-sync at scan).
- ScanVM / EditRecordView already auto-write — new feature is the **manual backfill** entry.

**UI placement options:**
| Option | Position | Verdict |
|---|---|---|
| **A (recommended)** | `ToolbarItem(.topBarTrailing)` `heart.text.square`, visible iff `selectedMetric == .weight` | Standard HK-aware iOS pattern; one-line conditional; doesn't crowd chart; matches Ripley's pick. |
| B | Section between chart and insight | Metric-switch causes scroll jitter; raises first-screen density. |
| C | History row swipe action | Doesn't honor metric-only constraint; collides with delete contextMenu. |

**Localizable.xcstrings keys to add** (7 keys, zh-Hans + en):
`trends.weight.writeHealth.button` / `.a11yLabel` / `.confirm.title` / `.confirm.message` / `.success` / `.error.notAuthorized` / `.error.unavailable`.

**A11y / edge:**
- `Label("写入健康", systemImage: "heart.text.square")` + `.accessibilityLabel/Hint`.
- Reduced Motion: no spring on success toast/alert.
- `HealthKitService.shared.isAvailable == false` (rare iPad/Catalyst) → hide button (not disabled).
- **Trends entry is independent of global Settings toggle** (manual one-shot, not auto-sync) — confirmed by Ripley.

---

### 2026-05-24 — Weight Write-to-Health Test Plan (Phase 1)
**By:** Parker (Tester/QA)
**Status:** Draft — awaiting Ripley API freeze + Ash signature lock. **Hard blocker noted: `MyBodyTests` target still not in `project.yml`.**

**Testability ask (Ripley/Ash):** introduce a protocol seam so unit tests don't mock `HKHealthStore` (Apple's surface too wide):
```swift
protocol HealthKitWriting {
    var isAvailable: Bool { get }
    func authorizationStatus(for: HKQuantityTypeIdentifier) -> HKAuthorizationStatus
    func requestAuthorization() async throws
    func saveWeight(_ kg: Double, date: Date) async throws
    func saveWeights(_ samples: [(kg: Double, date: Date, dedupKey: String)]) async throws -> BulkWriteResult
}
```
`HealthKitService` conforms; tests inject `FakeHealthKitWriter`.

**Unit tests (9):** notAuthorized error, single write OK, duplicate skipped, bulk mixed (3 new/1 dup/1 invalid), empty no-op, invalidWeight filtered, unavailable throws, concurrent writes serialize, date boundary preserved. Coverage target ≥ 90% on bulk path.

**UI tests (5):** button visible on weight tab, hidden on other tabs, success feedback toast, denied-permission alert with deep-link, empty-Trends button disabled. **Needs launch args `-MOCK_HEALTH_GRANTED 1` / `-MOCK_HEALTH_DENIED 1`** (Ripley to wire).

**Manual QA checklist:** 10 items — first-permission sheet strings match Info.plist; Health source attribution "MyBody"; re-tap no duplicates; deny → Settings deep-link; toggle off in Health Sources → graceful error; iPad isAvailable=false path; zh-Hans + en strings; background mid-write; both `NSHealthShare/UpdateUsageDescription` present.

**Open questions:**
1. Dedup mechanism (Ash's `SyncIdentifier` vs Ripley's custom key + query) shapes tests U3/U8.
2. `MyBodyTests` target absence — hard blocker for unit tests; UI + manual can proceed.
3. Retroactive dedup of existing ScanViewModel/EditRecordView writes — Ripley scoping call.

### 2026-05-24 — HealthKit weight write Phase 2 implementation (Ash)
**By:** Ash (Core Engineer)
**Files:** `MyBody/Services/HealthKitService.swift` (rewrite), `MyBody/ViewModels/ScanViewModel.swift` (L189, L324), `MyBody/Views/Detail/EditRecordView.swift` (L118).

**Public API delivered for Lambert/Parker:**
- `struct HealthKitWriteResult { written, skippedInvalid, skippedDuplicate: Int; failed: [(recordID: UUID, error: Error)]; totalProcessed, failedCount }` — Sendable.
- `func writeWeightSamples(_ records: [InBodyRecord]) async throws -> HealthKitWriteResult` — batch backfill for Trends「写入健康」.
- `func saveWeight(_ kg: Double, date: Date, recordID: UUID) async throws` — new dedup-enabled single-sample path used by the 3 legacy call sites.
- `func saveWeight(_ kg: Double, date: Date) async throws` — kept for back-compat; no dedup.
- `var bodyMassWriteStatus: HKAuthorizationStatus` — Lambert can show UI hint.
- `var isAvailable: Bool` — Lambert hides toolbar item when false.
- `func requestAuthorization() async throws` — unchanged.
- `enum HealthKitError: LocalizedError { unavailable, notAuthorized, invalidValue }` — unchanged.

**Dedup mechanism — chosen: query-first + save-with-SyncIdentifier (double protection):**
- `HKMetadataKeySyncIdentifier = record.id.uuidString`, `HKMetadataKeySyncVersion = 1`, `HKMetadataKeyWasUserEntered = false`.
- Query (`HKSampleQuery` filtered by `HKSource.default()`) gives accurate `skippedDuplicate` count for Jeff's "written/skipped/failed" dialog (HK auto-dedup-by-replace does NOT report which samples were replaced).
- Save still carries SyncIdentifier so query→save races (or query misses) are auto-resolved by HK's replace-by-version semantics.

**Error semantics:**
- Pre-flight failures (`unavailable`, `notAuthorized`) → `throws`. Lambert shows alert + system Settings deep-link.
- Per-sample failures → aggregated into `result.failed`, never thrown. Lambert shows count in dialog.
- Batch `store.save([HKObject])` is atomic; on failure we degrade to per-sample save to pinpoint failing records.

**Concurrency:** `writeWeightSamples` reads `record.weight/scanDate/id` synchronously into local `Candidate` value-type structs BEFORE the first `await`. Avoids cross-actor SwiftData `@Model` access under Swift 6 isolation. Lambert can safely call from `@MainActor`.

**Refactored call sites:** all 3 legacy `try? saveWeight(weight, date:)` now pass `recordID: record.id`. Each extracts primitives before `Task.detached` to keep `InBodyRecord` on its origin actor.

**Build:** `make build` ✅.

**Reversed earlier decision:** `HKMetadataKeyWasUserEntered` is now `false` (was `true`). OCR-derived ≠ manual entry; Health App "data sources" attribution is more honest.

**Not addressed (out of Phase 2 scope):** `HealthKitWriting` protocol seam Parker requested for unit-test mocking; `MyBodyTests` target absence from `project.yml`. Both still blocking Parker's U1–U9 tests.
### 2026-05-24: Lambert — Trends 体重→Health 写入 UI 模式
**By:** Lambert
**What:** UI 用 `WeightHealthWriteController: @Observable` + `WeightHealthWriteOverlay: ViewModifier` 模式承接 `HealthKitService.writeWeightSamples`。三档范围（全部历史/当前图表范围/最近 30 天，默认全部历史）走 `.confirmationDialog`；写入中用半透明 `ProgressView` 蒙层；结果走 `.alert` 显示 written/skippedDuplicate/skippedInvalid/failed 计数；失败明细走子 `.sheet`。授权拒绝（`HealthKitError.notAuthorized`）专门的错误 alert 提供「打开设置」深链 `UIApplication.openSettingsURLString`。
**Why:** 把交互/状态/Service 调用从 `TrendsView` 抽离，body 只多一行 `.modifier`；后续做 Body Fat / 其它指标 HK 写入可复制 controller 重用模式。`recordsForRange` 闭包注入让 controller 不依赖 SwiftData / `TrendsViewModel`，可独立测试。
### 2026-05-24 — Weight Write-to-Health Phase 2 Test Implementation
**By:** Parker (Tester/QA)
**Status:** 9 active tests + 6 `XCTSkip` stubs landed in `MyBodyTests/Services/HealthKitWeightWriteTests.swift`. Build currently **blocked on Lambert** — `WeightHealthWriteSheet.swift` has 2 compile errors (see below). My file parses cleanly in isolation.

**Phase 1 self-correction:** My "MyBodyTests target absent" hard blocker was wrong — the target was already in `project.yml` (target block ~ line 130 + scheme `test.targets` entry ~ line 26). Apologies for the noise; will trust `project.yml` over the test-folder layout next time.

**What landed in `HealthKitWeightWriteTests.swift`:**
- **3 sync-identifier tests** — deterministic format `"mybody.inbody.\(uuid)"`, idempotency, uniqueness across records.
- **5 pre-flight filter tests** — empty input, nil weight, zero/negative weight, valid weight, mixed batch. Use test-local `Self.partitionForWrite(_:)` mirroring Ash's spec (delete once Ash exports the helper).
- **2 `HealthKitWriteResult` aggregation tests** — totals across categories, all-written happy path. Use local `MockWriteResult` (delete once Ash's real struct is reachable from tests — currently it is, but I avoided the bind to keep the file compile-safe even if the API shifts).
- **6 `XCTSkip` stubs** with detailed expected-behavior strings — covers notAuthorized, unavailable, duplicate SyncIdentifier, concurrent serialization, metadata round-trip, date-boundary preservation. All require a fakeable HK seam.

**Critical finding for Ripley/Ash arbitration:** Ash shipped `writeWeightSamples(_:)` without extracting `protocol HealthKitWriting` (the seam I requested in Phase 1). The method touches `HKHealthStore` directly with `query → save` round-trip. Consequence: 6 of the 9 most valuable unit tests can't activate. **Ask:** retrofit the protocol seam (1 file edit on `HealthKitService`, plus `FakeHealthKitWriter` in tests), OR accept that those 6 paths are tested only by manual QA + UI tests. Charter bias: I want the protocol; not a release blocker if Jeff disagrees.

**Build break I am NOT fixing (not my code):**
- `MyBody/Views/Trends/WeightHealthWriteSheet.swift:10` — `WeightHealthWriteController.Phase` enum needs `: Equatable` conformance (SwiftUI `onChange(of:)` likely).
- `MyBody/Views/Trends/WeightHealthWriteSheet.swift:59` — `HealthKitWriteResult(...)` call has `skippedDuplicate:` before `skippedInvalid:`. Ash's struct field order is `written, skippedInvalid, skippedDuplicate, failed`. Lambert needs to swap.

**UI tests:** Deferred. `MyBodyUITests/HealthKitWeightWriteUITests.swift.TODO` documents all 5 cases + required launch args (`-MOCK_HEALTH_GRANTED`, `-MOCK_HEALTH_DENIED`, `-MOCK_HEALTH_EMPTY`). File extension is `.TODO` (not `.swift`) so xcodegen + xcodebuild ignore it; rename when Ripley wires the mocks.

**Test execution result:** `make test-unit` → build error 65, did NOT reach the test phase. Neither pass nor fail counts available for my new file until Lambert's 2 errors are resolved (then I should re-run and confirm 9 pass + 6 skipped).


### 2026-05-24: Batch re-parse path for end-of-batch "重新识别 duplicates"
**By:** Ash (Core/Vision/OCR)
**What:** Added `duplicateAssetIds: [String]`, `reparseIndex`/`reparseTotal: Int`, and `@MainActor func reparseDuplicateRecords() async -> (succeeded, failed, errors)` to `ScanViewModel`. Duplicate asset IDs are now collected (not just counted) in the dedup branch of `parseNextPhoto()`. The new sweep method iterates duplicates, fetches each `InBodyRecord` by `photoAssetIdentifier` predicate, and delegates per-record to existing static `reparseExistingReport(...)` — best-effort, failures collected into errors array, loop continues. Progress fields are deliberately separate from batch-scan progress to avoid UI state collisions. `duplicateAssetIds` is NOT cleared at end so UI can render "X / Y 已更新" summary.
**Why:** Earlier dedup was destructive (count-only) — there was no way to surface "these N photos already had records" to the user or to act on them. New flow keeps initial-scan dedup behavior intact while enabling a second, explicitly user-confirmed re-OCR pass.
**Contract for Lambert (UI):** call `await scanVM.reparseDuplicateRecords()`; show progress via `reparseIndex`/`reparseTotal` + `parseStageMessage` (already in 中文); render result tuple as summary. Tests stay green (`make test-unit` 18/0/6).

### 2026-05-24: 批量导入完成后弹窗询问是否对去重报告重新识别
**By:** Lambert (UI)
**What:** `PhotoScanView` 在 `batchFinished` 时若 `duplicateAssetIds` 非空，弹 alert「重新识别已有报告？」，按钮「重新识别」(default) / 「跳过」(cancel)。「跳过」直接关闭 sheet；「重新识别」展示 dim+material overlay（文案绑 `reparseIndex/reparseTotal`），完成后顶部 capsule banner 显示「已更新 X 条」(`appGreen`) 或「已更新 X 条，Y 条失败」(`appOrange`)，2.5s 后 `dismiss()`。
**Why:** 去重保证幂等的同时，老照片不能享受 OCR 引擎升级；显式询问而非自动跑，避免覆盖用户已手编辑数据时的预期错位。复用 DetailView 单条 reparse 的视觉语言保持一致。

### 2026-05-24: HealthKitWriting protocol seam (Phase 2.5)
**By:** Ash (Core Engineer)
**What:** Extracted `protocol HealthKitWriting` from `HealthKitService` exposing 5 members used by Trends/Edit/Scan call sites: `isAvailable`, `bodyMassWriteStatus`, `requestAuthorization()`, `writeWeightSamples(_:)`, `saveWeight(_:date:recordID:)`. `HealthKitService` conforms; `shared` stays concrete. Internal query helpers, `HKHealthStore` ref, and legacy `saveWeight(_:date:)` overload NOT on protocol. Also lifted `static HealthKitService.partitionForWrite(_:now:)` so fake reuses the same `weight > 0 && scanDate <= now` filter as production (no drift). `FakeHealthKitWriter` (MyBodyTests/Services/) conforms with auth/availability/duplicate/failure knobs + thread-safe call recording, mirroring production pre-flight order (device → auth → partition → categorize).
**Why:** Unblocks Parker's 6 XCTSkip'd HealthKit tests without touching `HKHealthStore` directly (Parker charter forbids). No signature changes, no call-site refactors, `InBodyRecord` + `HealthKitWriteResult` shapes preserved (Lambert-safe). Ripley arbitration GO confirmed by Jeff.

### 2026-05-24: HealthKit Phase 1 + 2 unit tests fully activated (18/0/0)
**By:** Parker (Tester/QA)
**What:** Replaced 6 XCTSkip stubs in `MyBodyTests/Services/HealthKitWeightWriteTests.swift` with real tests against Ash's `FakeHealthKitWriter`: notAuthorized throws, unavailableDevice throws, recordID flow-through, duplicate skip (preExistingRecordIDs), scanDate preservation, concurrent `async let` batches aggregate correctly. `make test-unit` → 18/0/0 (was 18/0/6).
**Why:** Adaptation: fake records input `[InBodyRecord]` per bulk call, not per-sample HKQuantitySample saves — so metadata/date tests re-aimed at fake's observable surface (recordID + scanDate pass-through). HK `HKMetadataKeySyncIdentifier` invariant becomes production-only, deferred to integration tests when `HealthKitWeightWriteUITests.swift.TODO` lands. Drift documented inline. All Phase 1 + 2 unit-test scope green; ScanViewModel/EditRecordView can now be DI-tested via the protocol without HKHealthStore.

### 2026-05-24: iCloud 照片导入兜底自动下载
**By:** Ash (requested by Jeff Tian)
**What:** `PhotoScanService.requestImageSync` 新增 `allowNetwork` 参数。
- **Scan 阶段**（粗筛全相册）：受 Settings 开关 `iCloudPhotoDownload` 控制，默认 `false`，仅用本地缓存（避免对大量无关照片触发 iCloud 下载、消耗流量）。
- **Parse 阶段** (`loadFullImage`)：始终 `allowNetwork=true`，保证用户确认导入后能拿到 iCloud 原图，避免出现「只有📄图标、无图无数据」的空记录。
- Settings 文案同步更新，把开关定位为"扫描时也下载 iCloud 照片"，并说明 parse 阶段始终自动下载。

**Why:** 截图里 2026-05-19 / 05-20 那种空记录的根因 — iCloud 原图未下载、`loadFullImage` 返回 nil、ScanViewModel 回退保存空记录。修复后导入路径具备 iCloud 自动下载兜底。

**Scope:** 仅前向修复。已存在的空记录不做回填（用户可手动重新导入）。

### 2026-05-24: SwiftUI alert presentation must not depend on overlay/state-machine state
**By:** Lambert (iOS UI Dev)
**Scope:** Team-wide SwiftUI pattern. Applies to any view using `.alert(_:isPresented:presenting:actions:message:)` alongside `.overlay`, `.sheet`, or `confirmationDialog` driven by the same state machine.

**What:** When presenting an `.alert(...)` whose visibility depends on a state machine that also drives other overlays/sheets on the same view, you **MUST**:
1. Snapshot the alert's payload (`presenting:` value) into a **dedicated stored optional** on the view-model.
2. Bind `isPresented` to `Binding(get: { snapshot != nil }, set: { if !$0 { snapshot = nil } })`.
3. Bind `presenting:` directly to that stored optional.
4. Every alert button action MUST explicitly set `snapshot = nil` if it should dismiss.

**Do NOT** derive `presenting:` from a computed property reading an enum/state-machine case (e.g. `if case .result(let r) = phase { return r }`). SwiftUI will cancel the alert presentation if the derived value transitions to `nil` during a sibling view's teardown in the same render transaction.

**Why:** Concrete bug hit in TrendsView 写入完成 / 需要健康权限 alerts. `WeightHealthWriteController.phase: Phase` is `.idle → .writing → .result | .error`. Host view had `.overlay { if ctrl.isWriting { ... } }` + two `.alert(...)`. When `phase = .result(...)` fired, ONE SwiftUI transaction (1) dismissed confirmationDialog, (2) tore down overlay (`isWriting` flipped false), (3) tried to present result alert. Because `presenting:` was computed from `phase`, the alert's value-check raced with overlay teardown. Alert presented for ~1 frame then SwiftUI cancelled it. Decoupling alert payload (stored `pendingResult: HealthKitWriteResult?`) from state machine fixes this: once `pendingResult` is set, only user dismissal nils it.

**Where applied:** `MyBody/Views/Trends/WeightHealthWriteSheet.swift` (`pendingResult` + `pendingError: ErrorInfo?`), `MyBody/Views/Trends/TrendsView.swift` (alert bindings on `WeightHealthWriteOverlay`).

**Watch for this in:** Any future view combining (a) state-machine VM (`@Observable` controller with enum-driven `phase`), (b) `.overlay`/`.sheet`/`confirmationDialog` reading from that state, (c) `.alert(...presenting:)` whose value also reads from that state. Apply the same dedicated-optional pattern before shipping.

### 2026-05-30: 全屏看图加入缩放/平移交互
**By:** Lambert (iOS UI Developer), requested by Jeff Tian
**What:** 在 `MyBody/Views/Detail/DetailView.swift` 的 `FullPhotoView` 中加入双指捏合缩放(1x–4x)、双击切换(1x↔2.5x)、放大后拖动平移(带边界 clamp，超界回弹/小于1x归位)。图片逻辑抽到 private `ZoomablePhoto`，保留原有关闭按钮。
**Why:** 报告照片需要放大查看 InBody 细节数字，原查看器只能 .fit 静态显示。
**Scope note:** `FullPhotoView` 为 DetailView 与 EditRecordView 共用组件，本次改动同时惠及两处看图入口。`make build` 通过。
