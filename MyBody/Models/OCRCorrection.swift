import Foundation
import SwiftData

/// 用户对 OCR 解析结果的纠正反馈。
///
/// 当用户在 `EditRecordView` 修改了某个字段的值，而这个字段在解析时
/// 来源于某段 OCR 原始文本（例如 "体脂肪量 32.1kg(30.3~37.0)"），
/// 就把 (字段名, 归一化原始文本) → 用户修正后的值 存下来。
///
/// 下次解析遇到完全相同的原始文本时，`OCRService` 会直接套用用户修正值，
/// 使 App 对同款报告（或 OCR 一致误读）"越用越准"。
@Model
final class OCRCorrection {
    /// 对应 `OCRService.ParsedReport` 的字段名，例如 "weight"、"bodyFatPercent"。
    var fieldName: String
    /// 归一化后的 OCR 原始 box 文本（已 `OCRCorrection.normalize` 处理）。
    var rawText: String
    /// 用户修正后的数值（Int 字段用 Double 存，读取时再转换）。
    var correctedValue: Double
    /// 这条纠正已被自动套用的次数，便于后续做 UI 展示或置信度策略。
    var useCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        fieldName: String,
        rawText: String,
        correctedValue: Double,
        useCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.fieldName = fieldName
        self.rawText = rawText
        self.correctedValue = correctedValue
        self.useCount = useCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 把 OCR 原始文本归一化为查询键：去空白、统一符号、小写化。
    /// 保留数字和主要分隔符，让 "32.1kg(30.3~37.0)" 和 " 32.1 kg (30.3~37.0) " 视为同一条。
    static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .lowercased()
    }
}
