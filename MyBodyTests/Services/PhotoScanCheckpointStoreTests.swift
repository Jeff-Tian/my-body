import XCTest
@testable import MyBody

final class PhotoScanCheckpointStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PhotoScanCheckpointStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndLoadCheckpointForScanRange() throws {
        let store = UserDefaultsPhotoScanCheckpointStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let checkpoint = PhotoScanCheckpoint(
            scanRange: .last90Days,
            lastProcessedAssetIdentifier: "asset-42",
            lastProcessedCreationDate: date,
            processedCount: 42,
            detectedCount: 3,
            detectedAssetIdentifiers: ["report-1", "report-2", "report-3"],
            completed: false
        )

        try store.save(checkpoint)

        let loaded = try XCTUnwrap(store.load(for: .last90Days))
        XCTAssertEqual(loaded.scanRange, .last90Days)
        XCTAssertEqual(loaded.lastProcessedAssetIdentifier, "asset-42")
        XCTAssertEqual(loaded.lastProcessedCreationDate, date)
        XCTAssertEqual(loaded.processedCount, 42)
        XCTAssertEqual(loaded.detectedCount, 3)
        XCTAssertEqual(loaded.detectedAssetIdentifiers, ["report-1", "report-2", "report-3"])
        XCTAssertFalse(loaded.completed)
    }

    func testMissingCheckpointReturnsNil() throws {
        let store = UserDefaultsPhotoScanCheckpointStore(defaults: defaults)

        XCTAssertNil(try store.load(for: .last90Days))
    }

    func testFrozenScanWindowPersistsAndReloads() throws {
        let store = UserDefaultsPhotoScanCheckpointStore(defaults: defaults)
        let windowStart = Date(timeIntervalSince1970: 1_699_000_000)
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let checkpoint = PhotoScanCheckpoint(
            scanRange: .last90Days,
            lastProcessedAssetIdentifier: "asset-7",
            lastProcessedCreationDate: Date(timeIntervalSince1970: 1_699_500_000),
            processedCount: 7,
            detectedCount: 1,
            detectedAssetIdentifiers: ["report-1"],
            windowStartDate: windowStart,
            windowAnchorDate: anchor,
            completed: false
        )

        try store.save(checkpoint)

        let loaded = try XCTUnwrap(store.load(for: .last90Days))
        XCTAssertEqual(loaded.windowStartDate, windowStart)
        XCTAssertEqual(loaded.windowAnchorDate, anchor)
        XCTAssertEqual(loaded, checkpoint)
    }

    func testLegacyCheckpointWithoutFrozenWindowStillDecodes() throws {
        // Simulate a checkpoint persisted before the frozen-window fields existed.
        let legacyJSON = """
        {
            "scanRange": "last90",
            "lastProcessedAssetIdentifier": "legacy-asset",
            "lastProcessedCreationDate": 1234567,
            "processedCount": 12,
            "detectedCount": 2,
            "detectedAssetIdentifiers": ["r-1", "r-2"],
            "completed": false
        }
        """
        defaults.set(Data(legacyJSON.utf8), forKey: "photoScanCheckpoint.last90")

        let store = UserDefaultsPhotoScanCheckpointStore(defaults: defaults)
        let loaded = try XCTUnwrap(store.load(for: .last90Days))

        XCTAssertEqual(loaded.lastProcessedAssetIdentifier, "legacy-asset")
        XCTAssertEqual(loaded.processedCount, 12)
        XCTAssertEqual(loaded.detectedAssetIdentifiers, ["r-1", "r-2"])
        XCTAssertNil(loaded.windowStartDate)
        XCTAssertNil(loaded.windowAnchorDate)
        XCTAssertFalse(loaded.hasFrozenWindow)
    }

    func testMarkCompletedPersistsCompletedCheckpoint() throws {
        let store = UserDefaultsPhotoScanCheckpointStore(defaults: defaults)
        let checkpoint = PhotoScanCheckpoint(
            scanRange: .last90Days,
            lastProcessedAssetIdentifier: "asset-99",
            lastProcessedCreationDate: Date(timeIntervalSince1970: 1_700_000_099),
            processedCount: 99,
            detectedCount: 7,
            completed: false
        )
        try store.save(checkpoint)

        try store.markCompleted(for: .last90Days)

        let loaded = try XCTUnwrap(store.load(for: .last90Days))
        XCTAssertTrue(loaded.completed)
        XCTAssertEqual(loaded.lastProcessedAssetIdentifier, "asset-99")
        XCTAssertEqual(loaded.processedCount, 99)
        XCTAssertEqual(loaded.detectedCount, 7)
    }

    func testMarkCompletedWithoutCheckpointDoesNotCreateOne() throws {
        let store = UserDefaultsPhotoScanCheckpointStore(defaults: defaults)

        try store.markCompleted(for: .last90Days)

        XCTAssertNil(try store.load(for: .last90Days))
    }

    func testCheckpointsForDifferentScanRangesDoNotCollide() throws {
        let store = UserDefaultsPhotoScanCheckpointStore(defaults: defaults)
        let recentCheckpoint = PhotoScanCheckpoint(
            scanRange: .last30Days,
            lastProcessedAssetIdentifier: "recent-asset",
            lastProcessedCreationDate: Date(timeIntervalSince1970: 1_700_000_030),
            processedCount: 30,
            detectedCount: 1,
            completed: false
        )
        let allPhotosCheckpoint = PhotoScanCheckpoint(
            scanRange: .all,
            lastProcessedAssetIdentifier: "all-asset",
            lastProcessedCreationDate: Date(timeIntervalSince1970: 1_700_000_000),
            processedCount: 10_000,
            detectedCount: 42,
            completed: false
        )

        try store.save(recentCheckpoint)
        try store.save(allPhotosCheckpoint)

        XCTAssertEqual(try store.load(for: .last30Days), recentCheckpoint)
        XCTAssertEqual(try store.load(for: .all), allPhotosCheckpoint)
        XCTAssertNil(try store.load(for: .last90Days))
    }

    func testCorruptCheckpointDataThrowsAndDoesNotAffectOtherRanges() throws {
        let store = UserDefaultsPhotoScanCheckpointStore(defaults: defaults)
        let validCheckpoint = PhotoScanCheckpoint(
            scanRange: .all,
            lastProcessedAssetIdentifier: "all-asset",
            lastProcessedCreationDate: Date(timeIntervalSince1970: 1_700_000_000),
            processedCount: 10_000,
            detectedCount: 42,
            completed: false
        )
        try store.save(validCheckpoint)
        defaults.set(Data("not-json".utf8), forKey: "photoScanCheckpoint.last90")

        XCTAssertThrowsError(try store.load(for: .last90Days))
        XCTAssertEqual(try store.load(for: .all), validCheckpoint)
    }

    func testCompletedCheckpointDoesNotResume() throws {
        let checkpoint = PhotoScanCheckpoint(
            scanRange: .last90Days,
            lastProcessedAssetIdentifier: "asset-2",
            lastProcessedCreationDate: Date(timeIntervalSince1970: 200),
            processedCount: 2,
            detectedCount: 1,
            completed: true
        )
        let assets = [
            PhotoScanResumeItem(localIdentifier: "asset-1", creationDate: Date(timeIntervalSince1970: 300)),
            PhotoScanResumeItem(localIdentifier: "asset-2", creationDate: Date(timeIntervalSince1970: 200)),
            PhotoScanResumeItem(localIdentifier: "asset-3", creationDate: Date(timeIntervalSince1970: 100))
        ]

        XCTAssertEqual(checkpoint.resumeStartIndex(in: assets), 0)
    }

    func testResumeStartsAfterExactAssetIdentifierWhenPresent() {
        let checkpoint = PhotoScanCheckpoint(
            scanRange: .last90Days,
            lastProcessedAssetIdentifier: "asset-2",
            lastProcessedCreationDate: Date(timeIntervalSince1970: 200),
            processedCount: 2,
            detectedCount: 1,
            completed: false
        )
        let assets = [
            PhotoScanResumeItem(localIdentifier: "asset-1", creationDate: Date(timeIntervalSince1970: 300)),
            PhotoScanResumeItem(localIdentifier: "asset-2", creationDate: Date(timeIntervalSince1970: 200)),
            PhotoScanResumeItem(localIdentifier: "asset-3", creationDate: Date(timeIntervalSince1970: 100))
        ]

        XCTAssertEqual(checkpoint.resumeStartIndex(in: assets), 2)
    }

    func testResumeFallsBackToCreationDateWithoutSkippingSameTimestampAssets() {
        let checkpoint = PhotoScanCheckpoint(
            scanRange: .last90Days,
            lastProcessedAssetIdentifier: "deleted-asset",
            lastProcessedCreationDate: Date(timeIntervalSince1970: 200),
            processedCount: 2,
            detectedCount: 1,
            completed: false
        )
        let assets = [
            PhotoScanResumeItem(localIdentifier: "asset-1", creationDate: Date(timeIntervalSince1970: 300)),
            PhotoScanResumeItem(localIdentifier: "asset-same-time", creationDate: Date(timeIntervalSince1970: 200)),
            PhotoScanResumeItem(localIdentifier: "asset-older", creationDate: Date(timeIntervalSince1970: 100))
        ]

        XCTAssertEqual(checkpoint.resumeStartIndex(in: assets), 1)
    }

    func testResumeFallsBackToEndWhenCheckpointIsOlderThanVisibleAssets() {
        let checkpoint = PhotoScanCheckpoint(
            scanRange: .last90Days,
            lastProcessedAssetIdentifier: "deleted-older-asset",
            lastProcessedCreationDate: Date(timeIntervalSince1970: 100),
            processedCount: 10_000,
            detectedCount: 12,
            completed: false
        )
        let assets = [
            PhotoScanResumeItem(localIdentifier: "asset-1", creationDate: Date(timeIntervalSince1970: 400)),
            PhotoScanResumeItem(localIdentifier: "asset-2", creationDate: Date(timeIntervalSince1970: 300)),
            PhotoScanResumeItem(localIdentifier: "asset-3", creationDate: Date(timeIntervalSince1970: 200))
        ]

        XCTAssertEqual(checkpoint.resumeStartIndex(in: assets), assets.count)
    }

    func testResumeRestartsWhenIdentifierMissingAndNoCreationDateExists() {
        let checkpoint = PhotoScanCheckpoint(
            scanRange: .last90Days,
            lastProcessedAssetIdentifier: "missing-asset",
            lastProcessedCreationDate: nil,
            processedCount: 10_000,
            detectedCount: 12,
            completed: false
        )
        let assets = [
            PhotoScanResumeItem(localIdentifier: "asset-1", creationDate: Date(timeIntervalSince1970: 300)),
            PhotoScanResumeItem(localIdentifier: "asset-2", creationDate: Date(timeIntervalSince1970: 200))
        ]

        XCTAssertEqual(checkpoint.resumeStartIndex(in: assets), 0)
    }
}