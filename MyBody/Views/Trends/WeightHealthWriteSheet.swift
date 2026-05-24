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

    var phase: Phase = .idle
    var showRangeDialog = false
    var showResultAlert = false
    var showErrorAlert = false
    var showFailedDetails = false

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
            phase = .result(HealthKitWriteResult())
            showResultAlert = true
            return
        }
        Task { await runWrite(records: records) }
    }

    private func runWrite(records: [InBodyRecord]) async {
        phase = .writing
        do {
            let result = try await service.writeWeightSamples(records)
            phase = .result(result)
            showResultAlert = true
        } catch let error as HealthKitError {
            let denied = (error == .notAuthorized)
            phase = .error(message: error.errorDescription ?? "\(error)", isAuthDenied: denied)
            showErrorAlert = true
        } catch {
            phase = .error(message: error.localizedDescription, isAuthDenied: false)
            showErrorAlert = true
        }
    }

    var isWriting: Bool {
        if case .writing = phase { return true }
        return false
    }

    var resultForDisplay: HealthKitWriteResult? {
        if case .result(let r) = phase { return r }
        return nil
    }
}
