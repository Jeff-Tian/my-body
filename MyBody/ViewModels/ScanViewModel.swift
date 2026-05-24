import Foundation
import SwiftData
import SwiftUI
import Photos

@MainActor
@Observable
final class ScanViewModel {
    var isScanning = false
    var scanProgress: Double = 0
    var totalCount: Int = 0
    var processedCount: Int = 0
    var stageMessage: String = ""
    var scannedPhotos: [ScannedPhoto] = []
    var showConfirmation = false

    var currentParseIndex = 0
    var currentThumbnail: UIImage?
    var currentAsset: PHAsset?
    var isParsing = false
    var parseStageMessage: String = ""

    /// 批量识别并保存完成后置为 true，View 据此关闭 sheet。
    var batchFinished = false
    /// 批量导入完成时的统计
    var savedCount = 0
    var skippedCount = 0
    /// 因已存在同一照片的记录而跳过的数量（幂等去重）
    var duplicateCount = 0

    private let photoService = PhotoScanService()
    private let ocrService = OCRService()
    private var modelContext: ModelContext?
    private var progressObserver: Task<Void, Never>?

    func setup(context: ModelContext) {
        self.modelContext = context
    }

    func startScan() async {
        isScanning = true
        scanProgress = 0
        totalCount = 0
        processedCount = 0
        stageMessage = ""
        scannedPhotos = []

        // Mirror photoService counts into this view model
        progressObserver?.cancel()
        progressObserver = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.totalCount = self.photoService.totalCount
                self.processedCount = self.photoService.processedCount
                self.scanProgress = self.photoService.scanProgress
                self.stageMessage = self.photoService.stageMessage
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
            }
        }

        await photoService.scanPhotoLibrary()

        progressObserver?.cancel()
        scannedPhotos = photoService.scannedPhotos
        totalCount = photoService.totalCount
        processedCount = photoService.processedCount
        stageMessage = photoService.stageMessage
        scanProgress = 1.0
        isScanning = false

        if !scannedPhotos.isEmpty {
            showConfirmation = true
        }
    }

    func toggleSelection(for photo: ScannedPhoto) {
        if let idx = scannedPhotos.firstIndex(where: { $0.id == photo.id }) {
            scannedPhotos[idx].isSelected.toggle()
        }
    }

    var selectedPhotos: [ScannedPhoto] {
        scannedPhotos.filter { $0.isSelected }
    }

    func parseNextPhoto() async {
        let selected = selectedPhotos
        guard currentParseIndex < selected.count else {
            batchFinished = true
            isParsing = false
            return
        }

        isParsing = true
        let photo = selected[currentParseIndex]
        currentAsset = photo.asset
        currentThumbnail = photo.thumbnail
        parseStageMessage = "正在加载图片…"

        // 幂等：若已导入过同一张相册照片，直接跳过，避免重复记录。
        let assetId = photo.asset.localIdentifier
        if let context = modelContext, recordExists(forAssetId: assetId, in: context) {
            duplicateCount += 1
            currentParseIndex += 1
            parseStageMessage = ""
            if currentParseIndex < selected.count {
                await parseNextPhoto()
            } else {
                batchFinished = true
                isParsing = false
            }
            return
        }

        let image = await photoService.loadFullImage(for: photo.asset)

        var finalReport: OCRService.ParsedReport
        if let image {
            parseStageMessage = "正在识别文字…"
            let ocr = ocrService
            // 先把所有已登记的纠正读进内存快照，避免在后台线程触碰 SwiftData。
            let snapshot: [String: [String: Double]] = {
                guard let context = modelContext else { return [:] }
                let all = (try? context.fetch(FetchDescriptor<OCRCorrection>())) ?? []
                var dict: [String: [String: Double]] = [:]
                for row in all {
                    dict[row.fieldName, default: [:]][row.rawText] = row.correctedValue
                }
                return dict
            }()
            let lookup: (String, String) -> Double? = { field, raw in
                snapshot[field]?[OCRCorrection.normalize(raw)]
            }
            let result: OCRService.ParsedReport = await Task.detached(priority: .userInitiated) {
                do {
                    return try ocr.parseReport(from: image, corrections: lookup)
                } catch {
                    var failed = OCRService.ParsedReport()
                    failed.failedFields = Set(["all"])
                    return failed
                }
            }.value
            // 回到主 actor 后再把 useCount 累加上去
            if let context = modelContext {
                for (field, raw) in result.rawTexts {
                    let key = OCRCorrection.normalize(raw)
                    if snapshot[field]?[key] != nil {
                        var desc = FetchDescriptor<OCRCorrection>(
                            predicate: #Predicate { $0.fieldName == field && $0.rawText == key }
                        )
                        desc.fetchLimit = 1
                        if let row = (try? context.fetch(desc))?.first {
                            row.useCount += 1
                            row.updatedAt = Date()
                        }
                    }
                }
                try? context.save()
            }
            finalReport = result
        } else {
            // 图片加载失败（Mac "Designed for iPhone" 或 iCloud 原图未下载）：
            // 仍然创建一条空记录，用户稍后手动补录。
            var fallback = OCRService.ParsedReport()
            fallback.failedFields = Set(["all"])
            finalReport = fallback
            skippedCount += 1
        }

        if finalReport.scanDate == nil {
            finalReport.scanDate = photo.asset.creationDate
        }

        // 自动保存：把照片数据一起存下来，以便日后核对。
        if let context = modelContext {
            let photoData = image?.jpegData(compressionQuality: 0.7)
            let record = finalReport.toRecord(
                photoData: photoData,
                assetIdentifier: photo.asset.localIdentifier
            )
            context.insert(record)
            try? context.save()
            savedCount += 1

            // 可选：把体重写入系统「健康」App。失败时静默忽略，避免阻塞批量导入。
            // 带 SyncIdentifier(record.id)，重复扫描同一张相册照片不会产生重复 HK 样本。
            if UserDefaults.standard.bool(forKey: "syncWeightToHealth"),
               let weight = record.weight {
                let date = record.scanDate
                let recordID = record.id
                Task.detached {
                    try? await HealthKitService.shared.saveWeight(weight, date: date, recordID: recordID)
                }
            }
        }

        currentParseIndex += 1
        parseStageMessage = ""

        // 继续下一张，直到全部处理完。
        if currentParseIndex < selected.count {
            await parseNextPhoto()
        } else {
            batchFinished = true
            isParsing = false
        }
    }

    func reset() {
        currentParseIndex = 0
        currentThumbnail = nil
        currentAsset = nil
        isParsing = false
        showConfirmation = false
        scannedPhotos = []
        parseStageMessage = ""
        batchFinished = false
        savedCount = 0
        skippedCount = 0
        duplicateCount = 0
    }

    /// 单张照片导入：跳过相册扫描和确认网格,直接对一张图片走 OCR/保存流程。
    /// - 优先用 PHAsset 路径（与批量扫描一致,保留按 localIdentifier 去重）。
    /// - 若 itemIdentifier 为 nil（受限相册访问等场景）,退化为 Data 路径,
    ///   保存时 assetIdentifier 留空,不做去重检查。
    func startSingleImport(itemIdentifier: String?, fallbackImageData: Data?) async {
        reset()
        isParsing = true
        parseStageMessage = "正在加载图片…"

        // 快路径:能拿到 PHAsset 就走批量管道,自动享有去重/创建日期回填
        if let id = itemIdentifier {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            if let asset = fetch.firstObject {
                let thumb = await photoService.loadFullImage(for: asset)
                currentThumbnail = thumb
                currentAsset = asset
                var photo = ScannedPhoto(asset: asset, thumbnail: thumb)
                photo.isSelected = true
                scannedPhotos = [photo]
                currentParseIndex = 0
                await parseNextPhoto()
                return
            }
        }

        // 慢路径:只有原始 Data 时直接构造 UIImage 跑 OCR,不走 PHAsset 通路
        if let data = fallbackImageData, let image = UIImage(data: data) {
            await parseSingleDataImage(image)
            batchFinished = true
            isParsing = false
            return
        }

        // 既没有 asset 也没有 data —— 视为加载失败
        skippedCount += 1
        batchFinished = true
        isParsing = false
    }

    /// Data 路径专用的 OCR + 保存流程。与 parseNextPhoto 主体保持一致,
    /// 但跳过 PHAsset 相关步骤（去重/创建日期回填/asset 缩略图）。
    private func parseSingleDataImage(_ image: UIImage) async {
        currentThumbnail = image
        parseStageMessage = "正在识别文字…"

        let ocr = ocrService
        let snapshot: [String: [String: Double]] = {
            guard let context = modelContext else { return [:] }
            let all = (try? context.fetch(FetchDescriptor<OCRCorrection>())) ?? []
            var dict: [String: [String: Double]] = [:]
            for row in all {
                dict[row.fieldName, default: [:]][row.rawText] = row.correctedValue
            }
            return dict
        }()
        let lookup: (String, String) -> Double? = { field, raw in
            snapshot[field]?[OCRCorrection.normalize(raw)]
        }

        let result: OCRService.ParsedReport = await Task.detached(priority: .userInitiated) {
            do {
                return try ocr.parseReport(from: image, corrections: lookup)
            } catch {
                var failed = OCRService.ParsedReport()
                failed.failedFields = Set(["all"])
                return failed
            }
        }.value

        // 回到主 actor 累加 useCount
        if let context = modelContext {
            for (field, raw) in result.rawTexts {
                let key = OCRCorrection.normalize(raw)
                if snapshot[field]?[key] != nil {
                    var desc = FetchDescriptor<OCRCorrection>(
                        predicate: #Predicate { $0.fieldName == field && $0.rawText == key }
                    )
                    desc.fetchLimit = 1
                    if let row = (try? context.fetch(desc))?.first {
                        row.useCount += 1
                        row.updatedAt = Date()
                    }
                }
            }
            try? context.save()
        }

        var finalReport = result
        // 没有 PHAsset.creationDate 可用,留空让用户后续手动补
        if finalReport.scanDate == nil {
            finalReport.scanDate = nil
        }

        if let context = modelContext {
            let photoData = image.jpegData(compressionQuality: 0.7)
            let record = finalReport.toRecord(photoData: photoData, assetIdentifier: nil)
            context.insert(record)
            try? context.save()
            savedCount += 1

            // Data 路径：同样走带 SyncIdentifier 的写入。
            if UserDefaults.standard.bool(forKey: "syncWeightToHealth"),
               let weight = record.weight {
                let date = record.scanDate
                let recordID = record.id
                Task.detached {
                    try? await HealthKitService.shared.saveWeight(weight, date: date, recordID: recordID)
                }
            }
        }

        parseStageMessage = ""
    }

    /// 判断相册 assetId 是否已存在对应的 InBodyRecord，用于批量导入去重。
    private func recordExists(forAssetId assetId: String, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<InBodyRecord>(
            predicate: #Predicate { $0.photoAssetIdentifier == assetId }
        )
        descriptor.fetchLimit = 1
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    // MARK: - Re-parse existing report

    enum ReparseError: LocalizedError {
        case noOriginalPhoto
        case photoNotInAlbum
        case imageLoadFailed
        case ocrFailed

        var errorDescription: String? {
            switch self {
            case .noOriginalPhoto:
                return "该记录没有关联的原始照片，无法重新识别。"
            case .photoNotInAlbum:
                return "原始照片已不在相册中（可能已被删除），无法重新识别。"
            case .imageLoadFailed:
                return "无法加载原图（可能 iCloud 原图尚未下载），请稍后再试。"
            case .ocrFailed:
                return "OCR 识别失败，请稍后再试。"
            }
        }
    }

    /// 对已有记录的原始照片重新跑一次 OCR，并就地覆盖数值字段。
    ///
    /// - 复用 `parseNextPhoto()` 的 OCR + 纠正快照 + useCount 累加管道。
    /// - 不改动去重逻辑：本函数是用户显式触发的"重新识别"路径，
    ///   绕过 PHAsset 去重并直接写回同一条记录。
    /// - 不读写 `wasManuallyEdited` 之类的手工编辑标记（模型当前未提供该字段，
    ///   由调用方在 UI 上做确认即可，后续可作为增强）。
    /// - Returns: 新解析出的 `ParsedReport`，调用方可用来展示前后对比。
    /// - Throws: `ReparseError` —— 见各 case 说明。
    @MainActor
    static func reparseExistingReport(
        _ record: InBodyRecord,
        context: ModelContext,
        ocrService: OCRService = OCRService()
    ) async throws -> OCRService.ParsedReport {
        guard let assetId = record.photoAssetIdentifier, !assetId.isEmpty else {
            throw ReparseError.noOriginalPhoto
        }

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else {
            throw ReparseError.photoNotInAlbum
        }

        let photoService = PhotoScanService()
        guard let image = await photoService.loadFullImage(for: asset) else {
            throw ReparseError.imageLoadFailed
        }

        // 把已登记的 OCR 纠正读进内存快照，避免在后台线程触碰 SwiftData。
        let snapshot: [String: [String: Double]] = {
            let all = (try? context.fetch(FetchDescriptor<OCRCorrection>())) ?? []
            var dict: [String: [String: Double]] = [:]
            for row in all {
                dict[row.fieldName, default: [:]][row.rawText] = row.correctedValue
            }
            return dict
        }()
        let lookup: (String, String) -> Double? = { field, raw in
            snapshot[field]?[OCRCorrection.normalize(raw)]
        }

        let ocr = ocrService
        let result: OCRService.ParsedReport? = await Task.detached(priority: .userInitiated) {
            try? ocr.parseReport(from: image, corrections: lookup)
        }.value

        guard var parsed = result else {
            throw ReparseError.ocrFailed
        }

        // 累加命中的纠正项使用次数（与 parseNextPhoto 保持一致）。
        for (field, raw) in parsed.rawTexts {
            let key = OCRCorrection.normalize(raw)
            if snapshot[field]?[key] != nil {
                var desc = FetchDescriptor<OCRCorrection>(
                    predicate: #Predicate { $0.fieldName == field && $0.rawText == key }
                )
                desc.fetchLimit = 1
                if let row = (try? context.fetch(desc))?.first {
                    row.useCount += 1
                    row.updatedAt = Date()
                }
            }
        }

        // scanDate 若解析未拿到，回退到 PHAsset.creationDate；再不行保留原值。
        if parsed.scanDate == nil {
            parsed.scanDate = asset.creationDate ?? record.scanDate
        }

        // 就地覆盖记录的数值字段 + OCR 原始文本溯源。
        record.scanDate = parsed.scanDate ?? record.scanDate
        record.scanTime = parsed.scanTime ?? record.scanTime
        record.weight = parsed.weight
        record.skeletalMuscle = parsed.skeletalMuscle
        record.bodyFatMass = parsed.bodyFatMass
        record.totalBodyWater = parsed.totalBodyWater
        record.leanBodyMass = parsed.leanBodyMass
        record.bmi = parsed.bmi
        record.bodyFatPercent = parsed.bodyFatPercent
        record.whr = parsed.whr
        record.bmr = parsed.bmr
        record.inbodyScore = parsed.inbodyScore
        record.visceralFatLevel = parsed.visceralFatLevel
        record.dailyCalorie = parsed.dailyCalorie
        record.segMuscleLeftArm = parsed.segMuscleLeftArm
        record.segMuscleRightArm = parsed.segMuscleRightArm
        record.segMuscleTrunk = parsed.segMuscleTrunk
        record.segMuscleLeftLeg = parsed.segMuscleLeftLeg
        record.segMuscleRightLeg = parsed.segMuscleRightLeg
        record.segFatLeftArm = parsed.segFatLeftArm
        record.segFatRightArm = parsed.segFatRightArm
        record.segFatTrunk = parsed.segFatTrunk
        record.segFatLeftLeg = parsed.segFatLeftLeg
        record.segFatRightLeg = parsed.segFatRightLeg
        record.ocrRawTexts = parsed.rawTexts

        try context.save()
        return parsed
    }
}
