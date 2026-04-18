import SwiftUI

struct ObesityAnalysisCard: View {
    let items: [(label: String, value: String, range: String, status: MetricStatus?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("肥胖分析", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundColor(.appGreen)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.label)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.value)
                            .fontWeight(.medium)
                        if let status = item.status {
                            StatusBadge(status: status)
                        }
                    }
                    Text("正常范围: \(item.range)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)

                if item.label != items.last?.label {
                    Divider()
                }
            }

            if items.isEmpty {
                Text("暂无数据")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
        .cardStyle()
    }
}
