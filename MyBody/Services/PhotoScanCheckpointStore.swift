import Foundation

struct PhotoScanResumeItem: Equatable, Sendable {
    let localIdentifier: String
    let creationDate: Date?
}

struct PhotoScanCheckpoint: Codable, Equatable, Sendable {
    let scanRange: ScanRange
    let lastProcessedAssetIdentifier: String
    let lastProcessedCreationDate: Date?
    let processedCount: Int
    let detectedCount: Int
    let detectedAssetIdentifiers: [String]
    var completed: Bool

    init(
        scanRange: ScanRange,
        lastProcessedAssetIdentifier: String,
        lastProcessedCreationDate: Date?,
        processedCount: Int,
        detectedCount: Int,
        detectedAssetIdentifiers: [String] = [],
        completed: Bool
    ) {
        self.scanRange = scanRange
        self.lastProcessedAssetIdentifier = lastProcessedAssetIdentifier
        self.lastProcessedCreationDate = lastProcessedCreationDate
        self.processedCount = processedCount
        self.detectedCount = detectedCount
        self.detectedAssetIdentifiers = detectedAssetIdentifiers
        self.completed = completed
    }

    private enum CodingKeys: String, CodingKey {
        case scanRange
        case lastProcessedAssetIdentifier
        case lastProcessedCreationDate
        case processedCount
        case detectedCount
        case detectedAssetIdentifiers
        case completed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanRange = try container.decode(ScanRange.self, forKey: .scanRange)
        lastProcessedAssetIdentifier = try container.decode(String.self, forKey: .lastProcessedAssetIdentifier)
        lastProcessedCreationDate = try container.decodeIfPresent(Date.self, forKey: .lastProcessedCreationDate)
        processedCount = try container.decode(Int.self, forKey: .processedCount)
        detectedCount = try container.decode(Int.self, forKey: .detectedCount)
        detectedAssetIdentifiers = try container.decodeIfPresent([String].self, forKey: .detectedAssetIdentifiers) ?? []
        completed = try container.decode(Bool.self, forKey: .completed)
    }

    func resumeStartIndex(in assets: [PhotoScanResumeItem]) -> Int {
        guard !completed else { return 0 }

        if let exactIndex = assets.firstIndex(where: { $0.localIdentifier == lastProcessedAssetIdentifier }) {
            return assets.index(after: exactIndex)
        }

        guard let lastProcessedCreationDate else { return 0 }
        return assets.firstIndex { item in
            guard let creationDate = item.creationDate else { return false }
            return creationDate <= lastProcessedCreationDate
        } ?? assets.count
    }
}

protocol PhotoScanCheckpointStoring: Sendable {
    func load(for scanRange: ScanRange) throws -> PhotoScanCheckpoint?
    func save(_ checkpoint: PhotoScanCheckpoint) throws
    func markCompleted(for scanRange: ScanRange) throws
}

final class UserDefaultsPhotoScanCheckpointStore: PhotoScanCheckpointStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let keyPrefix = "photoScanCheckpoint"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for scanRange: ScanRange) throws -> PhotoScanCheckpoint? {
        guard let data = defaults.data(forKey: key(for: scanRange)) else { return nil }
        return try decoder.decode(PhotoScanCheckpoint.self, from: data)
    }

    func save(_ checkpoint: PhotoScanCheckpoint) throws {
        let data = try encoder.encode(checkpoint)
        defaults.set(data, forKey: key(for: checkpoint.scanRange))
    }

    func markCompleted(for scanRange: ScanRange) throws {
        guard var checkpoint = try load(for: scanRange) else { return }
        checkpoint.completed = true
        try save(checkpoint)
    }

    private func key(for scanRange: ScanRange) -> String {
        "\(keyPrefix).\(scanRange.rawValue)"
    }
}