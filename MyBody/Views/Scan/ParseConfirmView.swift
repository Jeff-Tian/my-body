import SwiftUI

struct ParseConfirmView: View {
    @State var report: OCRService.ParsedReport
    let image: UIImage?
    let onSave: (OCRService.ParsedReport) -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Photo preview
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                Text("请确认识别结果")
                    .font(.headline)

                Text("橙色标记的字段识别失败，请手动修正")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Editable fields
                VStack(spacing: 12) {
                    Section {
                        dateField
                    } header: {
                        sectionHeader("基本信息")
                    }

                    Section {
                        editableField("体重 (kg)", value: $report.weight, failed: report.failedFields.contains("weight"))
                        editableField("骨骼肌 (kg)", value: $report.skeletalMuscle, failed: report.failedFields.contains("skeletalMuscle"))
                        editableField("体脂肪 (kg)", value: $report.bodyFatMass, failed: report.failedFields.contains("bodyFatMass"))
                        editableField("身体水分 (kg)", value: $report.totalBodyWater, failed: report.failedFields.contains("totalBodyWater"))
                        editableField("去脂体重 (kg)", value: $report.leanBodyMass, failed: report.failedFields.contains("leanBodyMass"))
                    } header: {
                        sectionHeader("身体成分")
                    }

                    Section {
                        editableField("BMI", value: $report.bmi, failed: report.failedFields.contains("bmi"))
                        editableField("体脂率 (%)", value: $report.bodyFatPercent, failed: report.failedFields.contains("bodyFatPercent"))
                        editableField("腰臀比", value: $report.whr, failed: report.failedFields.contains("whr"))
                    } header: {
                        sectionHeader("肥胖分析")
                    }

                    Section {
                        editableIntField("InBody评分", value: $report.inbodyScore, failed: report.failedFields.contains("inbodyScore"))
                        editableIntField("内脏脂肪等级", value: $report.visceralFatLevel, failed: report.failedFields.contains("visceralFatLevel"))
                        editableField("基础代谢 (kcal)", value: $report.bmr, failed: report.failedFields.contains("bmr"))
                        editableField("每日所需热量 (kcal)", value: $report.dailyCalorie, failed: false)
                    } header: {
                        sectionHeader("综合指标")
                    }

                    Section {
                        editableField("左臂肌肉 (kg)", value: $report.segMuscleLeftArm, failed: false)
                        editableField("右臂肌肉 (kg)", value: $report.segMuscleRightArm, failed: false)
                        editableField("躯干肌肉 (kg)", value: $report.segMuscleTrunk, failed: false)
                        editableField("左腿肌肉 (kg)", value: $report.segMuscleLeftLeg, failed: false)
                        editableField("右腿肌肉 (kg)", value: $report.segMuscleRightLeg, failed: false)
                    } header: {
                        sectionHeader("节段肌肉")
                    }

                    Section {
                        editableField("左臂脂肪 (%)", value: $report.segFatLeftArm, failed: false)
                        editableField("右臂脂肪 (%)", value: $report.segFatRightArm, failed: false)
                        editableField("躯干脂肪 (%)", value: $report.segFatTrunk, failed: false)
                        editableField("左腿脂肪 (%)", value: $report.segFatLeftLeg, failed: false)
                        editableField("右腿脂肪 (%)", value: $report.segFatRightLeg, failed: false)
                    } header: {
                        sectionHeader("节段脂肪")
                    }
                }
                .padding(.horizontal)

                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        onSkip()
                    } label: {
                        Text("跳过")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onSave(report)
                    } label: {
                        Text("保存")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.appGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private var dateField: some View {
        HStack {
            Text("测量日期")
                .foregroundColor(.secondary)
            Spacer()
            DatePicker(
                "",
                selection: Binding(
                    get: { report.scanDate ?? Date() },
                    set: { report.scanDate = $0 }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
        }
        .font(.subheadline)
    }

    private func editableField(_ label: String, value: Binding<Double?>, failed: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundColor(failed ? .appOrange : .secondary)
                .font(.subheadline)
            Spacer()
            TextField("--", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(failed ? Color.appOrange.opacity(0.1) : Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func editableIntField(_ label: String, value: Binding<Int?>, failed: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundColor(failed ? .appOrange : .secondary)
                .font(.subheadline)
            Spacer()
            TextField("--", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(failed ? Color.appOrange.opacity(0.1) : Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
