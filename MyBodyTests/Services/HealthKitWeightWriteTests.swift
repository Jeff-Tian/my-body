import XCTest
import HealthKit
@testable import MyBody

/// Unit tests for the Trends → Apple Health weight write feature.
///
/// **Phase 2 status (2026-05-24):** Ash has *proposed* `HealthKitService
/// .writeWeightSamples(_:) -> HealthKitWriteResult` but has not yet shipped
/// the implementation or the `HealthKitWriting` protocol seam that Parker
/// requested in the Phase 1 test plan (`.squad/decisions.md`).
///
/// This file therefore contains two kinds of tests:
///
/// 1. **Active tests** — exercise pure logic that doesn't need an
///    `HKHealthStore` mock: deterministic sync-identifier formatting,
///    pre-flight filtering arithmetic against a test-local mirror of the
///    planned filter, and `HealthKitWriteResult` aggregation. These
///    encode the spec from `decisions.md` so Ash can target them.
///
/// 2. **Skipped tests** — flagged with `XCTSkip` in the
///    `// MARK: - TODO: needs HealthKitWriting protocol` section. They
///    name the case and the required injection point; they will activate
///    the moment Ash exposes a fakeable surface. Per Parker charter: do
///    NOT mock `HKHealthStore` directly — wait for the protocol.
///
/// Confirmed scope (Jeff, 2026-05-24): default all-history with user
/// override, dedup via `HKMetadataKeySyncIdentifier`, detailed result
/// dialog, existing call sites refactored.
final class HealthKitWeightWriteTests: XCTestCase {

    // MARK: - Sync identifier construction
    //
    // The dedup contract (decisions.md: Ash + Jeff arbitration) is:
    //   HKMetadataKeySyncIdentifier = "mybody.inbody.\(record.id.uuidString)"
    // HealthKit dedupes by SyncIdentifier *within the same source*, so the
    // string format MUST be stable across app versions and reinstalls.

    func test_syncIdentifier_formatIsStable() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let record = InBodyRecord(id: id, scanDate: Date())
        XCTAssertEqual(
            Self.syncIdentifier(for: record),
            "mybody.inbody.11111111-2222-3333-4444-555555555555"
        )
    }

    func test_syncIdentifier_isDeterministicForSameRecord() {
        let record = InBodyRecord(id: UUID(), scanDate: Date())
        XCTAssertEqual(Self.syncIdentifier(for: record), Self.syncIdentifier(for: record))
    }

    func test_syncIdentifier_differsAcrossRecords() {
        let a = InBodyRecord(id: UUID(), scanDate: Date())
        let b = InBodyRecord(id: UUID(), scanDate: Date())
        XCTAssertNotEqual(Self.syncIdentifier(for: a), Self.syncIdentifier(for: b))
    }

    // MARK: - Pre-flight input filtering
    //
    // The planned API filters out records whose weight is nil or <= 0 BEFORE
    // talking to HealthKit (decisions.md: Ash Phase 2 API). A future-dated
    // scanDate is *not* currently spec'd as invalid — flagged below as an
    // open question if Jeff wants it. The test-local `partitionForWrite`
    // mirrors the spec so it will be straightforward to swap in
    // `HealthKitService.partitionForWrite(_:)` (or whatever Ash names it)
    // once it ships.

    func test_partition_emptyInput_returnsZeroCounts() {
        let parts = Self.partitionForWrite([])
        XCTAssertTrue(parts.writable.isEmpty)
        XCTAssertTrue(parts.skippedInvalid.isEmpty)
    }

    func test_partition_filtersNilWeight() {
        let r = InBodyRecord(id: UUID(), scanDate: Date(), weight: nil)
        let parts = Self.partitionForWrite([r])
        XCTAssertEqual(parts.writable.count, 0)
        XCTAssertEqual(parts.skippedInvalid.count, 1)
    }

    func test_partition_filtersNonPositiveWeight() {
        let zero = InBodyRecord(id: UUID(), scanDate: Date(), weight: 0)
        let negative = InBodyRecord(id: UUID(), scanDate: Date(), weight: -5)
        let parts = Self.partitionForWrite([zero, negative])
        XCTAssertEqual(parts.writable.count, 0)
        XCTAssertEqual(parts.skippedInvalid.count, 2)
    }

    func test_partition_keepsValidWeight() {
        let r = InBodyRecord(id: UUID(), scanDate: Date(), weight: 68.1)
        let parts = Self.partitionForWrite([r])
        XCTAssertEqual(parts.writable.count, 1)
        XCTAssertEqual(parts.skippedInvalid.count, 0)
    }

    func test_partition_mixedBatch_splitsCorrectly() {
        let valid1 = InBodyRecord(id: UUID(), scanDate: Date(), weight: 68.1)
        let valid2 = InBodyRecord(id: UUID(), scanDate: Date(), weight: 70.4)
        let nilWeight = InBodyRecord(id: UUID(), scanDate: Date(), weight: nil)
        let zero = InBodyRecord(id: UUID(), scanDate: Date(), weight: 0)
        let parts = Self.partitionForWrite([valid1, valid2, nilWeight, zero])
        XCTAssertEqual(parts.writable.count, 2)
        XCTAssertEqual(parts.skippedInvalid.count, 2)
    }

    // MARK: - HealthKitWriteResult aggregation
    //
    // Mirrors Ash's proposed struct in `decisions.md`. Once Ash exports the
    // real type, delete the local `MockWriteResult` and re-point these
    // assertions; the math is the contract.

    func test_writeResult_totalsAcrossCategories() {
        let result = MockWriteResult(
            written: 3,
            skippedDuplicate: 1,
            skippedInvalid: 2,
            failed: [(UUID(), HealthKitError.notAuthorized)]
        )
        XCTAssertEqual(result.written + result.skippedDuplicate + result.skippedInvalid + result.failed.count, 7)
    }

    func test_writeResult_allWrittenIsHappyPath() {
        let result = MockWriteResult(written: 5, skippedDuplicate: 0, skippedInvalid: 0, failed: [])
        XCTAssertEqual(result.written, 5)
        XCTAssertTrue(result.failed.isEmpty)
    }

    // MARK: - TODO: needs HealthKitWriting protocol
    //
    // These cases require injecting a fake into `HealthKitService` (or the
    // proposed `HealthKitWriting` protocol). They will compile-bind to the
    // real types once Ash ships the seam; until then they document the
    // expected behavior and skip rather than fail.

    func test_writeWeightSamples_notAuthorized_throwsBeforeWrite() throws {
        throw XCTSkip("Waiting on Ash: HealthKitWriting protocol + FakeHealthKitWriter injection. " +
                      "Expected: when auth status is .sharingDenied, the bulk API throws HealthKitError.notAuthorized " +
                      "without invoking save(); no samples are persisted.")
    }

    func test_writeWeightSamples_unavailableDevice_throws() throws {
        throw XCTSkip("Waiting on Ash: needs fake whose isAvailable == false. " +
                      "Expected: throws HealthKitError.unavailable on Catalyst/unsupported devices.")
    }

    func test_writeWeightSamples_duplicateSyncIdentifier_isSkipped() throws {
        throw XCTSkip("Waiting on Ash: needs fake that simulates HK's SyncIdentifier dedup. " +
                      "Expected: re-running with same recordIDs increments skippedDuplicate, not written.")
    }

    func test_writeWeightSamples_concurrentWrites_serialize() throws {
        throw XCTSkip("Waiting on Ash: needs fake to observe call ordering. " +
                      "Expected: two concurrent .writeWeightSamples calls do not interleave HKHealthStore.save batches.")
    }

    func test_writeWeightSamples_metadataIncludesSyncIdentifier() throws {
        throw XCTSkip("Waiting on Ash: needs fake that captures the [HKObject] passed to save(). " +
                      "Expected: every sample carries HKMetadataKeySyncIdentifier = \"mybody.inbody.\\(record.id.uuidString)\".")
    }

    func test_writeWeightSamples_dateBoundariesPreserved() throws {
        throw XCTSkip("Waiting on Ash: needs fake that captures sample start/end dates. " +
                      "Expected: HKQuantitySample.start == record.scanDate and end == record.scanDate (point-in-time sample).")
    }

    // MARK: - Helpers

    /// Mirror of the dedup contract from `.squad/decisions.md`. Will be
    /// replaced by the production helper (likely a private function in
    /// `HealthKitService`) once Ash exports it.
    static func syncIdentifier(for record: InBodyRecord) -> String {
        "mybody.inbody.\(record.id.uuidString)"
    }

    /// Mirror of the planned pre-flight filter. Production version will
    /// live in `HealthKitService.writeWeightSamples` and bump
    /// `result.skippedInvalid` instead of returning a separate array.
    static func partitionForWrite(_ records: [InBodyRecord])
        -> (writable: [InBodyRecord], skippedInvalid: [InBodyRecord]) {
        var writable: [InBodyRecord] = []
        var skipped: [InBodyRecord] = []
        for r in records {
            if let w = r.weight, w > 0 {
                writable.append(r)
            } else {
                skipped.append(r)
            }
        }
        return (writable, skipped)
    }

    /// Local mirror of Ash's proposed `HealthKitWriteResult`. Delete once
    /// `HealthKitService` exports the real type.
    struct MockWriteResult {
        var written: Int
        var skippedDuplicate: Int
        var skippedInvalid: Int
        var failed: [(recordID: UUID, error: Error)]
    }
}
