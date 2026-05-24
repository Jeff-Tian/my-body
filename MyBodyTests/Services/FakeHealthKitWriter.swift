import Foundation
import HealthKit
@testable import MyBody

/// Test double for `HealthKitWriting`. Lets Parker's previously-skipped tests
/// exercise the Trends/Edit/Scan call paths without touching real `HKHealthStore`.
///
/// Concurrency: tests may call from multiple actors; mutation is guarded by `NSLock`.
/// `@unchecked Sendable` because the lock provides the actual safety.
final class FakeHealthKitWriter: HealthKitWriting, @unchecked Sendable {

    // MARK: - Configurable behavior

    /// Mirrors `HealthKitService.isAvailable`. Set `false` to simulate Catalyst /
    /// unsupported devices — `writeWeightSamples` then throws `.unavailable`.
    var isAvailable: Bool = true

    /// Mirrors `HealthKitService.bodyMassWriteStatus`. `.sharingDenied` makes
    /// `writeWeightSamples` throw `.notAuthorized` before any save attempt.
    /// `.notDetermined` triggers `requestAuthorization()` once; if the test
    /// flips `bodyMassWriteStatus` to `.sharingDenied` inside the authorization
    /// closure (`onRequestAuthorization`), the second status check throws.
    var bodyMassWriteStatus: HKAuthorizationStatus = .sharingAuthorized

    /// Error to throw from `requestAuthorization()`. `nil` = succeed.
    var authorizationError: Error?

    /// Optional hook fired inside `requestAuthorization()` *before* the error
    /// throw. Use it to mutate `bodyMassWriteStatus` so the post-prompt status
    /// check sees the new value.
    var onRequestAuthorization: (() -> Void)?

    /// `recordID`s pretended to already exist in HealthKit. Counted as
    /// `skippedDuplicate` in `writeWeightSamples` results.
    var preExistingRecordIDs: Set<UUID> = []

    /// `recordID`s that should fail at save time. Counted as `failed` in
    /// `writeWeightSamples` results; throw from `saveWeight(_:date:recordID:)`.
    var failingRecordIDs: Set<UUID> = []

    /// Error used when a record is in `failingRecordIDs`.
    var saveError: Error = HealthKitError.invalidValue

    // MARK: - Call recording (thread-safe)

    private let lock = NSLock()
    private var _authorizationCallCount = 0
    private var _saveWeightCalls: [(kg: Double, date: Date, recordID: UUID)] = []
    private var _writeWeightSamplesCalls: [[InBodyRecord]] = []

    var authorizationCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _authorizationCallCount
    }

    var saveWeightCalls: [(kg: Double, date: Date, recordID: UUID)] {
        lock.lock(); defer { lock.unlock() }
        return _saveWeightCalls
    }

    var writeWeightSamplesCalls: [[InBodyRecord]] {
        lock.lock(); defer { lock.unlock() }
        return _writeWeightSamplesCalls
    }

    // MARK: - HealthKitWriting

    func requestAuthorization() async throws {
        lock.lock(); _authorizationCallCount += 1; lock.unlock()
        onRequestAuthorization?()
        if let err = authorizationError { throw err }
    }

    func saveWeight(_ kg: Double, date: Date, recordID: UUID) async throws {
        lock.lock(); _saveWeightCalls.append((kg, date, recordID)); lock.unlock()
        guard isAvailable else { throw HealthKitError.unavailable }
        if bodyMassWriteStatus == .sharingDenied { throw HealthKitError.notAuthorized }
        if failingRecordIDs.contains(recordID) { throw saveError }
    }

    func writeWeightSamples(_ records: [InBodyRecord]) async throws -> HealthKitWriteResult {
        lock.lock(); _writeWeightSamplesCalls.append(records); lock.unlock()

        // 1) Device check (mirrors production pre-flight).
        guard isAvailable else { throw HealthKitError.unavailable }

        // 2) Authorization (mirrors production pre-flight).
        switch bodyMassWriteStatus {
        case .sharingDenied:
            throw HealthKitError.notAuthorized
        case .notDetermined:
            try await requestAuthorization()
            if bodyMassWriteStatus == .sharingDenied {
                throw HealthKitError.notAuthorized
            }
        case .sharingAuthorized:
            break
        @unknown default:
            break
        }

        // 3) Reuse the SAME partition logic production uses. If this drifts,
        //    production drifts too — the fake stays honest.
        let parts = HealthKitService.partitionForWrite(records)
        var result = HealthKitWriteResult()
        result.skippedInvalid = parts.skippedInvalid.count

        // 4) Categorize remaining writables: pre-existing → skippedDuplicate,
        //    failing → failed, else → written.
        for record in parts.writable {
            if preExistingRecordIDs.contains(record.id) {
                result.skippedDuplicate += 1
            } else if failingRecordIDs.contains(record.id) {
                result.failed.append((recordID: record.id, error: saveError))
            } else {
                result.written += 1
            }
        }

        return result
    }
}
