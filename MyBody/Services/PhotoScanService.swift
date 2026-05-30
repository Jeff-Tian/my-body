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
    @Published var totalCount: Int = 0
    @Published var processedCount: Int = 0
    @Published var detectedCount: Int = 0
    @Published var stageMessage: String = ""

    private let ocrService = OCRService()

    func requestAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return true }

        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return newStatus == .authorized || newStatus == .limited
    }

    /// Load image synchronously. isSynchronous=true guarantees the callback
    /// fires exactly once before requestImage returns — no continuation needed.
    ///
    /// - Parameter allowNetwork: when `true`, PhotoKit 会在原图仅存于 iCloud 时
    ///   通过网络下载后再返回，确保拿到完整图片。扫描粗筛阶段传 `false`（避免
    ///   对相册里成千上万张无关照片触发 iCloud 下载）；parse / 全图加载阶段
    ///   传 `true`，保证导入后记录里一定有图。
    private nonisolated func requestImageSync(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit,
        allowNetwork: Bool = false
    ) -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = true
        options.isNetworkAccessAllowed = allowNetwork

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
        stageMessage = "正在请求相册权限..."
        guard await requestAuthorization() else {
            stageMessage = "未获得相册访问权限"
            isScanning = false
            return
        }

        isScanning = true
        scanProgress = 0
        processedCount = 0
        detectedCount = 0
        totalCount = 0
        scannedPhotos = []
        stageMessage = "正在读取相册..."

        let range = ScanRange.current
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        if let startDate = range.startDate {
            fetchOptions.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@",
                PHAssetMediaType.image.rawValue,
                startDate as NSDate
            )
        } else {
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        }

        let assets = PHAsset.fetchAssets(with: fetchOptions)

        let total = assets.count
        totalCount = total
        guard total > 0 else {
            stageMessage = "相册中没有符合条件的照片"
            isScanning = false
            return
        }

        stageMessage = "正在准备扫描..."

        // Collect assets into an array (PHFetchResult is not Sendable)
        var assetList: [PHAsset] = []
        assetList.reserveCapacity(total)
        for i in 0..<total {
            assetList.append(assets[i])
        }

        let scanSize = CGSize(width: 800, height: 800)
        let thumbSize = CGSize(width: 200, height: 200)
        let ocr = ocrService
        // 用户可在 Settings 打开「扫描时也下载 iCloud」开关。默认关：扫描只用
        // 本地缓存，速度快、不耗流量。开启后会对粗筛阶段每张照片触发 iCloud
        // 下载（可能很慢、流量大）。无论这里如何，parse 阶段始终会下载 iCloud。
        let scanAllowsNetwork = UserDefaults.standard.bool(forKey: "iCloudPhotoDownload")

        // Run ALL heavy work (image loading + OCR) on a background thread
        let detected: [ScannedPhoto] = await Task.detached(priority: .userInitiated) {
            var results: [ScannedPhoto] = []

            for (i, asset) in assetList.enumerated() {
                if Task.isCancelled { break }

                await MainActor.run {
                    self.stageMessage = "正在读取第 \(i + 1) / \(total) 张照片..."
                }

                guard let image = self.requestImageSync(
                    for: asset,
                    targetSize: scanSize,
                    allowNetwork: scanAllowsNetwork
                ) else {
                    await MainActor.run {
                        self.processedCount = i + 1
                        self.scanProgress = Double(i + 1) / Double(total)
                    }
                    continue
                }

                await MainActor.run {
                    self.stageMessage = "正在识别第 \(i + 1) / \(total) 张照片..."
                }

                if ocr.isInBodyReport(image) {
                    let thumb = self.requestImageSync(
                        for: asset,
                        targetSize: thumbSize,
                        contentMode: .aspectFill,
                        allowNetwork: scanAllowsNetwork
                    )
                    results.append(ScannedPhoto(asset: asset, thumbnail: thumb))
                    let detectedSoFar = results.count
                    await MainActor.run {
                        self.detectedCount = detectedSoFar
                    }
                }

                await MainActor.run {
                    self.processedCount = i + 1
                    self.scanProgress = Double(i + 1) / Double(total)
                }
            }

            return results
        }.value

        scannedPhotos = detected
        stageMessage = detected.isEmpty ? "扫描完成，未发现报告" : "扫描完成"
        isScanning = false
    }

    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            // 全图加载用于导入/详情：原图只在 iCloud 时，自动下载到本地，
            // 避免空记录（截图里只有📄图标、没数据的行就是这种情况）。
            self.requestImageSync(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                allowNetwork: true
            )
        }.value
    }
}
