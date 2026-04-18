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
    var parsedReport: OCRService.ParsedReport?
    var currentImage: UIImage?
    var currentThumbnail: UIImage?
    var currentAsset: PHAsset?
    var isParsing = false
    var showParseResult = false
    var parseStageMessage: String = ""

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
        guard currentParseIndex < selected.count else { return }

        isParsing = true
        let photo = selected[currentParseIndex]
        currentAsset = photo.asset
        currentThumbnail = photo.thumbnail
        currentImage = nil
        parsedReport = nil
        parseStageMessage = "正在加载图片…"

        guard let image = await photoService.loadFullImage(for: photo.asset) else {
            // 图片加载失败（常见于 Mac "Designed for iPhone" 或 iCloud 原图未下载）：
            // 生成一份空报告让用户手动录入，避免白屏卡死。
            var fallback = OCRService.ParsedReport()
            fallback.scanDate = photo.asset.creationDate
            fallback.failedFields = Set(["all"])
            parsedReport = fallback
            parseStageMessage = ""
            isParsing = false
            showParseResult = true
            return
        }

        currentImage = image
        parseStageMessage = "正在识别文字…"
        let ocr = ocrService
        // Run OCR on background thread
        let result: OCRService.ParsedReport = await Task.detached(priority: .userInitiated) {
            do {
                return try ocr.parseReport(from: image)
            } catch {
                var failed = OCRService.ParsedReport()
                failed.failedFields = Set(["all"])
                return failed
            }
        }.value
        parseStageMessage = "正在解析字段…"
        var finalReport = result
        if finalReport.scanDate == nil {
            finalReport.scanDate = photo.asset.creationDate
        }
        parsedReport = finalReport

        parseStageMessage = ""
        isParsing = false
        showParseResult = true
    }

    func saveCurrentRecord(report: OCRService.ParsedReport) {
        guard let context = modelContext else { return }

        let photoData = currentImage?.jpegData(compressionQuality: 0.7)
        let record = report.toRecord(
            photoData: photoData,
            assetIdentifier: currentAsset?.localIdentifier
        )

        context.insert(record)
        try? context.save()

        currentParseIndex += 1
        showParseResult = false
        parsedReport = nil
        currentImage = nil
    }

    func skipCurrentPhoto() {
        currentParseIndex += 1
        showParseResult = false
        parsedReport = nil
        currentImage = nil
    }

    func reset() {
        currentParseIndex = 0
        parsedReport = nil
        currentImage = nil
        currentThumbnail = nil
        currentAsset = nil
        isParsing = false
        showParseResult = false
        showConfirmation = false
        scannedPhotos = []
        parseStageMessage = ""
    }
}
