import Foundation
import Photos
import UIKit

struct ScannedPhoto: Identifiable {
    let id = UUID()
    let asset: PHAsset
    var thumbnail: UIImage?
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

    /// Safely request a single image from PHImageManager.
    /// PHImageManager.requestImage may call its result handler MORE THAN ONCE
    /// (even with `.highQualityFormat`). We use NSLock to guarantee the
    /// continuation is resumed exactly once, preventing SIGABRT.
    private func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit
    ) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = UserDefaults.standard.bool(forKey: "iCloudPhotoDownload")

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, _ in
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
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

        let scanSize = CGSize(width: 800, height: 800)
        let thumbSize = CGSize(width: 200, height: 200)
        var detected: [ScannedPhoto] = []

        for i in 0..<total {
            // Support cancellation
            if Task.isCancelled { break }

            let asset = assets[i]

            guard let image = await requestImage(for: asset, targetSize: scanSize) else {
                scanProgress = Double(i + 1) / Double(total)
                continue
            }

            if await ocrService.isInBodyReport(image) {
                let thumb = await requestImage(for: asset, targetSize: thumbSize, contentMode: .aspectFill)
                detected.append(ScannedPhoto(asset: asset, thumbnail: thumb))
            }

            scanProgress = Double(i + 1) / Double(total)
        }

        scannedPhotos = detected
        isScanning = false
    }

    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await requestImage(for: asset, targetSize: PHImageManagerMaximumSize)
    }
}
