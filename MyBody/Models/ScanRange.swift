import Foundation

enum ScanRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case last30Days = "last30"
    case last90Days = "last90"
    case lastYear = "lastYear"
    case all = "all"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .last30Days: return "最近 30 天"
        case .last90Days: return "最近 90 天"
        case .lastYear: return "最近一年"
        case .all: return "全部照片"
        }
    }

    /// Start date cutoff. Returns nil for .all (no filter).
    var startDate: Date? {
        startDate(anchoredAt: Date())
    }

    /// Start date cutoff computed relative to an explicit anchor instead of `now`.
    ///
    /// Use this to FREEZE a scan window at scan start: capture the anchor once,
    /// persist it in the checkpoint, and recompute the same cutoff on resume so
    /// the window does not drift forward between sessions. Returns nil for `.all`.
    func startDate(anchoredAt anchor: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .last30Days: return calendar.date(byAdding: .day, value: -30, to: anchor)
        case .last90Days: return calendar.date(byAdding: .day, value: -90, to: anchor)
        case .lastYear: return calendar.date(byAdding: .year, value: -1, to: anchor)
        case .all: return nil
        }
    }

    static var current: ScanRange {
        let raw = UserDefaults.standard.string(forKey: "scanRange") ?? ScanRange.last90Days.rawValue
        return ScanRange(rawValue: raw) ?? .last90Days
    }
}
