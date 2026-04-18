import Foundation
import SwiftData
import SwiftUI

enum MetricType: String, CaseIterable, Identifiable {
    case weight = "体重"
    case bmi = "BMI"
    case bodyFatPercent = "体脂率"
    case skeletalMuscle = "骨骼肌"
    case inbodyScore = "InBody评分"
    case whr = "腰臀比"
    case bmr = "基础代谢"
    case visceralFat = "内脏脂肪"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .weight, .skeletalMuscle: return "kg"
        case .bmi, .whr: return ""
        case .bodyFatPercent: return "%"
        case .inbodyScore: return "分"
        case .bmr: return "kcal"
        case .visceralFat: return ""
        }
    }

    var referenceRange: (min: Double, max: Double)? {
        switch self {
        case .weight: return (53.4, 72.3)
        case .bmi: return (18.5, 25.0)
        case .bodyFatPercent: return (10, 20)
        case .skeletalMuscle: return (26.8, 32.7)
        case .inbodyScore: return (80, 100)
        case .whr: return (0.80, 0.90)
        case .bmr: return (1497, 1747)
        case .visceralFat: return (1, 9)
        }
    }

    func value(from record: InBodyRecord) -> Double? {
        switch self {
        case .weight: return record.weight
        case .bmi: return record.bmi
        case .bodyFatPercent: return record.bodyFatPercent
        case .skeletalMuscle: return record.skeletalMuscle
        case .inbodyScore: return record.inbodyScore.map { Double($0) }
        case .whr: return record.whr
        case .bmr: return record.bmr
        case .visceralFat: return record.visceralFatLevel.map { Double($0) }
        }
    }
}

enum TimeFilter: String, CaseIterable, Identifiable {
    case last3 = "近3次"
    case last6 = "近6次"
    case all = "全部"

    var id: String { rawValue }
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

@MainActor
@Observable
final class TrendsViewModel {
    var records: [InBodyRecord] = []
    var selectedMetric: MetricType = .weight
    var timeFilter: TimeFilter = .all

    private var modelContext: ModelContext?

    func setup(context: ModelContext) {
        self.modelContext = context
        fetchRecords()
    }

    func fetchRecords() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<InBodyRecord>(
            sortBy: [SortDescriptor(\.scanDate, order: .reverse)]
        )
        do {
            records = try context.fetch(descriptor)
        } catch {
            print("Failed to fetch: \(error)")
        }
    }

    var filteredRecords: [InBodyRecord] {
        switch timeFilter {
        case .last3: return Array(records.prefix(3))
        case .last6: return Array(records.prefix(6))
        case .all: return records
        }
    }

    var chartData: [ChartDataPoint] {
        filteredRecords.reversed().compactMap { record in
            guard let value = selectedMetric.value(from: record) else { return nil }
            return ChartDataPoint(date: record.scanDate, value: value)
        }
    }

    var insightText: String {
        let sorted = records.sorted { $0.scanDate > $1.scanDate }
        guard sorted.count >= 2,
              let latest = selectedMetric.value(from: sorted[0]),
              let previous = selectedMetric.value(from: sorted[1]) else {
            return "需要至少两条记录才能生成趋势分析"
        }

        let diff = latest - previous
        let direction = diff > 0 ? "上升" : diff < 0 ? "下降" : "持平"
        let absDiff = abs(diff)

        let metricName = selectedMetric.rawValue
        let unit = selectedMetric.unit

        if diff == 0 {
            return "\(metricName)与上次相比保持不变"
        }

        return "\(metricName)较上次\(direction)了 \(String(format: "%.1f", absDiff))\(unit)"
    }
}
