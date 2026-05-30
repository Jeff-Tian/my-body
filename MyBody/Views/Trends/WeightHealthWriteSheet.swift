import SwiftUI

/// Lightweight VM that drives the "写入健康" flow.
///
/// Owns its own state machine so `TrendsView` doesn't drown in @State.
/// Lives across the toolbar tap → range pick → progress → result/error alert sequence.
@MainActor
@Observable
final class WeightHealthWriteController {
    enum Phase {
        case idle
        case writing
        case result(HealthKitWriteResult)
        case error(message: String, isAuthDenied: Bool)
    }

    enum Range: String, CaseIterable, Identifiable {
        case allHistory
        case currentChart
        case last30Days

        var id: String { rawValue }

        var localizedTitle: LocalizedStringKey {
            switch self {
            case .allHistory: return "全部历史"
            case .currentChart: return "当前图表范围"
            case .last30Days: return "最近 30 天"
            }
        }
    }

    /// Payload for the error alert. Kept independent from `phase` so the alert's
    /// lifetime is owned solely by user dismissal — not by any state transition.
    struct ErrorInfo: Equatable {
        let message: String
        let isAuthDenied: Bool
    }

    var phase: Phase = .idle
    var showRangeDialog = false
    var showFailedDetails = false

    /// Result snapshot driving the "写入完成" alert. Set once on successful write,
    /// cleared ONLY by user dismissal. Independent of `phase` so a phase change
    /// (e.g. overlay teardown) cannot cancel the alert presentation.
    var pendingResult: HealthKitWriteResult?

    /// Error snapshot driving the auth/error alert. Same stickiness contract as
    /// `pendingResult`: only user dismissal clears it.
    var pendingError: ErrorInfo?

    /// Caller-supplied selector for each range. Keeps this controller free of
    /// `TrendsViewModel` / SwiftData / time filter concerns.
    private let recordsForRange: (Range) -> [InBodyRecord]
    private let service: HealthKitService

    init(
        service: HealthKitService = .shared,
        recordsForRange: @escaping (Range) -> [InBodyRecord]
    ) {
        self.service = service
        self.recordsForRange = recordsForRange
    }

    func userTappedToolbarButton() {
        showRangeDialog = true
    }

    func userPickedRange(_ range: Range) {
        let records = recordsForRange(range).filter { $0.weight != nil && ($0.weight ?? 0) > 0 }
        guard !records.isEmpty else {
            let empty = HealthKitWriteResult()
            phase = .result(empty)
            pendingResult = empty
            return
        }
        Task { await runWrite(records: records) }
    }

    private func runWrite(records: [InBodyRecord]) async {
        phase = .writing
        do {
            let result = try await service.writeWeightSamples(records)
            phase = .result(result)
            pendingResult = result
        } catch let error as HealthKitError {
            let denied = (error == .notAuthorized)
            let info = ErrorInfo(
                message: error.errorDescription ?? "\(error)",
                isAuthDenied: denied
            )
            phase = .error(message: info.message, isAuthDenied: info.isAuthDenied)
            pendingError = info
        } catch {
            let info = ErrorInfo(message: error.localizedDescription, isAuthDenied: false)
            phase = .error(message: info.message, isAuthDenied: info.isAuthDenied)
            pendingError = info
        }
    }

    var isWriting: Bool {
        if case .writing = phase { return true }
        return false
    }
}
