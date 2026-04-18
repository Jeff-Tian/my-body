import Foundation
import Vision
import UIKit

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

    /// Perform OCR synchronously — no completion handler, no continuation.
    /// VNRecognizeTextRequest.results is populated after perform() returns.
    func recognizeText(from image: UIImage) throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let results = request.results ?? []
        return results.compactMap { $0.topCandidates(1).first?.string }
    }

    func parseReport(from image: UIImage) throws -> ParsedReport {
        let lines = try recognizeText(from: image)
        return parseLines(lines)
    }

    func parseLines(_ lines: [String]) -> ParsedReport {
        var report = ParsedReport()
        let allText = lines.joined(separator: "\n")

        // Parse date
        report.scanDate = extractDate(from: allText)
        if report.scanDate == nil { report.failedFields.insert("scanDate") }

        // Parse time
        report.scanTime = extractTime(from: allText)

        // Body composition
        report.weight = extractValue(from: lines, keys: ["体重", "Weight"], after: allText)
        if report.weight == nil { report.failedFields.insert("weight") }

        report.skeletalMuscle = extractValue(from: lines, keys: ["骨骼肌", "骨骼肌量", "Skeletal Muscle", "SMM"], after: allText)
        if report.skeletalMuscle == nil { report.failedFields.insert("skeletalMuscle") }

        report.bodyFatMass = extractValue(from: lines, keys: ["体脂肪", "体脂肪量", "Body Fat Mass", "BFM"], after: allText)
        if report.bodyFatMass == nil { report.failedFields.insert("bodyFatMass") }

        report.totalBodyWater = extractValue(from: lines, keys: ["身体水分", "体水分", "Total Body Water", "TBW"], after: allText)
        if report.totalBodyWater == nil { report.failedFields.insert("totalBodyWater") }

        report.leanBodyMass = extractValue(from: lines, keys: ["去脂体重", "瘦体重", "Lean Body Mass", "LBM", "FFM"], after: allText)
        if report.leanBodyMass == nil { report.failedFields.insert("leanBodyMass") }

        // Obesity
        report.bmi = extractValue(from: lines, keys: ["BMI"], after: allText)
        if report.bmi == nil { report.failedFields.insert("bmi") }

        report.bodyFatPercent = extractValue(from: lines, keys: ["体脂百分比", "体脂率", "Body Fat", "PBF", "BFP"], after: allText)
        if report.bodyFatPercent == nil { report.failedFields.insert("bodyFatPercent") }

        report.whr = extractValue(from: lines, keys: ["腰臀比", "WHR", "Waist-Hip"], after: allText)
        if report.whr == nil { report.failedFields.insert("whr") }

        // Other
        report.bmr = extractValue(from: lines, keys: ["基础代谢", "BMR", "Basal Metabolic"], after: allText)
        if report.bmr == nil { report.failedFields.insert("bmr") }

        if let score = extractValue(from: lines, keys: ["InBody评分", "InBody 评分", "InBody Score", "身体评分", "总分"], after: allText) {
            report.inbodyScore = Int(score)
        }
        if report.inbodyScore == nil { report.failedFields.insert("inbodyScore") }

        if let vf = extractValue(from: lines, keys: ["内脏脂肪", "内脏脂肪等级", "Visceral Fat", "VFL"], after: allText) {
            report.visceralFatLevel = Int(vf)
        }
        if report.visceralFatLevel == nil { report.failedFields.insert("visceralFatLevel") }

        report.dailyCalorie = extractValue(from: lines, keys: ["每日所需热量", "日推荐摄入", "Daily Calorie"], after: allText)

        // Segmental muscle
        let segMuscle = extractSegmental(from: lines, section: "肌肉", allText: allText)
        report.segMuscleLeftArm = segMuscle.leftArm
        report.segMuscleRightArm = segMuscle.rightArm
        report.segMuscleTrunk = segMuscle.trunk
        report.segMuscleLeftLeg = segMuscle.leftLeg
        report.segMuscleRightLeg = segMuscle.rightLeg

        // Segmental fat
        let segFat = extractSegmental(from: lines, section: "脂肪", allText: allText)
        report.segFatLeftArm = segFat.leftArm
        report.segFatRightArm = segFat.rightArm
        report.segFatTrunk = segFat.trunk
        report.segFatLeftLeg = segFat.leftLeg
        report.segFatRightLeg = segFat.rightLeg

        return report
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
