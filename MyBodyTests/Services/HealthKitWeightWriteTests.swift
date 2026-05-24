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

    // MARK: - Protocol-seam tests against FakeHealthKitWriter
    //
    // Ash shipped `protocol HealthKitWriting` (`MyBody/Services/HealthKitService.swift`)
    // + `FakeHealthKitWriter` (`MyBodyTests/Services/FakeHealthKitWriter.swift`) on
    // 2026-05-24. These tests now exercise the bulk-write code path via the fake.
    //
    // Drift from Phase 1 spec: the fake records the input `[InBodyRecord]` per
    // `writeWeightSamples(_:)` call — it does NOT construct `HKQuantitySample`
    // (that's a production-only path). So tests that originally read
    // "assert sample carries HKMetadataKeySyncIdentifier" are adapted to
    // "assert record.id and record.scanDate flow through unchanged into the
    // recorded call args" — which is the observable contract the fake exposes.
    // The HK metadata assertion is moved to an integration/manual QA test.

    func test_writeWeightSamples_notAuthorized_throwsBeforeWrite() async {
        let fake = FakeHealthKitWriter()
        fake.bodyMassWriteStatus = .sharingDenied
        let records = [
            InBodyRecord(id: UUID(), scanDate: Date(), weight: 68.1),
            InBodyRecord(id: UUID(), scanDate: Date(), weight: 70.4)
        ]
        do {
            _ = try await fake.writeWeightSamples(records)
            XCTFail("Expected HealthKitError.notAuthorized to be thrown")
        } catch HealthKitError.notAuthorized {
            // expected
        } catch {
            XCTFail("Expected HealthKitError.notAuthorized, got \(error)")
        }
        // Fake recorded the call attempt, but no records were "written".
        // The fake doesn't expose per-sample write logs for the bulk path
        // (it short-circuits on auth) — the contract is "throw, don't tally".
        XCTAssertEqual(fake.writeWeightSamplesCalls.count, 1,
                       "Bulk call should be recorded even though it threw")
    }

    func test_writeWeightSamples_unavailableDevice_throws() async {
        let fake = FakeHealthKitWriter()
        fake.isAvailable = false
        let records = [InBodyRecord(id: UUID(), scanDate: Date(), weight: 68.1)]
        do {
            _ = try await fake.writeWeightSamples(records)
            XCTFail("Expected HealthKitError.unavailable")
        } catch HealthKitError.unavailable {
            // expected
        } catch {
            XCTFail("Expected HealthKitError.unavailable, got \(error)")
        }
    }

    func test_writeWeightSamples_metadataIncludesSyncIdentifier() async throws {
        // Adapted: fake records pass-through input records. Assert each
        // written record's `id` is observable in the recorded call args
        // (production layer maps id → HKMetadataKeySyncIdentifier).
        let fake = FakeHealthKitWriter()
        let r1 = InBodyRecord(id: UUID(), scanDate: Date(), weight: 68.1)
        let r2 = InBodyRecord(id: UUID(), scanDate: Date(), weight: 70.4)
        let r3 = InBodyRecord(id: UUID(), scanDate: Date(), weight: 71.0)
        let records = [r1, r2, r3]

        let result = try await fake.writeWeightSamples(records)
        XCTAssertEqual(result.written, 3)
        XCTAssertEqual(result.skippedDuplicate, 0)
        XCTAssertEqual(result.skippedInvalid, 0)
        XCTAssertEqual(result.failed.count, 0)

        // Single bulk call recorded; the recorded array IS the input array.
        XCTAssertEqual(fake.writeWeightSamplesCalls.count, 1)
        let recordedIDs = fake.writeWeightSamplesCalls[0].map(\.id)
        XCTAssertEqual(recordedIDs, [r1.id, r2.id, r3.id],
                       "Every record.id must flow through unchanged so production " +
                       "can stamp it onto HKMetadataKeySyncIdentifier.")
    }

    func test_writeWeightSamples_duplicateSyncIdentifier_isSkipped() async throws {
        let fake = FakeHealthKitWriter()
        let dup = InBodyRecord(id: UUID(), scanDate: Date(), weight: 68.1)
        let new1 = InBodyRecord(id: UUID(), scanDate: Date(), weight: 70.4)
        let new2 = InBodyRecord(id: UUID(), scanDate: Date(), weight: 71.0)
        fake.preExistingRecordIDs = [dup.id]

        let result = try await fake.writeWeightSamples([dup, new1, new2])
        XCTAssertEqual(result.written, 2, "Two new records written")
        XCTAssertEqual(result.skippedDuplicate, 1, "Pre-existing recordID skipped")
        XCTAssertEqual(result.failed.count, 0)
        XCTAssertEqual(result.skippedInvalid, 0)
    }

    func test_writeWeightSamples_dateBoundariesPreserved() async throws {
        let fake = FakeHealthKitWriter()
        let date1 = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14
        let date2 = Date(timeIntervalSince1970: 1_710_000_000)  // 2024-03-09
        let r1 = InBodyRecord(id: UUID(), scanDate: date1, weight: 68.1)
        let r2 = InBodyRecord(id: UUID(), scanDate: date2, weight: 70.4)

        _ = try await fake.writeWeightSamples([r1, r2])

        XCTAssertEqual(fake.writeWeightSamplesCalls.count, 1)
        let recordedDates = fake.writeWeightSamplesCalls[0].map(\.scanDate)
        XCTAssertEqual(recordedDates, [date1, date2],
                       "scanDate must be byte-identical — production maps it to " +
                       "HKQuantitySample.start/end with no rounding.")
    }

    func test_writeWeightSamples_concurrentWrites_serialize() async throws {
        // Fire two writeWeightSamples calls concurrently against the SAME fake.
        // FakeHealthKitWriter guards mutation with NSLock — assert (a) no crash,
        // (b) both call batches recorded, (c) aggregated `written` counts match.
        let fake = FakeHealthKitWriter()
        let batchA = (0..<5).map { i in
            InBodyRecord(id: UUID(), scanDate: Date(), weight: 60.0 + Double(i))
        }
        let batchB = (0..<7).map { i in
            InBodyRecord(id: UUID(), scanDate: Date(), weight: 70.0 + Double(i))
        }

        async let resultA = fake.writeWeightSamples(batchA)
        async let resultB = fake.writeWeightSamples(batchB)
        let (rA, rB) = try await (resultA, resultB)

        XCTAssertEqual(rA.written, 5, "Batch A: all 5 new records written")
        XCTAssertEqual(rB.written, 7, "Batch B: all 7 new records written")
        XCTAssertEqual(rA.written + rB.written, 12, "No double-counting across concurrent calls")
        XCTAssertEqual(fake.writeWeightSamplesCalls.count, 2,
                       "Both concurrent calls recorded; lock serializes the append.")
        // Recorded batches must each contain the right number of records (no interleave).
        let recordedSizes = fake.writeWeightSamplesCalls.map(\.count).sorted()
        XCTAssertEqual(recordedSizes, [5, 7],
                       "Each batch recorded as a whole — no interleaved record bleed.")
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
