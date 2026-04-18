import SwiftUI

struct StatusBadge: View {
    let status: MetricStatus

    var body: some View {
        Text(status.label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.swiftUIColor.opacity(0.15))
            .foregroundColor(status.color.swiftUIColor)
            .clipShape(Capsule())
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    let unit: String
    var status: MetricStatus? = nil
    var normalRange: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.semibold)
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                if let status {
                    StatusBadge(status: status)
                }
            }
            if let range = normalRange {
                Text("正常: \(range)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .font(.subheadline)
    }
}

struct DisclaimerFooter: View {
    var body: some View {
        Text("仅供健康参考，不作为医疗诊断依据。")
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}
