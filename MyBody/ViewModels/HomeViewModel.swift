import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    var latestRecord: InBodyRecord?
    var records: [InBodyRecord] = []

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
            latestRecord = records.first
        } catch {
            print("Failed to fetch records: \(error)")
        }
    }

    // MARK: - Computed Properties for Home Cards

    var scoreColor: Color {
        guard let score = latestRecord?.inbodyScore else { return .gray }
        if score >= 80 { return .appGreen }
        if score >= 60 { return .appOrange }
        return .appRed
    }

    var scoreProgress: Double {
        guard let score = latestRecord?.inbodyScore else { return 0 }
        return Double(score) / 100.0
    }

    var bodyCompositionItems: [(label: String, value: String, status: MetricStatus?)] {
        guard let r = latestRecord else { return [] }
        var items: [(String, String, MetricStatus?)] = []
        if let v = r.weight {
            items.append(("体重", "\(v.formatted1) kg", ReferenceRanges.weight.status(for: v)))
        }
        if let v = r.skeletalMuscle {
            items.append(("骨骼肌", "\(v.formatted1) kg", ReferenceRanges.skeletalMuscle.status(for: v)))
        }
        if let v = r.bodyFatMass {
            items.append(("体脂肪", "\(v.formatted1) kg", ReferenceRanges.bodyFatMass.status(for: v)))
        }
        if let v = r.totalBodyWater {
            items.append(("身体水分", "\(v.formatted1) kg", nil))
        }
        if let v = r.leanBodyMass {
            items.append(("去脂体重", "\(v.formatted1) kg", nil))
        }
        return items
    }

    var obesityItems: [(label: String, value: String, range: String, status: MetricStatus?)] {
        guard let r = latestRecord else { return [] }
        var items: [(String, String, String, MetricStatus?)] = []
        if let v = r.bmi {
            items.append(("BMI", v.formatted1, ReferenceRanges.bmi.displayRange, ReferenceRanges.bmi.status(for: v)))
        }
        if let v = r.bodyFatPercent {
            items.append(("体脂率", "\(v.formatted1)%", ReferenceRanges.bodyFatPercent.displayRange, ReferenceRanges.bodyFatPercent.status(for: v)))
        }
        if let v = r.whr {
            items.append(("腰臀比", v.formatted2, ReferenceRanges.whr.displayRange, ReferenceRanges.whr.status(for: v)))
        }
        return items
    }

    var riskItems: [(label: String, value: String, status: MetricStatus?)] {
        guard let r = latestRecord else { return [] }
        var items: [(String, String, MetricStatus?)] = []
        if let v = r.visceralFatLevel {
            items.append(("内脏脂肪等级", "\(v)", ReferenceRanges.visceralFatStatus(v)))
        }
        if let v = r.bmr {
            items.append(("基础代谢", "\(v.formatted0) kcal", ReferenceRanges.bmr.status(for: v)))
        }
        if let v = r.dailyCalorie {
            items.append(("每日所需热量", "\(v.formatted0) kcal", nil))
        }
        return items
    }
}
