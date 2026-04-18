import Foundation
import Photos
import UIKit

struct ScannedPhoto: Identifiable, Sendable {
    let id = UUID()
    let asset: PHAsset
    let thumbnail: UIImage?
    var isSelected: Bool = true
}

@MainActor
final class PhotoScanService: ObservableObject {
    @Published var scannedPhotos: [ScannedPhoto] = []
    @Published var isScanning = false
    @Published var scanProgress: Double = 0

    private let ocrService = OCRService()

    func requestAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return true }

        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return newStatus == .authorized || newStatus == .limited
    }

    /// Load image synchronously. isSynchronous=true guarantees the callback
    /// fires exactly once before requestImage returns — no continuation needed.
    private nonisolated func requestImageSync(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit
    ) -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = true
        options.isNetworkAccessAllowed = UserDefaults.standard.bool(forKey: "iCloudPhotoDownload")

        var result: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, _ in
            result = image
        }
        return result
    }

    func scanPhotoLibrary() async {
        guard await requestAuthorization() else { return }

        isScanning = true
        scanProgress = 0
        scannedPhotos = []

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let assets = PHAsset.fetchAssets(with: fetchOptions)

        let total = assets.count
        guard total > 0 else {
            isScanning = false
            return
        }

        // Collect assets into an array (PHFetchResult is not Sendable)
        var assetList: [PHAsset] = []
        assetList.reserveCapacity(total)
        for i in 0..<total {
            assetList.append(assets[i])
        }

        let scanSize = CGSize(width: 800, height: 800)
        let thumbSize = CGSize(width: 200, height: 200)
        let ocr = ocrService

        // Run ALL heavy work (image loading + OCR) on a background thread
        let detected: [ScannedPhoto] = await Task.detached(priority: .userInitiated) {
            var results: [ScannedPhoto] = []

            for (i, asset) in assetList.enumerated() {
                if Task.isCancelled { break }

                guard let image = self.requestImageSync(for: asset, targetSize: scanSize) else {
                    await MainActor.run { self.scanProgress = Double(i + 1) / Double(total) }
                    continue
                }

                if ocr.isInBodyReport(image) {
                    let thumb = self.requestImageSync(
                        for: asset,
                        targetSize: thumbSize,
                        contentMode: .aspectFill
                    )
                    results.append(ScannedPhoto(asset: asset, thumbnail: thumb))
                }

                await MainActor.run { self.scanProgress = Double(i + 1) / Double(total) }
            }

            return results
        }.value

        scannedPhotos = detected
        isScanning = false
    }

    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            self.requestImageSync(for: asset, targetSize: PHImageManagerMaximumSize)
        }.value
    }
}
