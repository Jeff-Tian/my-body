import SwiftUI

struct BodyCompositionCard: View {
    let items: [(label: String, value: String, status: MetricStatus?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("身体成分", systemImage: "figure.stand")
                .font(.headline)
                .foregroundColor(.appGreen)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.label)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
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
