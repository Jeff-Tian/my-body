import SwiftUI

struct RiskIndicatorCard: View {
    let items: [(label: String, value: String, status: MetricStatus?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("风险指标", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundColor(.appGreen)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.label)
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Spacer()
                    Text(item.value)
                        .fontWeight(.medium)
                    if let status = item.status {
                        StatusBadge(status: status)
                    }
                }
                .font(.subheadline)
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
