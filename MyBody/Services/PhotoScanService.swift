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
    /// `true` when the most recent `scanPhotoLibrary()` call resumed directly
    /// into the recognition phase (skipping the album scan) because a previous
    /// run finished scanning but was interrupted during recognition. The view
    /// model uses this to jump straight to parsing instead of showing the
    /// confirmation grid again.
    @Published var resumedRecognition = false

    private let ocrService = OCRService()
    private let checkpointStore: PhotoScanCheckpointStoring

    init(checkpointStore: PhotoScanCheckpointStoring = UserDefaultsPhotoScanCheckpointStore()) {
        self.checkpointStore = checkpointStore
    }

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

        let previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }

        isScanning = true
        scanProgress = 0
        processedCount = 0
        detectedCount = 0
        totalCount = 0
        scannedPhotos = []
        resumedRecognition = false
        stageMessage = "正在读取相册..."

        let range = ScanRange.current

        // If a previous run already finished SCANNING but was interrupted during
        // RECOGNITION, resume straight into recognition: rebuild the detected
        // photos from the checkpoint and skip the (slow) album scan entirely.
        if let resumeCheckpoint = (try? checkpointStore.load(for: range)),
           resumeCheckpoint.needsRecognitionResume {
            resumedRecognition = true
            await restoreDetectedPhotos(from: resumeCheckpoint)
            return
        }

        // Load any resumable mid-scan checkpoint up front so we can FREEZE the
        // scan window. `needsRecognitionResume` checkpoints were already handled
        // above; any `completed` checkpoint reaching here is fully done, so we
        // treat it as "nothing to resume" and start a fresh scan.
        let existingCheckpoint = (try? checkpointStore.load(for: range))
            .flatMap { $0.completed ? nil : $0 }

        // Freeze the exact scan window at scan start. When resuming a checkpoint
        // that already has a frozen window, reuse it verbatim so the window does
        // not drift forward (e.g. last90Days shifting by the days elapsed since
        // the original scan). Otherwise capture a fresh anchor now.
        let windowAnchorDate: Date
        let windowStartDate: Date?
        if let existingCheckpoint, existingCheckpoint.hasFrozenWindow {
            windowAnchorDate = existingCheckpoint.windowAnchorDate ?? Date()
            windowStartDate = existingCheckpoint.windowStartDate
        } else {
            let anchor = Date()
            windowAnchorDate = anchor
            windowStartDate = range.startDate(anchoredAt: anchor)
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        if let windowStartDate {
            fetchOptions.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@",
                PHAssetMediaType.image.rawValue,
                windowStartDate as NSDate
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

        let checkpoint = existingCheckpoint
        let resumeItems = assetList.map {
            PhotoScanResumeItem(localIdentifier: $0.localIdentifier, creationDate: $0.creationDate)
        }
        let startIndex = checkpoint?.resumeStartIndex(in: resumeItems) ?? 0
        let resumedDetectedAssetIdentifiers = checkpoint?.detectedAssetIdentifiers ?? []
        let resumedDetectedCount = resumedDetectedAssetIdentifiers.isEmpty
            ? checkpoint?.detectedCount ?? 0
            : resumedDetectedAssetIdentifiers.count

        if startIndex > 0 {
            processedCount = min(startIndex, total)
            detectedCount = resumedDetectedCount
            scanProgress = Double(processedCount) / Double(total)
            stageMessage = "正在继续上次扫描..."
        }

        let scanSize = CGSize(width: 800, height: 800)
        let thumbSize = CGSize(width: 200, height: 200)
        let ocr = ocrService
        let checkpointStore = checkpointStore
        // 用户可在 Settings 打开「扫描时也下载 iCloud」开关。默认关：扫描只用
        // 本地缓存，速度快、不耗流量。开启后会对粗筛阶段每张照片触发 iCloud
        // 下载（可能很慢、流量大）。无论这里如何，parse 阶段始终会下载 iCloud。
        let scanAllowsNetwork = UserDefaults.standard.bool(forKey: "iCloudPhotoDownload")

        // Run ALL heavy work (image loading + OCR) on a background thread
        let scanResult: (detected: [ScannedPhoto], completed: Bool) = await Task.detached(priority: .userInitiated) {
            var results: [ScannedPhoto] = []
            var detectedAssetIdentifiers: [String] = []
            var completed = true

            if !resumedDetectedAssetIdentifiers.isEmpty {
                let assetsByIdentifier = Dictionary(
                    assetList.map { ($0.localIdentifier, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                for identifier in resumedDetectedAssetIdentifiers {
                    guard let asset = assetsByIdentifier[identifier] else { continue }
                    let thumb = self.requestImageSync(
                        for: asset,
                        targetSize: thumbSize,
                        contentMode: .aspectFill,
                        allowNetwork: scanAllowsNetwork
                    )
                    results.append(ScannedPhoto(asset: asset, thumbnail: thumb))
                    detectedAssetIdentifiers.append(identifier)
                }
                let restoredDetectedCount = results.count
                await MainActor.run {
                    self.detectedCount = restoredDetectedCount
                }
            }

            for i in startIndex..<assetList.count {
                if Task.isCancelled {
                    completed = false
                    break
                }

                let asset = assetList[i]

                await MainActor.run {
                    self.stageMessage = "正在读取第 \(i + 1) / \(total) 张照片..."
                }

                guard let image = self.requestImageSync(
                    for: asset,
                    targetSize: scanSize,
                    allowNetwork: scanAllowsNetwork
                ) else {
                    let checkpoint = PhotoScanCheckpoint(
                        scanRange: range,
                        lastProcessedAssetIdentifier: asset.localIdentifier,
                        lastProcessedCreationDate: asset.creationDate,
                        processedCount: i + 1,
                        detectedCount: results.count,
                        detectedAssetIdentifiers: detectedAssetIdentifiers,
                        windowStartDate: windowStartDate,
                        windowAnchorDate: windowAnchorDate,
                        completed: false
                    )
                    try? checkpointStore.save(checkpoint)
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
                    detectedAssetIdentifiers.append(asset.localIdentifier)
                    let detectedSoFar = results.count
                    await MainActor.run {
                        self.detectedCount = detectedSoFar
                    }
                }

                let checkpoint = PhotoScanCheckpoint(
                    scanRange: range,
                    lastProcessedAssetIdentifier: asset.localIdentifier,
                    lastProcessedCreationDate: asset.creationDate,
                    processedCount: i + 1,
                    detectedCount: results.count,
                    detectedAssetIdentifiers: detectedAssetIdentifiers,
                    windowStartDate: windowStartDate,
                    windowAnchorDate: windowAnchorDate,
                    completed: false
                )
                try? checkpointStore.save(checkpoint)

                await MainActor.run {
                    self.processedCount = i + 1
                    self.scanProgress = Double(i + 1) / Double(total)
                }
            }

            return (results, completed)
        }.value

        if scanResult.completed {
            try? checkpointStore.markCompleted(for: range)
        }

        scannedPhotos = scanResult.detected
        stageMessage = scanResult.detected.isEmpty ? "扫描完成，未发现报告" : "扫描完成"
        isScanning = false
    }

    /// Resume the recognition phase after an interruption: rebuild the detected
    /// photos (with thumbnails) directly from the checkpoint's
    /// `detectedAssetIdentifiers`, skipping the album scan entirely. Recognition
    /// itself stays idempotent (already-saved records are de-duplicated), so it
    /// is safe to re-run through all detected photos and skip finished ones.
    private func restoreDetectedPhotos(from checkpoint: PhotoScanCheckpoint) async {
        stageMessage = "正在恢复上次的识别进度..."

        let identifiers = checkpoint.detectedAssetIdentifiers
        guard !identifiers.isEmpty else {
            scannedPhotos = []
            stageMessage = "扫描完成，未发现报告"
            isScanning = false
            return
        }

        let thumbSize = CGSize(width: 200, height: 200)
        let scanAllowsNetwork = UserDefaults.standard.bool(forKey: "iCloudPhotoDownload")

        let restored: [ScannedPhoto] = await Task.detached(priority: .userInitiated) {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            var assetsByIdentifier: [String: PHAsset] = [:]
            fetch.enumerateObjects { asset, _, _ in
                assetsByIdentifier[asset.localIdentifier] = asset
            }

            var photos: [ScannedPhoto] = []
            // Preserve the original detection order.
            for identifier in identifiers {
                guard let asset = assetsByIdentifier[identifier] else { continue }
                let thumb = self.requestImageSync(
                    for: asset,
                    targetSize: thumbSize,
                    contentMode: .aspectFill,
                    allowNetwork: scanAllowsNetwork
                )
                photos.append(ScannedPhoto(asset: asset, thumbnail: thumb))
            }
            return photos
        }.value

        scannedPhotos = restored
        totalCount = checkpoint.processedCount
        processedCount = checkpoint.processedCount
        detectedCount = restored.count
        scanProgress = 1.0
        stageMessage = restored.isEmpty ? "扫描完成，未发现报告" : "扫描完成"
        isScanning = false
    }

    /// Persist that recognition finished for `assetIdentifier` in the current
    /// scan range, so the recognition phase can resume after an interruption.
    func recordRecognized(assetIdentifier: String) {
        try? checkpointStore.markRecognized(assetIdentifier: assetIdentifier, for: ScanRange.current)
    }

    /// Mark the whole 扫描→识别→保存 pipeline complete for the current scan range.
    func recordRecognitionCompleted() {
        try? checkpointStore.markRecognitionCompleted(for: ScanRange.current)
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
