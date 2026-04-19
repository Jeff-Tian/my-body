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

        func toRecord(photoData: Data?, assetIdentifier: String?) -> InBodyRecord {
            InBodyRecord(
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
                photoAssetIdentifier: assetIdentifier
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
        for spec in specs {
            if let v = findValue(for: spec.keys, in: boxes, expected: spec.expected) {
                values[spec.name] = v
            } else {
                report.failedFields.insert(spec.name)
            }
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

        return report
    }

    /// 在 boxes 中寻找匹配 keys 之一的标签,并返回其最可能对应的数值。
    ///
    /// InBody 报告的典型行布局:
    ///   `[标签] [参考范围 X.X~Y.Y] [柱状图] [实测值 X.X kg]`
    /// 或嵌套形式: `身体水分总量 41.5kg(30.3~37.0)`
    ///
    /// 策略(按优先级):
    ///   1. 标签自带的主数值(排除括号内范围)
    ///   2. 同行右侧所有数字候选 → 跳过"纯范围"文本 → 在期望区间内、最靠右的一个
    ///   3. 若期望区间没命中,退而求其次取同行右侧任意合理数字
    ///   4. 正下方列的数字(表头/数据两行布局)
    private func findValue(
        for keys: [String],
        in boxes: [TextBox],
        expected: ClosedRange<Double>
    ) -> Double? {
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

        // 针对每个标签,先尝试同行右侧,期望区间优先
        for label in labels {
            // 1. 标签文本内自带的主值 (e.g., "身体水分总量 41.5kg(30.3~37.0)")
            if let n = primaryNumber(in: label.text, excludingKeys: keys), expected.contains(n) {
                return n
            }

            // 2. 同行右侧,在期望区间内的候选
            let rowTol = max(label.box.height, 0.012) * 1.8
            let rowNumbers: [(Double, CGFloat)] = boxes
                .filter { $0.left > label.right - 0.005 }
                .filter { abs($0.cy - label.cy) < rowTol }
                .compactMap { b in
                    guard let n = primaryNumber(in: b.text, excludingKeys: keys) else { return nil }
                    return (n, b.cx)
                }
            // 期望区间内的候选,挑最靠左(通常第一个命中就是正确的)
            // 注意 InBody 230 的范围下界(例如 53.4)可能也落在 weight 区间里,
            // 所以要过滤掉来自"纯范围"的 box
            let rowFiltered: [(Double, CGFloat)] = boxes
                .filter { $0.left > label.right - 0.005 }
                .filter { abs($0.cy - label.cy) < rowTol }
                .filter { !isPureRange($0.text) }
                .compactMap { b in
                    guard let n = primaryNumber(in: b.text, excludingKeys: keys) else { return nil }
                    return (n, b.cx)
                }

            if let hit = rowFiltered.first(where: { expected.contains($0.0) }) {
                return hit.0
            }

            // 3. 仍没有命中区间,但有行内候选 → 取期望区间内最接近的,或第一个
            if !rowFiltered.isEmpty {
                if let best = rowFiltered.min(by: { distanceToRange($0.0, expected) < distanceToRange($1.0, expected) }),
                   distanceToRange(best.0, expected) <= expected.upperBound * 0.5 {
                    return best.0
                }
            }

            // 4. 再宽松一点:允许范围 box(有些小字段如 BMI 没有范围,避免误判)
            if let n = rowNumbers.first(where: { expected.contains($0.0) })?.0 {
                return n
            }

            // 5. 正下方列(表头/数据两行布局,少见但保留)
            let colTol: CGFloat = 0.05
            let below: [(Double, CGFloat)] = boxes
                .filter { $0.cy < label.cy - label.box.height * 0.3 }
                .filter { abs($0.cx - label.cx) < colTol }
                .filter { !isPureRange($0.text) }
                .compactMap { b in
                    guard let n = primaryNumber(in: b.text, excludingKeys: keys) else { return nil }
                    return (n, label.cy - b.cy)
                }
                .sorted { $0.1 < $1.1 }
            if let hit = below.first(where: { expected.contains($0.0) }), hit.1 < 0.10 {
                return hit.0
            }
        }

        return nil
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
