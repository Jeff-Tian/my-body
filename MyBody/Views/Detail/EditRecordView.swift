import SwiftUI
import SwiftData

struct EditRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: InBodyRecord

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    DatePicker("测量日期", selection: $record.scanDate, displayedComponents: .date)
                }

                Section("身体成分") {
                    optionalDouble("体重 (kg)", value: $record.weight)
                    optionalDouble("骨骼肌 (kg)", value: $record.skeletalMuscle)
                    optionalDouble("体脂肪 (kg)", value: $record.bodyFatMass)
                    optionalDouble("身体水分 (kg)", value: $record.totalBodyWater)
                    optionalDouble("去脂体重 (kg)", value: $record.leanBodyMass)
                }

                Section("肥胖分析") {
                    optionalDouble("BMI", value: $record.bmi)
                    optionalDouble("体脂率 (%)", value: $record.bodyFatPercent)
                    optionalDouble("腰臀比", value: $record.whr)
                }

                Section("综合指标") {
                    optionalInt("InBody评分", value: $record.inbodyScore)
                    optionalInt("内脏脂肪等级", value: $record.visceralFatLevel)
                    optionalDouble("基础代谢 (kcal)", value: $record.bmr)
                    optionalDouble("每日所需热量 (kcal)", value: $record.dailyCalorie)
                }

                Section("节段肌肉 (kg)") {
                    optionalDouble("左臂", value: $record.segMuscleLeftArm)
                    optionalDouble("右臂", value: $record.segMuscleRightArm)
                    optionalDouble("躯干", value: $record.segMuscleTrunk)
                    optionalDouble("左腿", value: $record.segMuscleLeftLeg)
                    optionalDouble("右腿", value: $record.segMuscleRightLeg)
                }

                Section("节段脂肪 (%)") {
                    optionalDouble("左臂", value: $record.segFatLeftArm)
                    optionalDouble("右臂", value: $record.segFatRightArm)
                    optionalDouble("躯干", value: $record.segFatTrunk)
                    optionalDouble("左腿", value: $record.segFatLeftLeg)
                    optionalDouble("右腿", value: $record.segFatRightLeg)
                }
            }
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func optionalDouble(_ label: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("--", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }

    private func optionalInt(_ label: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("--", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }
}
