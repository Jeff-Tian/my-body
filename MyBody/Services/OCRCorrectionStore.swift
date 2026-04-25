import Foundation
import SwiftData

/// 轻量包装，便于 `OCRService` 在不感知 SwiftData 的情况下查询 / 写入用户纠正。
///
/// 所有操作都在调用方线程上的 `ModelContext` 执行，调用方负责线程安全
/// （通常是 `@MainActor` 的 ViewModel 或视图层）。
@MainActor
struct OCRCorrectionStore {
    let context: ModelContext

    /// 查询某字段 + 某原始 OCR 文本是否存在用户纠正。
    /// 命中时同步把 `useCount += 1`，便于后续做置信度/UI 显示。
    func correctedValue(for fieldName: String, rawText: String) -> Double? {
        let key = OCRCorrection.normalize(rawText)
        var descriptor = FetchDescriptor<OCRCorrection>(
            predicate: #Predicate { $0.fieldName == fieldName && $0.rawText == key }
        )
        descriptor.fetchLimit = 1
        guard let hit = (try? context.fetch(descriptor))?.first else { return nil }
        hit.useCount += 1
        hit.updatedAt = Date()
        try? context.save()
        return hit.correctedValue
    }

    /// 新增或覆盖一条 (字段, 原始文本) → 修正值。
    func upsert(fieldName: String, rawText: String, correctedValue: Double) {
        let key = OCRCorrection.normalize(rawText)
        var descriptor = FetchDescriptor<OCRCorrection>(
            predicate: #Predicate { $0.fieldName == fieldName && $0.rawText == key }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.correctedValue = correctedValue
            existing.updatedAt = Date()
        } else {
            let row = OCRCorrection(
                fieldName: fieldName,
                rawText: key,
                correctedValue: correctedValue
            )
            context.insert(row)
        }
        try? context.save()
    }

    /// 传给 `OCRService.parseBoxes(_:corrections:)` 的闭包适配器。
    /// 注意：闭包会在调用方线程同步执行，因此必须在 `@MainActor` 上下文中使用。
    func lookup() -> (String, String) -> Double? {
        { fieldName, rawText in
            self.correctedValue(for: fieldName, rawText: rawText)
        }
    }
}
