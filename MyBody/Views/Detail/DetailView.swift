import SwiftUI
import SwiftData

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let record: InBodyRecord
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var showFullPhoto = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Photo
                if let data = record.photoData, let uiImage = UIImage(data: data) {
                    Button { showFullPhoto = true } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Score
                if let score = record.inbodyScore {
                    ScoreRingView(score: score, size: 140)
                }

                // Date
                Text(record.formattedDateTime)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Body Composition
                detailSection("身体成分", icon: "figure.stand") {
                    metricDetail("体重", value: record.weight, unit: "kg", ref: ReferenceRanges.weight)
                    metricDetail("骨骼肌", value: record.skeletalMuscle, unit: "kg", ref: ReferenceRanges.skeletalMuscle)
                    metricDetail("体脂肪", value: record.bodyFatMass, unit: "kg", ref: ReferenceRanges.bodyFatMass)
                    metricSimple("身体水分", value: record.totalBodyWater, unit: "kg")
                    metricSimple("去脂体重", value: record.leanBodyMass, unit: "kg")
                }

                // Obesity Analysis
                detailSection("肥胖分析", icon: "chart.bar.fill") {
                    metricDetail("BMI", value: record.bmi, unit: "", ref: ReferenceRanges.bmi)
                    metricDetail("体脂率", value: record.bodyFatPercent, unit: "%", ref: ReferenceRanges.bodyFatPercent)
                    metricDetail("腰臀比", value: record.whr, unit: "", ref: ReferenceRanges.whr)
                }

                // Other Metrics
                detailSection("综合指标", icon: "heart.text.square.fill") {
                    if let score = record.inbodyScore {
                        HStack {
                            Text("InBody评分")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(score)")
                                .fontWeight(.medium)
                            StatusBadge(status: ReferenceRanges.scoreStatus(score))
                        }
                        .font(.subheadline)
                    }
                    if let vf = record.visceralFatLevel {
                        HStack {
                            Text("内脏脂肪等级")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(vf)")
                                .fontWeight(.medium)
                            StatusBadge(status: ReferenceRanges.visceralFatStatus(vf))
                        }
                        .font(.subheadline)
                    }
                    metricDetail("基础代谢", value: record.bmr, unit: "kcal", ref: ReferenceRanges.bmr)
                    metricSimple("每日所需热量", value: record.dailyCalorie, unit: "kcal")
                }

                // Segmental
                SegmentalDiagramView(record: record)

                DisclaimerFooter()
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("报告详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                modelContext.delete(record)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("删除后无法恢复，确定要删除这条记录吗？")
        }
        .sheet(isPresented: $showEditSheet) {
            EditRecordView(record: record)
        }
        .fullScreenCover(isPresented: $showFullPhoto) {
            FullPhotoView(photoData: record.photoData)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detailSection(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.appGreen)
            content()
        }
        .cardStyle()
    }

    @ViewBuilder
    private func metricDetail(_ label: String, value: Double?, unit: String, ref: ReferenceRange) -> some View {
        if let v = value {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(formatValue(v, unit: unit)) \(unit)")
                    .fontWeight(.medium)
                StatusBadge(status: ref.status(for: v))
            }
            .font(.subheadline)
            Text("正常: \(ref.displayRange)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func metricSimple(_ label: String, value: Double?, unit: String) -> some View {
        if let v = value {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(formatValue(v, unit: unit)) \(unit)")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
        }
    }

    private func formatValue(_ v: Double, unit: String) -> String {
        if unit == "kcal" { return v.formatted0 }
        if unit == "" && v < 2 { return v.formatted2 }
        return v.formatted1
    }
}

struct FullPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    let photoData: Data?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let data = photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }
}
