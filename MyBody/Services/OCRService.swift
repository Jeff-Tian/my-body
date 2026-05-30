import Foundation
import Vision
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

final class OCRService: Sendable {

    struct ParsedReport {
        var scanDate: Date?
        var scanTime: String?
        var weight: Double?
        var skeletalMuscle: Double?
        var bodyFatMass: Double?
        var totalBodyWater: Double?
        var leanBodyMass: Double?
        var bmi: Double?
        var bodyFatPercent: Double?
        var whr: Double?
        var bmr: Double?
        var inbodyScore: Int?
        var visceralFatLevel: Int?
        var dailyCalorie: Double?
        var segMuscleLeftArm: Double?
        var segMuscleRightArm: Double?
        var segMuscleTrunk: Double?
        var segMuscleLeftLeg: Double?
        var segMuscleRightLeg: Double?
        var segFatLeftArm: Double?
        var segFatRightArm: Double?
        var segFatTrunk: Double?
        var segFatLeftLeg: Double?
        var segFatRightLeg: Double?
        var failedFields: Set<String> = []

        /// 解析时每个成功字段命中的 OCR 原始 box 文本。
        /// 用于把 "OCR 看到了什么" 写入 `InBodyRecord`，再在用户修正时反馈给 `OCRCorrection`。
        var rawTexts: [String: String] = [:]

        func toRecord(photoData: Data?, assetIdentifier: String?) -> InBodyRecord {
            let rawJSON = try? JSONEncoder().encode(rawTexts)
            return InBodyRecord(
                scanDate: scanDate ?? Date(),
                scanTime: scanTime,
                weight: weight,
                skeletalMuscle: skeletalMuscle,
                bodyFatMass: bodyFatMass,
                totalBodyWater: totalBodyWater,
                leanBodyMass: leanBodyMass,
                bmi: bmi,
                bodyFatPercent: bodyFatPercent,
                whr: whr,
                bmr: bmr,
                inbodyScore: inbodyScore,
                visceralFatLevel: visceralFatLevel,
                dailyCalorie: dailyCalorie,
                segMuscleLeftArm: segMuscleLeftArm,
                segMuscleRightArm: segMuscleRightArm,
                segMuscleTrunk: segMuscleTrunk,
                segMuscleLeftLeg: segMuscleLeftLeg,
                segMuscleRightLeg: segMuscleRightLeg,
                segFatLeftArm: segFatLeftArm,
                segFatRightArm: segFatRightArm,
                segFatTrunk: segFatTrunk,
                segFatLeftLeg: segFatLeftLeg,
                segFatRightLeg: segFatRightLeg,
                photoData: photoData,
                photoAssetIdentifier: assetIdentifier,
                ocrRawTextsJSON: rawJSON
            )
        }
    }

    /// 一段 OCR 识别结果，附带归一化的 bounding box(左下原点, 0~1)。
    struct TextBox: Sendable {
        let text: String
        let box: CGRect  // Vision 原生坐标: 左下角原点
        var cx: CGFloat { box.midX }
        var cy: CGFloat { box.midY }
        var left: CGFloat { box.minX }
        var right: CGFloat { box.maxX }
    }

    /// Perform OCR synchronously — no completion handler, no continuation.
    /// VNRecognizeTextRequest.results is populated after perform() returns.
    func recognizeText(from image: UIImage) throws -> [String] {
        try recognizeBoxes(from: image).map { $0.text }
    }

    /// 带 bounding box 的识别结果。InBody 报告是多列表格布局,
    /// 必须用空间坐标把标签和数字配对,否则单靠阅读顺序会串行错位。
    func recognizeBoxes(from image: UIImage) throws -> [TextBox] {
        guard let cgImage = image.cgImage else { return [] }

        // 先跑一遍预处理(灰度+对比度拉伸+锐化);若预处理版识别到的数字多,就用预处理版。
        let processed = preprocess(cgImage: cgImage)

        let primary = try runRecognition(on: processed ?? cgImage)
        // 如果预处理版数字 box 数偏少,再回退到原图尝试一次,取识别到的文本更多的一版
        if processed != nil {
            let fallback = (try? runRecognition(on: cgImage)) ?? []
            return primary.count >= fallback.count ? primary : fallback
        }
        return primary
    }

    private func runRecognition(on cgImage: CGImage) throws -> [TextBox] {
        let request = VNRecognizeTextRequest()

        // ── 跨设备确定性:固定 Vision 文字识别模型版本 ──────────────────────
        // ⚠️ 不固定 revision 时,Vision 会在每台设备上选用当前 iOS 能提供的
        // **最新**模型版本。不同 iPhone(不同 iOS 版本)因此会用不同的
        // text-recognition 模型,对同一张报告产生不同的 box 切分/几何/阅读顺序。
        // 下游字段解析完全依赖 box 几何与文本,所以这会直接导致"同一张报告在
        // A 手机识别成 68.1kg、在 B 手机识别成 60.0kg(且体脂肪 100kg)"这类
        // 设备相关的串字段 bug。固定到 revision 3(iOS 16+ 提供,本 App 最低
        // iOS 17)即可让 OCR 在所有设备上确定一致。若该 revision 在某设备上
        // 不可用(理论上不会发生),则不设置,退回系统默认。
        let pinnedRevision = VNRecognizeTextRequestRevision3
        if VNRecognizeTextRequest.supportedRevisions.contains(pinnedRevision) {
            request.revision = pinnedRevision
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.008  // 允许较小字号,表格单元格常很密
        request.customWords = [
            "InBody", "BMI", "BMR", "SMM", "BFM", "TBW", "LBM", "FFM", "PBF", "BFP",
            "WHR", "VFL", "骨骼肌", "体脂肪", "体水分", "去脂体重", "腰臀比",
            "内脏脂肪", "基础代谢", "体脂百分比", "体脂率", "人体成份分析",
            "身体水分总量", "肌肉脂肪分析", "肥胖分析", "节段肌肉", "节段脂肪"
        ]
        #if targetEnvironment(simulator)
        // Workaround: iOS Simulator 的 Metal API Validation 会对 Vision 内部
        // 使用的 shared-storage Metal 纹理调用 synchronizeResource 触发断言崩溃。
        // 在模拟器上强制 Vision 走 CPU 路径,真机不受影响。
        request.usesCPUOnly = true
        #endif

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let results = request.results ?? []
        return results.compactMap { obs in
            guard let cand = obs.topCandidates(1).first else { return nil }
            return TextBox(text: cand.string, box: obs.boundingBox)
        }
    }

    /// 对手机拍摄的 InBody 报告做 OCR 预处理:
    /// 灰度化 → 对比度拉伸 → 轻微锐化。可显著提升打印表格的识别率。
    private func preprocess(cgImage: CGImage) -> CGImage? {
        let ctx = CIContext(options: nil)
        var img = CIImage(cgImage: cgImage)

        // 1. 灰度 + 对比度
        let color = CIFilter.colorControls()
        color.inputImage = img
        color.saturation = 0
        color.contrast = 1.25
        color.brightness = 0.02
        if let out = color.outputImage { img = out }

        // 2. 锐化(unsharp mask)
        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = img
        sharpen.radius = 1.5
        sharpen.intensity = 0.6
        if let out = sharpen.outputImage { img = out }

        return ctx.createCGImage(img, from: img.extent)
    }

    func parseReport(from image: UIImage) throws -> ParsedReport {
        let boxes = try recognizeBoxes(from: image)
        return parseBoxes(boxes)
    }

    /// 带用户纠正反馈的解析入口。`corrections(fieldName, rawText)` 命中时将直接替换解析值。
    func parseReport(
        from image: UIImage,
        corrections: ((String, String) -> Double?)?
    ) throws -> ParsedReport {
        let boxes = try recognizeBoxes(from: image)
        return parseBoxes(boxes, corrections: corrections)
    }

    func parseLines(_ lines: [String]) -> ParsedReport {
        // 无 bbox 的退化路径:把每段文本伪造一个横条 box(同一行),
        // 使后续空间算法仍能跑,但准确度会降低。
        let boxes = lines.enumerated().map { (i, text) -> TextBox in
            let y = 1.0 - (CGFloat(i) + 0.5) / CGFloat(max(lines.count, 1))
            return TextBox(text: text, box: CGRect(x: 0, y: y, width: 1, height: 0.01))
        }
        return parseBoxes(boxes)
    }

    /// 基于空间坐标解析:对每个字段关键字,找到包含该关键字的 TextBox,
    /// 然后在"同一水平带内右侧"或"正下方邻近列"寻找最近的数字 box。
    func parseBoxes(_ boxes: [TextBox]) -> ParsedReport {
        parseBoxes(boxes, corrections: nil)
    }

    /// 同 `parseBoxes(_:)`，额外接受一个纠正查询闭包：命中 `(fieldName, rawText)`
    /// 就把解析值直接替换为用户历史修正值。
    func parseBoxes(
        _ boxes: [TextBox],
        corrections: ((String, String) -> Double?)?
    ) -> ParsedReport {
        var report = ParsedReport()
        let allText = boxes.map { $0.text }.joined(separator: "\n")

        // Date / Time 用全文正则即可
        report.scanDate = extractDate(from: allText)
        if report.scanDate == nil { report.failedFields.insert("scanDate") }
        report.scanTime = extractTime(from: allText)

        // key -> fieldName 映射,按出现频率排列关键字(优先短且独特的)
        struct FieldSpec {
            let name: String
            let keys: [String]
            let intValue: Bool
            /// 合理值区间,用于在多个数字候选里挑对的那个。
            let expected: ClosedRange<Double>
        }
        let specs: [FieldSpec] = [
            .init(name: "weight",           keys: ["体重", "Weight"],                                       intValue: false, expected: 20...250),
            .init(name: "skeletalMuscle",   keys: ["骨骼肌量", "骨骼肌", "Skeletal Muscle", "SMM"],           intValue: false, expected: 5...60),
            .init(name: "bodyFatMass",      keys: ["体脂肪量", "体脂肪", "Body Fat Mass", "BFM"],             intValue: false, expected: 1...100),
            .init(name: "totalBodyWater",   keys: ["身体水分总量", "身体水分", "体水分", "Total Body Water", "TBW"], intValue: false, expected: 10...80),
            .init(name: "leanBodyMass",     keys: ["去脂体重", "瘦体重", "Lean Body Mass", "LBM", "FFM"],     intValue: false, expected: 20...150),
            .init(name: "bmi",              keys: ["BMI"],                                                   intValue: false, expected: 8...60),
            .init(name: "bodyFatPercent",   keys: ["体脂肪百分比", "体脂百分比", "体脂率", "PBF", "BFP"],       intValue: false, expected: 1...70),
            .init(name: "whr",              keys: ["腰臀比", "WHR"],                                         intValue: false, expected: 0.5...1.5),
            .init(name: "bmr",              keys: ["基础代谢率", "基础代谢", "BMR", "Basal Metabolic"],        intValue: false, expected: 500...3500),
            .init(name: "inbodyScore",      keys: ["InBody评分", "InBody Score", "身体评分", "总分"],         intValue: true,  expected: 20...120),
            .init(name: "visceralFatLevel", keys: ["内脏脂肪等级", "内脏脂肪", "Visceral Fat", "VFL"],        intValue: true,  expected: 1...30),
            .init(name: "dailyCalorie",     keys: ["每日所需热量", "日推荐摄入", "Daily Calorie"],             intValue: false, expected: 600...5000)
        ]

        var values: [String: Double] = [:]
        // All known field keys (used to detect competing labels on the same row, e.g.
        // 身体水分含量 and 去脂体重 sit side-by-side in the InBody 230 layout).
        let allOtherKeys: [String] = specs.flatMap { $0.keys }
        for spec in specs {
            let competitorKeys = allOtherKeys.filter { k in !spec.keys.contains(k) }
            if let hit = findValue(for: spec.keys, in: boxes, expected: spec.expected, competitorKeys: competitorKeys) {
                // 先看用户是否已经为这段原始文本登记过纠正
                if let corrected = corrections?(spec.name, hit.rawText) {
                    values[spec.name] = corrected
                } else {
                    values[spec.name] = hit.value
                }
                report.rawTexts[spec.name] = hit.rawText
            } else {
                report.failedFields.insert(spec.name)
            }
        }

        // Pattern F (Trusted Override) — 运动处方段落里 "基础体重：68.1 kg" 是普通印刷文本,
        // 比柱状图行(常被 Vision 误读成 "w00.1kg" 或抓到坐标轴刻度如 "238")可靠得多。
        // 当能从这段抽到值时,优先采信它,无论主路径是否给出了值。
        // 注:若样张里没有这段(老报告/裁剪过的图),helper 返回 nil,主路径值原样保留。
        if let trusted = extractWeightFromExercisePrescription(
            boxes: boxes,
            expected: 20...250
        ) {
            if let corrected = corrections?("weight", trusted.rawText) {
                values["weight"] = corrected
            } else {
                values["weight"] = trusted.value
            }
            report.rawTexts["weight"] = trusted.rawText
            report.failedFields.remove("weight")
        }

        report.weight           = values["weight"]
        report.skeletalMuscle   = values["skeletalMuscle"]
        report.bodyFatMass      = values["bodyFatMass"]
        report.totalBodyWater   = values["totalBodyWater"]
        report.leanBodyMass     = values["leanBodyMass"]
        report.bmi              = values["bmi"]
        report.bodyFatPercent   = values["bodyFatPercent"]
        report.whr              = values["whr"]
        report.bmr              = values["bmr"]
        if let v = values["inbodyScore"]      { report.inbodyScore      = Int(v) }
        if let v = values["visceralFatLevel"] { report.visceralFatLevel = Int(v) }
        report.dailyCalorie     = values["dailyCalorie"]

        // Segmental:保留原有行级逻辑作兜底
        let lines = boxes.map { $0.text }
        let segMuscle = extractSegmental(from: lines, section: "肌肉", allText: allText)
        report.segMuscleLeftArm  = segMuscle.leftArm
        report.segMuscleRightArm = segMuscle.rightArm
        report.segMuscleTrunk    = segMuscle.trunk
        report.segMuscleLeftLeg  = segMuscle.leftLeg
        report.segMuscleRightLeg = segMuscle.rightLeg

        let segFat = extractSegmental(from: lines, section: "脂肪", allText: allText)
        report.segFatLeftArm  = segFat.leftArm
        report.segFatRightArm = segFat.rightArm
        report.segFatTrunk    = segFat.trunk
        report.segFatLeftLeg  = segFat.leftLeg
        report.segFatRightLeg = segFat.rightLeg

        // 跨字段物理合理性校验:丢弃明显不可能的串字段值(例如体脂肪 ≥ 体重)。
        applyCrossFieldValidation(&report)

        return report
    }

    /// 跨字段物理合理性校验(防 OCR 串字段写入脏数据)。
    ///
    /// 每个字段的 `expected` 只是**单字段**硬区间,无法识别"单看在区间内、
    /// 但相对体重不可能"的值 —— 例如跨设备误读出的 `体脂肪 100.0 kg` 对
    /// `体重 60.0 kg`(60kg 的身体不可能有 100kg 脂肪)。该值能通过
    /// `bodyFatMass.expected`(1...100),但物理上是垃圾。
    ///
    /// 规则:所有质量分量(骨骼肌、体脂肪、身体水分、去脂体重)都必须**小于
    /// 体重**。2% 容差吸收 OCR 取整 / 去脂体重接近体重的情形。任一违规者
    /// 直接置 nil 并记入 `failedFields`、从 `rawTexts` 移除 —— UI 会显示
    /// "未识别"(提示重扫 / 手动输入),而不是把脏值存库再写进 HealthKit。
    ///
    /// 仅在 `weight` 自身解析成功时运行:没有可信的体重锚点就无法判断分量,
    /// 此时保持原样不动。
    private func applyCrossFieldValidation(_ report: inout ParsedReport) {
        guard let weight = report.weight, weight > 0 else { return }
        // 分量不得超过体重(+2% OCR 容差)。
        let ceiling = weight * 1.02

        func reject(_ value: Double?, field: String) -> Double? {
            guard let v = value else { return nil }
            if v >= ceiling {
                report.failedFields.insert(field)
                report.rawTexts.removeValue(forKey: field)
                return nil
            }
            return value
        }

        report.skeletalMuscle = reject(report.skeletalMuscle, field: "skeletalMuscle")
        report.bodyFatMass    = reject(report.bodyFatMass,    field: "bodyFatMass")
        report.totalBodyWater = reject(report.totalBodyWater, field: "totalBodyWater")
        report.leanBodyMass   = reject(report.leanBodyMass,   field: "leanBodyMass")
    }

    /// 从 InBody 230 "运动处方" 段落抽取"基础体重"印刷数值。
    ///
    /// Vision 通常把这一行拆成两个 box,例如:
    ///   `每项运动所消耗的能量（基础体重：` (左侧 cx≈0.26 cy≈0.31)
    ///   `68.1 kg /持续时间：30分钟/单位：大卡）` (右侧 cx≈0.47 cy≈0.30)
    /// 也可能(在其他样张里)拼成单个 box `... 基础体重：68.1 kg ...`。
    ///
    /// 算法:
    /// 1. 先在所有 box 上正则匹配 `基础体重[：:]\s*(\d+(?:\.\d+)?)\s*kg`,
    ///    捕获到合法数字就返回。
    /// 2. 若 1 失败,定位包含 `基础体重` 的 box(label box),
    ///    在同行右侧(rowTol = max(h,0.012)*1.8)找 box,
    ///    用 `(\d+(?:\.\d+)?)\s*kg` 抽取数字。
    ///
    /// 容错:文本里如出现 `68. 1 kg`(Vision 偶发的"小数点后空格"),先做合并再匹配。
    private func extractWeightFromExercisePrescription(
        boxes: [TextBox],
        expected: ClosedRange<Double>
    ) -> (value: Double, rawText: String)? {
        // 把 "68. 1 kg" / "68 . 1kg" 规范化为 "68.1 kg",和 primaryNumber 保持一致。
        func normalize(_ s: String) -> String {
            s.replacingOccurrences(
                of: #"(\d)\s*\.\s+(\d)"#,
                with: "$1.$2",
                options: .regularExpression
            )
        }
        func parseKgNumber(_ text: String) -> Double? {
            let normalized = normalize(text)
            guard let re = try? NSRegularExpression(
                pattern: #"(\d+(?:\.\d+)?)\s*kg"#,
                options: [.caseInsensitive]
            ) else { return nil }
            let range = NSRange(normalized.startIndex..., in: normalized)
            guard let m = re.firstMatch(in: normalized, options: [], range: range),
                  m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: normalized),
                  let v = Double(normalized[r]),
                  expected.contains(v) else { return nil }
            return v
        }

        // 1) 单 box 匹配:`基础体重：68.1 kg`
        let single = try? NSRegularExpression(
            pattern: #"基础体重[：:]\s*(\d+(?:\.\d+)?)\s*kg"#,
            options: [.caseInsensitive]
        )
        if let re = single {
            for b in boxes {
                let text = normalize(b.text)
                let r = NSRange(text.startIndex..., in: text)
                if let m = re.firstMatch(in: text, options: [], range: r),
                   m.numberOfRanges >= 2,
                   let valRange = Range(m.range(at: 1), in: text),
                   let v = Double(text[valRange]),
                   expected.contains(v) {
                    return (v, b.text)
                }
            }
        }

        // 2) 跨 box:label "基础体重" 与数字 box 拆开。
        let labelBoxes = boxes.filter { $0.text.contains("基础体重") }
        for label in labelBoxes {
            let rowTol = max(label.box.height, 0.012) * 1.8
            // 同行右侧候选(允许 label.right 之后 / 同行 cy 内)
            let sameRowRight = boxes
                .filter { $0.left > label.right - 0.005 }
                .filter { abs($0.cy - label.cy) <= rowTol }
                .sorted { $0.cx < $1.cx }
            for cand in sameRowRight {
                if let v = parseKgNumber(cand.text) {
                    return (v, cand.text)
                }
            }
        }
        return nil
    }

    /// 在 boxes 中寻找匹配 keys 之一的标签,并返回其最可能对应的数值。
    ///
    /// InBody 报告的典型行布局:
    ///   `[标签] [参考范围 X.X~Y.Y] [柱状图轴刻度 40 55 70 85 ...] [实测值 X.X kg]`
    /// 或嵌套形式: `身体水分总量 41.5kg(30.3~37.0)`
    ///
    /// **关键陷阱**(2026-05-24 修复):柱状图的轴刻度(整数 40/55/70/85...)
    /// 全部落在宽松的 `expected` 区间里。旧实现取"第一个落在区间内的候选",
    /// 因此实测值永远拿不到 —— 第一个轴刻度就把它挤掉了。
    ///
    /// 新策略(Plan A + Plan B):
    ///   - **Plan B**:先在同行扫一遍打印出的"正常范围"box(如 `53.4~72.3`),
    ///     把字段的 `expected` 临时收紧到 `low×0.5 ... high×1.5`,
    ///     直接砍掉远端轴刻度(如 weight 行的 115/130/145)。
    ///   - **Plan A**:对剩下的同行右侧候选,按"含单位 / 是小数 / box 字号大 /
    ///     最右侧"加分,对"等距整数群(轴刻度特征)"扣分,取最高分。
    ///   - 若 Plan A/B 全部失效 → 退回旧的 distance-to-range + below-column 兜底,
    ///     保证 BMI / WHR / BMR 等无柱状图字段不受影响。
    private func findValue(
        for keys: [String],
        in boxes: [TextBox],
        expected: ClosedRange<Double>,
        competitorKeys: [String] = []
    ) -> (value: Double, rawText: String)? {
        // 优先匹配更长、更独特的关键字
        let sortedKeys = keys.sorted { $0.count > $1.count }

        // 收集所有候选标签,长 key 在前
        var labels: [TextBox] = []
        for key in sortedKeys {
            labels.append(contentsOf: boxes.filter { containsKey($0.text, key: key) })
        }
        // 去重(同一 box 可能被多个 key 命中)
        var seen = Set<String>()
        labels = labels.filter { box in
            let id = "\(box.box.minX),\(box.box.minY),\(box.text)"
            return seen.insert(id).inserted
        }

        // Fix 4 (2026-05-24):排除被 competitor key 以更长子串吃掉的标签。
        // 例如 weight 用 key '体重',但 '去脂体重'(leanBodyMass key)也含 '体重',
        // 不过滤会让 '去脂体重' 被当作 weight 的标签,值跑到 leanBodyMass 行。
        // 规则:若某个 competitorKey 在 label 文本中匹配长度 > 本字段任一 key 的
        // 匹配长度,则该 box 属于竞争字段,跳过。
        labels = labels.filter { box in
            let myBest = sortedKeys.first(where: { containsKey(box.text, key: $0) })?.count ?? 0
            let competitorBest = competitorKeys
                .filter { containsKey(box.text, key: $0) }
                .map { $0.count }
                .max() ?? 0
            return competitorBest <= myBest
        }

        // Fix 3 (2026-05-24):跳过含数学符号(=,×,÷)的"公式标签"。
        // 例如 InBody 230 报告里 '=一体脂肪×100' 这种公式行也含 '体脂肪',
        // 不过滤会被当作合法标签,导致从公式行里抽到错误数字。
        labels = labels.filter { box in
            !box.text.contains("=") && !box.text.contains("×") && !box.text.contains("÷")
        }

        // 针对每个标签,先尝试同行右侧,期望区间优先
        for label in labels {
            // 1. 标签文本内自带的主值 (e.g., "身体水分总量 41.5kg(30.3~37.0)")
            if let n = primaryNumber(in: label.text, excludingKeys: keys), expected.contains(n) {
                return (n, label.text)
            }

            let rowTol = max(label.box.height, 0.012) * 1.8

            // ── 同行列界:若存在其他已知字段标签也落在本行右侧,把候选 cx 锁在它左边 ──
            // 例:InBody 230 把 `身体水分含量` 和 `去脂体重` 放在同一行,前者的值是
            // 41.2,后者的值是 56.1。如果不卡列,前者会取到后者的 56。
            let competitorRight: CGFloat = {
                guard !competitorKeys.isEmpty else { return 1.0 }
                let nextLabelLeft = boxes
                    .filter { $0.left > label.right + 0.005 }
                    .filter { abs($0.cy - label.cy) < rowTol }
                    .filter { b in competitorKeys.contains(where: { containsKey(b.text, key: $0) }) }
                    .map { $0.left }
                    .min()
                return nextLabelLeft ?? 1.0
            }()

            // ── Plan B:同行印刷范围 sanity check ────────────────────────────
            // 扫描同行被 `isPureRange` 过滤的 box,解析成 (low, high)。
            // 把字段 `expected` 临时收紧到 [low × 0.5, high × 1.5],
            // 这一步把柱状图远端轴刻度(115/130/145)直接砍掉。
            // ⚠️ 多个 isPureRange box 可能同时落入 rowTol(相邻字段的参考范围互相渗透),
            // 因此按 cy 距离 label 升序排序,取离 label 最近的那一条。
            let rowRange = boxes
                .filter { abs($0.cy - label.cy) < rowTol }
                .filter { isPureRange($0.text) }
                .sorted { abs($0.cy - label.cy) < abs($1.cy - label.cy) }
                .compactMap { parsePrintedRange($0.text) }
                .first
            let narrowed: ClosedRange<Double> = {
                guard let r = rowRange else { return expected }
                let lo = max(expected.lowerBound, r.lowerBound * 0.5)
                let hi = min(expected.upperBound, r.upperBound * 1.5)
                return lo < hi ? lo...hi : expected
            }()

            // 同行右侧、非"纯范围"的所有数字候选(保留 TextBox 用于评分:高度、位置)
            let rowCandidates: [(value: Double, box: TextBox)] = boxes
                .filter { $0.left > label.right - 0.005 }
                .filter { $0.left < competitorRight }
                .filter { abs($0.cy - label.cy) < rowTol }
                .filter { !isPureRange($0.text) }
                .compactMap { b in
                    guard let n = primaryNumber(in: b.text, excludingKeys: keys) else { return nil }
                    return (n, b)
                }

            // ── Plan A:候选评分 ─────────────────────────────────────────────
            // 在 narrowed 区间内的候选先做评分;若全军覆没再回到 expected。
            let inNarrowed = rowCandidates.filter { narrowed.contains($0.value) }
            let inExpected = rowCandidates.filter { expected.contains($0.value) }

            // ── Pattern D (2026-05-24): "硬收紧" ─────────────────────────────
            // 当行内印刷范围存在但所有同行数字候选都落在 narrowed 之外,
            // 说明 Vision 看到的值跟该字段的"参考范围"不兼容 —— 多半是
            // 邻行(例如骨骼肌的 31.7 渗到体脂肪行,或柱状图轴刻度 160 渗到
            // 体重行)在作怪。继续到下一个 label,而不是退回 inExpected:
            // 后者会把"最右侧的合法数"也算正确答案,正是 Pattern A/B/C
            // 在反复修补的问题。
            // 仅在 rowRange != nil 时启用硬收紧 —— 无柱状图的字段
            // (BMI / WHR / BMR 等)保持宽松回退,避免误伤。
            if rowRange != nil && inNarrowed.isEmpty {
                continue
            }

            let pool = !inNarrowed.isEmpty ? inNarrowed : inExpected

            if !pool.isEmpty {
                if let best = pickHighestScoring(
                    pool,
                    allRowCandidates: rowCandidates,
                    labelCy: label.cy,
                    rowTol: rowTol
                ) {
                    return (best.value, best.box.text)
                }
            }

            // ── 兜底 1:仍有行内候选 → 取距离 expected 最近的(老逻辑) ─────────
            if !rowCandidates.isEmpty {
                if let best = rowCandidates.min(by: {
                    distanceToRange($0.value, expected) < distanceToRange($1.value, expected)
                }), distanceToRange(best.value, expected) <= expected.upperBound * 0.5 {
                    return (best.value, best.box.text)
                }
            }

            // ── 兜底 2:允许"纯范围" box 中的主数字(BMI / WHR 等无范围字段) ──
            let rowNumbersIncludingRange: [(Double, CGFloat, String)] = boxes
                .filter { $0.left > label.right - 0.005 }
                .filter { $0.left < competitorRight }
                .filter { abs($0.cy - label.cy) < rowTol }
                .compactMap { b in
                    guard let n = primaryNumber(in: b.text, excludingKeys: keys) else { return nil }
                    return (n, b.cx, b.text)
                }
            if let hit = rowNumbersIncludingRange.first(where: { expected.contains($0.0) }) {
                return (hit.0, hit.2)
            }

            // ── 兜底 3:正下方列(表头/数据两行布局,少见但保留) ───────────────
            let colTol: CGFloat = 0.05
            let below: [(Double, CGFloat, String)] = boxes
                .filter { $0.cy < label.cy - label.box.height * 0.3 }
                .filter { abs($0.cx - label.cx) < colTol }
                .filter { !isPureRange($0.text) }
                .compactMap { b in
                    guard let n = primaryNumber(in: b.text, excludingKeys: keys) else { return nil }
                    return (n, label.cy - b.cy, b.text)
                }
                .sorted { $0.1 < $1.1 }
            if let hit = below.first(where: { expected.contains($0.0) }), hit.1 < 0.10 {
                return (hit.0, hit.2)
            }
        }

        return nil
    }

    /// 候选评分器(Plan A 核心)。
    ///
    /// 权重设计:
    ///   - **+4**:文本含 `kg` / `%` / `kcal` 等单位 —— 实测值几乎一定带单位,
    ///     轴刻度几乎一定不带。
    ///   - **+2**:值是小数(原始文本含 `.`) —— 实测值通常小数,刻度通常整数。
    ///   - **+2**:box 高度位于行内候选的上四分位 —— 实测值字号通常 2-3× 于刻度。
    ///   - **+1**:本候选是行内最靠右的 —— 实测值通常在 bar 末端。
    ///   - **-5**:命中"等距整数群"(3+ 个整数候选间距大致相等) —— 轴刻度特征。
    ///
    /// 等距判定:取候选中所有整数,按 cx 排序,若 3+ 个且相邻 cx 间距的
    /// (max-min)/mean < 0.4,则判为等差数列;序列里的每个值都扣分。
    private func pickHighestScoring(
        _ pool: [(value: Double, box: TextBox)],
        allRowCandidates: [(value: Double, box: TextBox)],
        labelCy: CGFloat,
        rowTol: CGFloat
    ) -> (value: Double, box: TextBox)? {
        guard !pool.isEmpty else { return nil }

        // 上四分位高度阈值(用整行候选,不仅 pool 内,因为轴刻度也算行内)
        let heights = allRowCandidates.map { $0.box.box.height }.sorted()
        let q3Height: CGFloat = heights.isEmpty
            ? 0
            : heights[min(heights.count - 1, (heights.count * 3) / 4)]

        // 等距整数群检测:整行候选里的整数 cx 是否近似等差
        let intCandidates = allRowCandidates
            .filter { $0.value.truncatingRemainder(dividingBy: 1) == 0 }
            .sorted { $0.box.cx < $1.box.cx }
        let axisValueSet: Set<Double> = {
            guard intCandidates.count >= 3 else { return [] }
            let xs = intCandidates.map { $0.box.cx }
            var gaps: [CGFloat] = []
            for i in 1..<xs.count { gaps.append(xs[i] - xs[i - 1]) }
            let meanGap = gaps.reduce(0, +) / CGFloat(gaps.count)
            guard meanGap > 0.001 else { return [] }
            let spread = (gaps.max()! - gaps.min()!) / meanGap
            // 间距相对均匀(spread < 0.4) → 视为坐标轴
            return spread < 0.4 ? Set(intCandidates.map { $0.value }) : []
        }()

        // 最右候选(用 pool 而不是 allRow,保证落在合理区间内)
        let rightmostCx = pool.map { $0.box.cx }.max() ?? 0

        struct Scored {
            let value: Double
            let box: TextBox
            let score: Int
        }

        let scored: [Scored] = pool.map { cand in
            var s = 0
            let txt = cand.box.text
            // +4 单位
            if txt.range(of: #"(kg|KG|Kg|%|kcal|Kcal|KCAL)"#, options: .regularExpression) != nil {
                s += 4
            }
            // +2 小数
            if txt.contains(".") && cand.value.truncatingRemainder(dividingBy: 1) != 0 {
                s += 2
            }
            // +2 字号位于上四分位
            if cand.box.box.height >= q3Height && q3Height > 0 {
                s += 2
            }
            // +1 最右
            if abs(cand.box.cx - rightmostCx) < 0.005 {
                s += 1
            }
            // +2 Pattern E (2026-05-24):候选 cy 落在 rowTol 内圈 40%
            // —— 视为"真正同行",优先于跨行渗透值。rowTol = 1.8 × label.height
            // 比较宽松,会把上下相邻行的值也吸进来(例如 InBody 230 骨骼肌行
            // cy=0.725 把体脂肪行 cy=0.709 的 25.7 也算同行,导致 +1 rightmost
            // 让错误答案胜出)。内圈 40% (≤ rowTol × 0.4) 才算"贴脸",
            // 给一个 +2 的强势加分把渗透值压回去。
            let cyDist = abs(cand.box.cy - labelCy)
            if cyDist <= rowTol * 0.4 {
                s += 2
            }
            // -5 等距整数群成员
            if axisValueSet.contains(cand.value) {
                s -= 5
            }
            return Scored(value: cand.value, box: cand.box, score: s)
        }

        // 取最高分;若并列,取最右
        let best = scored.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.box.cx < rhs.box.cx
        }
        // 若所有候选都被打成负分,放弃由兜底逻辑接手
        guard let winner = best, winner.score >= 0 else { return nil }
        return (winner.value, winner.box)
    }

    /// 把一段被判定为 `isPureRange` 的文本解析回 (low, high)。
    /// 例:`"53.4~72.3"` / `"8.5-15.1kg"` / `"26.8～32.7"` → (53.4, 72.3) 等。
    private func parsePrintedRange(_ text: String) -> ClosedRange<Double>? {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "∼", with: "~")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        let pattern = #"(-?\d+(?:\.\d+)?)[~\-](-?\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: cleaned, range: NSRange(location: 0, length: (cleaned as NSString).length)),
              m.numberOfRanges >= 3 else { return nil }
        let ns = cleaned as NSString
        guard let lo = Double(ns.substring(with: m.range(at: 1))),
              let hi = Double(ns.substring(with: m.range(at: 2))),
              lo <= hi, lo > 0 else { return nil }
        return lo...hi
    }

    /// 数字到期望区间的距离(区间内为 0)。
    private func distanceToRange(_ n: Double, _ range: ClosedRange<Double>) -> Double {
        if range.contains(n) { return 0 }
        if n < range.lowerBound { return range.lowerBound - n }
        return n - range.upperBound
    }

    /// 忽略大小写、忽略常见干扰符号地检查 text 是否包含 key。
    private func containsKey(_ text: String, key: String) -> Bool {
        let norm = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ":", with: "")
        let nkey = key.replacingOccurrences(of: " ", with: "")
        return norm.range(of: nkey, options: .caseInsensitive) != nil
    }

    /// 检测一段文本是否就是一个数值范围(例如 "53.4~72.3"、"8.5-15.1")。
    /// 这种 box 属于参考范围,不应作为字段值。
    private func isPureRange(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "~", with: "~")
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        // 形如 X(.X)? [~-] Y(.Y)? ,可带 kg 等单位
        let pattern = #"^-?\d+(\.\d+)?[~\-]\d+(\.\d+)?(kg|%|cm|岁|级)?$"#
        return cleaned.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 从一段文本里提取主要数值。
    /// - 若文本是纯范围 → 返回 nil
    /// - 若是 "41.5kg(30.3~37.0)" → 返回 41.5(括号前的主值)
    /// - 若是 "68.0" / "29.1 kg" / "BMI 22.3" → 返回 68.0 / 29.1 / 22.3
    /// - 排除的 keys 会先被剥离,避免关键字尾数被误读。
    private func primaryNumber(in text: String, excludingKeys keys: [String]) -> Double? {
        if isPureRange(text) { return nil }

        var working = text
        // Vision sometimes splits decimals with a literal space, e.g. "68. 1kg" or "56. 1 kg".
        // Stitch any `<digit>. <digit>` (one or more spaces) back into `<digit>.<digit>` BEFORE
        // anything else touches the string, so the number regex below captures the full value.
        working = working.replacingOccurrences(
            of: #"(\d)\.\s+(\d)"#,
            with: "$1.$2",
            options: .regularExpression
        )
        for key in keys {
            working = working.replacingOccurrences(of: key, with: " ", options: .caseInsensitive)
        }
        // 把括号内容(范围/公式)整体抹掉,避免括号内数字抢先
        working = working.replacingOccurrences(
            of: #"[((][^))]*[))]"#,
            with: " ",
            options: .regularExpression
        )
        // 抹掉单位词,降低干扰
        for unit in ["kg", "Kg", "KG", "cm", "CM", "%", "分", "岁", "级", ","] {
            working = working.replacingOccurrences(of: unit, with: " ")
        }

        // 在清理后的串里取第一个数字。但若第一个数字后紧跟 ~ 或 - 连着另一数字,说明仍是范围,跳过。
        let nsText = working as NSString
        let regex = try? NSRegularExpression(pattern: #"-?\d+(\.\d+)?"#)
        let matches = regex?.matches(in: working, range: NSRange(location: 0, length: nsText.length)) ?? []
        for (idx, m) in matches.enumerated() {
            let numStr = nsText.substring(with: m.range)
            // 检查紧邻的下一个字符是不是 ~ 或 - 后接数字(未被抹掉的范围形式)
            let afterEnd = m.range.location + m.range.length
            if afterEnd < nsText.length {
                let nextChar = nsText.substring(with: NSRange(location: afterEnd, length: 1))
                if (nextChar == "~" || nextChar == "-") && idx + 1 < matches.count {
                    // 是范围的左端,跳过
                    continue
                }
            }
            if let n = Double(numStr) {
                return n
            }
        }
        return nil
    }

    /// 保留以兼容旧接口(未使用)。
    private func pureNumber(_ text: String) -> Double? {
        primaryNumber(in: text, excludingKeys: [])
    }

    /// 过滤明显不合理的值。
    private func isPlausible(_ n: Double) -> Bool {
        n >= 0 && n < 10000
    }



    // MARK: - Extraction Helpers

    private func extractDate(from text: String) -> Date? {
        let patterns = [
            "\\d{4}[\\./\\-]\\d{1,2}[\\./\\-]\\d{1,2}",
            "\\d{4}年\\d{1,2}月\\d{1,2}日"
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let dateStr = String(text[range])
                    .replacingOccurrences(of: "年", with: "-")
                    .replacingOccurrences(of: "月", with: "-")
                    .replacingOccurrences(of: "日", with: "")
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ".", with: "-")
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-M-d"
                if let date = formatter.date(from: dateStr) { return date }
            }
        }
        return nil
    }

    private func extractTime(from text: String) -> String? {
        let pattern = "\\d{1,2}:\\d{2}(:\\d{2})?"
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }

    private func extractValue(from lines: [String], keys: [String], after allText: String) -> Double? {
        for key in keys {
            // Look for "key ... number" pattern
            for line in lines {
                if line.localizedCaseInsensitiveContains(key) {
                    if let num = extractFirstNumber(after: key, in: line) {
                        return num
                    }
                    // Try extracting any number from the line
                    if let num = extractAnyNumber(from: line, excluding: key) {
                        return num
                    }
                }
            }
            // Check adjacent lines
            for (i, line) in lines.enumerated() {
                if line.localizedCaseInsensitiveContains(key) && i + 1 < lines.count {
                    if let num = extractAnyNumber(from: lines[i + 1], excluding: "") {
                        return num
                    }
                }
            }
        }
        return nil
    }

    private func extractFirstNumber(after key: String, in text: String) -> Double? {
        guard let keyRange = text.range(of: key, options: .caseInsensitive) else { return nil }
        let afterKey = String(text[keyRange.upperBound...])
        let pattern = "-?\\d+\\.?\\d*"
        if let range = afterKey.range(of: pattern, options: .regularExpression) {
            return Double(afterKey[range])
        }
        return nil
    }

    private func extractAnyNumber(from text: String, excluding key: String) -> Double? {
        let cleaned = key.isEmpty ? text : text.replacingOccurrences(of: key, with: "", options: .caseInsensitive)
        let pattern = "-?\\d+\\.?\\d*"
        guard let range = cleaned.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(cleaned[range])
    }

    struct SegmentalValues {
        var leftArm: Double?
        var rightArm: Double?
        var trunk: Double?
        var leftLeg: Double?
        var rightLeg: Double?
    }

    private func extractSegmental(from lines: [String], section: String, allText: String) -> SegmentalValues {
        var values = SegmentalValues()
        let keys = [
            ("右臂", "Right Arm"),
            ("左臂", "Left Arm"),
            ("躯干", "Trunk"),
            ("右腿", "Right Leg"),
            ("左腿", "Left Leg")
        ]

        for line in lines {
            if !line.contains(section) && !line.localizedCaseInsensitiveContains("segment") {
                continue
            }
            for (zhKey, enKey) in keys {
                if line.contains(zhKey) || line.localizedCaseInsensitiveContains(enKey) {
                    if let num = extractFirstNumber(after: zhKey, in: line)
                        ?? extractFirstNumber(after: enKey, in: line) {
                        switch zhKey {
                        case "左臂": values.leftArm = num
                        case "右臂": values.rightArm = num
                        case "躯干": values.trunk = num
                        case "左腿": values.leftLeg = num
                        case "右腿": values.rightLeg = num
                        default: break
                        }
                    }
                }
            }
        }
        return values
    }

    // MARK: - InBody Report Detection

    func isInBodyReport(_ image: UIImage) -> Bool {
        do {
            let lines = try recognizeText(from: image)
            let text = lines.joined(separator: " ").lowercased()
            let keywords = ["inbody", "人体成份分析", "人体成分分析", "bmi", "骨骼肌",
                          "体脂肪", "身体成分", "body composition"]
            let matchCount = keywords.filter { text.contains($0.lowercased()) }.count
            return matchCount >= 2
        } catch {
            return false
        }
    }
}
