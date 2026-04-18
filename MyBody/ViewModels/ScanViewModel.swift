import Foundation
import SwiftData
import SwiftUI
import Photos

@MainActor
@Observable
final class ScanViewModel {
    var isScanning = false
    var scanProgress: Double = 0
    var scannedPhotos: [ScannedPhoto] = []
    var showConfirmation = false

    var currentParseIndex = 0
    var parsedReport: OCRService.ParsedReport?
    var currentImage: UIImage?
    var currentAsset: PHAsset?
    var isParsing = false
    var showParseResult = false

    private let photoService = PhotoScanService()
    private let ocrService = OCRService()
    private var modelContext: ModelContext?

    func setup(context: ModelContext) {
        self.modelContext = context
    }

    func startScan() async {
        isScanning = true
        scanProgress = 0
        scannedPhotos = []

        await photoService.scanPhotoLibrary()

        scannedPhotos = photoService.scannedPhotos
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

        if let image = await photoService.loadFullImage(for: photo.asset) {
            currentImage = image
            do {
                parsedReport = try await ocrService.parseReport(from: image)
                // Set date from asset if OCR failed
                if parsedReport?.scanDate == nil {
                    parsedReport?.scanDate = photo.asset.creationDate
                }
            } catch {
                parsedReport = OCRService.ParsedReport()
                parsedReport?.scanDate = photo.asset.creationDate
                parsedReport?.failedFields = Set(["all"])
            }
        }

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
        currentAsset = nil
        isParsing = false
        showParseResult = false
        showConfirmation = false
        scannedPhotos = []
    }
}
