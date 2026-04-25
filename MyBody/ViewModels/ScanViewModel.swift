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
            if UserDefaults.standard.bool(forKey: "syncWeightToHealth"),
               let weight = record.weight {
                let date = record.scanDate
                Task.detached {
                    try? await HealthKitService.shared.saveWeight(weight, date: date)
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

    /// 判断相册 assetId 是否已存在对应的 InBodyRecord，用于批量导入去重。
    private func recordExists(forAssetId assetId: String, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<InBodyRecord>(
            predicate: #Predicate { $0.photoAssetIdentifier == assetId }
        )
        descriptor.fetchLimit = 1
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }
}
