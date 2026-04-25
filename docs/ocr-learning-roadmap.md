# OCR 识别"越用越准"路线图

本文档记录 InBody 报告 OCR 识别的本地化学习能力演进。所有方案都只在设备端运行，不依赖服务器或第三方 API，保持 App 的隐私承诺。

## 背景

识别管线由 Apple 原生框架组成：

- **OCR**：`Vision` 的 `VNRecognizeTextRequest`（闭源、不可微调）。
- **字段解析**：自写的空间坐标 + 关键字规则，见 [OCRService.parseBoxes](../MyBody/Services/OCRService.swift)。
- **持久化**：SwiftData。

能"越用越准"的层是**字段解析**与**版式识别**，而非 OCR 文字识别本身。

## 已完成（Phase 1）

**目标**：用户在编辑页修正字段后，把修正反馈到下一次相同 OCR 输出。

- [MyBody/Models/OCRCorrection.swift](../MyBody/Models/OCRCorrection.swift) — SwiftData 模型：`(fieldName, 归一化 rawText) → correctedValue`，附 `useCount`。
- [MyBody/Services/OCRCorrectionStore.swift](../MyBody/Services/OCRCorrectionStore.swift) — 主 actor 上的 upsert/lookup 包装。
- [MyBody/Models/InBodyRecord.swift](../MyBody/Models/InBodyRecord.swift) — 新增 `ocrRawTextsJSON` 存每个字段命中的原始 OCR 文本。
- [MyBody/Services/OCRService.swift](../MyBody/Services/OCRService.swift) — `parseBoxes` 接受 `corrections:` 闭包，命中即替换解析值。
- [MyBody/ViewModels/ScanViewModel.swift](../MyBody/ViewModels/ScanViewModel.swift) — 解析前把全部纠正拍快照传给后台线程，命中后主 actor 累加 `useCount`。
- [MyBody/Views/Detail/EditRecordView.swift](../MyBody/Views/Detail/EditRecordView.swift) — 进入拍快照，保存时 diff，差异字段写入 `OCRCorrection`。
- [MyBody/MyBodyApp.swift](../MyBody/MyBodyApp.swift) — 注册新模型到 `ModelContainer`。

**局限**：只有 OCR 原始文本"字节级一致"才会命中，跨报告迁移能力弱。

## Phase 2：UI 可见性（低成本高价值）

**目标**：给用户透明度与控制权，也方便自己调试。

- [ ] [SettingsView.swift](../MyBody/Views/SettingsView.swift) 新增"学习记录"入口：
  - 展示 `OCRCorrection` 条数、总 `useCount`。
  - 列表（按 `updatedAt` 倒序）可删除单条。
  - "清空学习记录"按钮（需二次确认）。
- [ ] [EditRecordView.swift](../MyBody/Views/Detail/EditRecordView.swift) 字段右侧加一个小标识：该字段本次是 OCR 原始解析还是由 `OCRCorrection` 自动替换（`useCount > 0`）。
- [ ] 扫描完成汇总页显示"本次应用了 N 条历史修正"。

## Phase 3：字段关键字 / customWords 自学习

**目标**：新版 InBody 报告把"骨骼肌量"印成"骨肌量"时，App 用一次就记住。

- [ ] 扩展 `OCRCorrection`：当用户在编辑页给某字段填值、但该字段本次 `rawTexts` 里没有命中原文时，弹一个轻量 Sheet 让用户从 OCR 识别到的 box 文本里点选"这个文本就是该字段的标签"。
- [ ] 新模型 `OCRFieldAlias(fieldName, alias)`：持久化用户选中的别名，下次解析时把 `alias` 动态并入 `FieldSpec.keys`。
- [ ] 把 `OCRService.runRecognition` 里的 `request.customWords` 改成「硬编码基础表 + `OCRFieldAlias` 里的用户积累」的合并结果。

**风险**：别名可能污染匹配（例如误把数字框指为标签）。需要在 UI 侧校验——只允许点选"明显是文字、不含数字"的 box。

## Phase 4：版式指纹 + 坐标 anchor（核心增益）

**目标**：同一台 InBody 机器输出的报告版式稳定，用一次版式就能让所有后续同款报告准确率拉满。

- [ ] 新模型 `ReportLayoutFingerprint`：
  - `fingerprint: String` —— 基于报告上稳定文字（"InBody"、"人体成份分析"、表头等）归一化坐标 hash 得到。
  - `fieldAnchors: Data` —— JSON，`[字段名: {labelBox: CGRect, valueBox: CGRect}]`。
- [ ] 解析流程改造：
  1. 先算 fingerprint，查表。
  2. **命中**：跳过全局启发式，直接按 `fieldAnchors` 里的 `valueBox` 取最近数字 box。识别失败再降级回现有规则。
  3. **未命中**：走现有规则；若用户之后在编辑页改动了任何字段，记录本次报告的 fingerprint + 各字段命中的 `labelBox` / `valueBox`。
- [ ] 用户删除某条 fingerprint 的入口放在 Phase 2 的"学习记录"页。

**命中率保守估计**：用户主力机型报告识别准确率 → 90%+，且随使用次数单调不降。

## Phase 5：合理值区间自适应

**目标**：把 `FieldSpec.expected` 从硬编码改成以"用户历史数据 ±N 倍标准差"动态收紧，过滤 OCR 少点 / 多点错误（如 `65.2 kg` 被识别为 `652`）。

- [ ] `OCRService.parseBoxes` 接受一个 `personalRanges: [String: ClosedRange<Double>]?` 参数。
- [ ] `ScanViewModel` 在解析前从 `InBodyRecord` 历史数据计算每个字段的个人区间（例如最近 30 条 ±30%）。
- [ ] 若个人区间比硬编码 `expected` 更窄，用前者；否则退回后者（冷启动保护）。

## 明确不做

- ❌ **自训练 OCR 模型**：设备端成本高，收益有限（Vision 对数字表格已足够）。
- ❌ **联邦学习 / 跨用户共享**：破坏"本地优先、零服务器"的隐私承诺。
- ❌ **云端纠错同步**：若未来做 iCloud 同步，`OCRCorrection` 随 SwiftData 的 CloudKit 容器走即可，不引入自建后端。

## 路线图优先级

| Phase | 价值 | 成本 | 建议次序 |
|---|---|---|---|
| 1 | 中（同图重扫会准） | 低 | ✅ 已完成 |
| 2 | 低直接价值，中调试价值 | 低 | 紧接 Phase 1 |
| 4 | 高（跨报告迁移） | 中 | 次之 |
| 3 | 中（新版式鲁棒性） | 中 | 可与 Phase 4 并行 |
| 5 | 低（防御性） | 低 | 有空再做 |
