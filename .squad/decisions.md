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
