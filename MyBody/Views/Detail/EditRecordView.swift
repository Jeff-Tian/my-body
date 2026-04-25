import SwiftUI
import SwiftData

struct EditRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: InBodyRecord
    @State private var showFullPhoto = false
    /// 打开页面时的字段快照，用于保存时与当前值 diff，把用户修改回灌给 `OCRCorrection`。
    @State private var initialSnapshot: [String: Double] = [:]

    var body: some View {
        NavigationStack {
            Form {
                if let data = record.photoData, let uiImage = UIImage(data: data) {
                    Section("原始照片") {
                        Button { showFullPhoto = true } label: {
                            HStack {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("查看原始照片")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text("点击放大以核对数值")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

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
                        recordCorrections()
                        try? modelContext.save()
                        syncWeightToHealthIfEnabled()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .fullScreenCover(isPresented: $showFullPhoto) {
                FullPhotoView(photoData: record.photoData)
            }
            .onAppear { captureSnapshot() }
        }
    }

    /// 把当前字段值冻结下来，供保存时 diff。
    private func captureSnapshot() {
        initialSnapshot = Self.currentValues(of: record)
    }

    /// 若用户在设置中开启了「同步体重到健康」，把当前体重写入 HealthKit。
    /// 失败静默忽略：用户体验上保存按钮应该总是能关闭页面，
    /// HealthKit 错误不应阻塞 SwiftData 持久化。
    private func syncWeightToHealthIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "syncWeightToHealth"),
              let weight = record.weight else { return }
        let date = record.scanDate
        Task.detached {
            try? await HealthKitService.shared.saveWeight(weight, date: date)
        }
    }

    /// 对比打开页面时的快照与当前值，为每个发生变化、且 OCR 有源头原始文本的字段
    /// 登记一条 `OCRCorrection`。
    private func recordCorrections() {
        let raw = record.ocrRawTexts
        guard !raw.isEmpty else { return }
        let store = OCRCorrectionStore(context: modelContext)
        let current = Self.currentValues(of: record)
        for (field, value) in current {
            guard let rawText = raw[field] else { continue }
            let before = initialSnapshot[field]
            // 只有当值真的变化时才登记，避免把未动字段误标为纠正
            if before == nil || abs((before ?? 0) - value) > 1e-6 {
                store.upsert(fieldName: field, rawText: rawText, correctedValue: value)
            }
        }
    }

    /// 把 `InBodyRecord` 里与 OCR 字段同名的当前值拍成 `[字段: 值]` 快照。
    /// 字段名必须与 `OCRService.parseBoxes` 里 `FieldSpec.name` 一致。
    private static func currentValues(of record: InBodyRecord) -> [String: Double] {
        var out: [String: Double] = [:]
        if let v = record.weight           { out["weight"]           = v }
        if let v = record.skeletalMuscle   { out["skeletalMuscle"]   = v }
        if let v = record.bodyFatMass      { out["bodyFatMass"]      = v }
        if let v = record.totalBodyWater   { out["totalBodyWater"]   = v }
        if let v = record.leanBodyMass     { out["leanBodyMass"]     = v }
        if let v = record.bmi              { out["bmi"]              = v }
        if let v = record.bodyFatPercent   { out["bodyFatPercent"]   = v }
        if let v = record.whr              { out["whr"]              = v }
        if let v = record.bmr              { out["bmr"]              = v }
        if let v = record.inbodyScore      { out["inbodyScore"]      = Double(v) }
        if let v = record.visceralFatLevel { out["visceralFatLevel"] = Double(v) }
        if let v = record.dailyCalorie     { out["dailyCalorie"]     = v }
        return out
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
