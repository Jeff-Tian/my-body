import SwiftUI

struct SegmentalDiagramView: View {
    let record: InBodyRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("节段分析", systemImage: "figure.arms.open")
                .font(.headline)
                .foregroundColor(.appGreen)

            if let r = record {
                HStack(alignment: .top, spacing: 0) {
                    // Left side labels
                    VStack(alignment: .trailing, spacing: 16) {
                        segLabel("左臂", muscle: r.segMuscleLeftArm, fat: r.segFatLeftArm)
                        Spacer()
                        segLabel("左腿", muscle: r.segMuscleLeftLeg, fat: r.segFatLeftLeg)
                    }
                    .frame(width: 100)

                    // Body silhouette
                    VStack(spacing: 4) {
                        Image(systemName: "figure.stand")
                            .font(.system(size: 80))
                            .foregroundColor(.appGreen.opacity(0.6))

                        if let trunk = r.segMuscleTrunk {
                            VStack(spacing: 2) {
                                Text("躯干")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(trunk.formatted1) kg")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                if let fat = r.segFatTrunk {
                                    Text("\(fat.formatted1)%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Right side labels
                    VStack(alignment: .leading, spacing: 16) {
                        segLabel("右臂", muscle: r.segMuscleRightArm, fat: r.segFatRightArm)
                        Spacer()
                        segLabel("右腿", muscle: r.segMuscleRightLeg, fat: r.segFatRightLeg)
                    }
                    .frame(width: 100)
                }
                .frame(height: 180)
            } else {
                Text("暂无节段数据")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func segLabel(_ name: String, muscle: Double?, fat: Double?) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
            if let m = muscle {
                Text("\(m.formatted1) kg")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            if let f = fat {
                Text("\(f.formatted1)%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if muscle == nil && fat == nil {
                Text("--")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
