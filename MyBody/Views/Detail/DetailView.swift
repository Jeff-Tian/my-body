import SwiftUI
import SwiftData

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let record: InBodyRecord
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var showFullPhoto = false
    // MARK: - 重新识别 (re-OCR with current parser)
    @State private var showReparseConfirm = false
    @State private var isReparsing = false
    @State private var reparseError: String?
    @State private var showReparseSuccess = false

    var body: some View {
        ZStack {
            scrollContent
            if isReparsing {
                reparsingOverlay
            }
        }
        .background(Color.appBackground)
        .navigationTitle("报告详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showReparseConfirm = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel("重新识别")
                .disabled(record.photoAssetIdentifier == nil || isReparsing)
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
                .disabled(isReparsing)
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .disabled(isReparsing)
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
        // TODO(Ash): 当 InBodyRecord 增加 `hasManualEdits` 标记后，
        // 在这里根据该标记替换为更强的警告文案（例如列出被覆盖的字段）。
        .alert("重新识别这张报告？", isPresented: $showReparseConfirm) {
            Button("取消", role: .cancel) {}
            Button("重新识别") {
                Task { await reparse() }
            }
        } message: {
            Text("将用最新版本的识别引擎重新读取原始照片。原始照片仍保留，仅替换识别出的数值。")
        }
        .alert("识别失败", isPresented: Binding(
            get: { reparseError != nil },
            set: { if !$0 { reparseError = nil } }
        )) {
            Button("好", role: .cancel) { reparseError = nil }
        } message: {
            Text(reparseError ?? "")
        }
        .overlay(alignment: .top) {
            if showReparseSuccess {
                ReparseSuccessBanner()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditRecordView(record: record)
        }
        .fullScreenCover(isPresented: $showFullPhoto) {
            FullPhotoView(photoData: record.photoData)
        }
    }

    private var scrollContent: some View {
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
    }

    // MARK: - 重新识别 overlay & action

    private var reparsingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text("重新识别中…")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
    }

    private func reparse() async {
        guard record.photoAssetIdentifier != nil else { return }
        isReparsing = true
        defer { isReparsing = false }
        do {
            _ = try await ScanViewModel.reparseExistingReport(record, context: modelContext, ocrService: OCRService())
            withAnimation { showReparseSuccess = true }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { showReparseSuccess = false }
        } catch {
            reparseError = friendlyReparseError(error)
        }
    }

    private func friendlyReparseError(_ error: Error) -> String {
        // `ScanViewModel.ReparseError` 已实现 LocalizedError，直接使用。
        if let reparseErr = error as? ScanViewModel.ReparseError,
           let desc = reparseErr.errorDescription {
            return desc
        }
        let nsErr = error as NSError
        if nsErr.domain.contains("Photos") || nsErr.localizedDescription.lowercased().contains("asset") {
            return "无法访问原始照片，可能已被删除或权限被撤销。"
        }
        return "识别失败：\(error.localizedDescription)"
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
                ZoomablePhoto(uiImage: uiImage)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
            }
            .accessibilityLabel("关闭")
        }
    }
}

/// 支持双指捏合缩放、双击切换、放大后拖动平移（带边界约束）的图片查看器。
private struct ZoomablePhoto: View {
    let uiImage: UIImage

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    private let doubleTapScale: CGFloat = 2.5

    // 已提交的状态（手势结束后落定）
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    // 手势进行中的增量
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let fitted = fittedSize(in: containerSize)
            let effectiveScale = scale * gestureScale
            // 拖动中的原始偏移（未 clamp，给实时跟手）；松手时再 clamp
            let liveOffset = CGSize(
                width: offset.width + gestureOffset.width,
                height: offset.height + gestureOffset.height
            )

            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: containerSize.width, height: containerSize.height)
                .scaleEffect(effectiveScale)
                .offset(liveOffset)
                .gesture(
                    MagnificationGesture()
                        .updating($gestureScale) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            // 松手瞬间的 effectiveScale = scale * value。
                            // 先无动画把 scale 接管这个连续值：gestureScale 会瞬间回弹到 1.0，
                            // 若用 withAnimation 提交 scale，effectiveScale 会先掉回 1x 再动画放大 —— 就是闪烁来源。
                            let newScale = scale * value
                            scale = newScale
                            let clamped = min(max(newScale, minScale), maxScale)
                            if clamped != newScale {
                                // 越界：用动画把 scale 回弹修正到合法范围，并相应处理 offset。
                                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = clamped
                                    if scale <= minScale {
                                        offset = .zero
                                    } else {
                                        offset = clampedOffset(offset, scale: scale, fitted: fitted, container: containerSize)
                                    }
                                }
                            } else {
                                // 合法范围内：scale 已连续落定，仅平滑 clamp 因放大变化的平移边界。
                                let target = clampedOffset(offset, scale: scale, fitted: fitted, container: containerSize)
                                if target != offset {
                                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                                        offset = target
                                    }
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .updating($gestureOffset) { value, state, _ in
                            // 仅在已放大时允许平移
                            if scale > minScale {
                                state = value.translation
                            }
                        }
                        .onEnded { value in
                            guard scale > minScale else { return }
                            let proposed = CGSize(
                                width: offset.width + value.translation.width,
                                height: offset.height + value.translation.height
                            )
                            // 同理：gestureOffset 在 onEnded 瞬间回弹到 .zero。
                            // 先无动画把 offset 落定到跟手位置（接管回弹，liveOffset 保持连续，消除松手跳动），
                            // 再仅在越界时用动画 clamp 到边界。
                            offset = proposed
                            let clamped = clampedOffset(proposed, scale: scale, fitted: fitted, container: containerSize)
                            if clamped != proposed {
                                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.85)) {
                                    offset = clamped
                                }
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if scale > minScale {
                            scale = minScale
                            offset = .zero
                        } else {
                            scale = doubleTapScale
                            offset = .zero
                        }
                    }
                }
                .accessibilityLabel("报告照片")
                .accessibilityHint("双指捏合缩放，双击放大或还原")
        }
    }

    /// 在容器内按 .fit 计算图片实际显示尺寸（缩放前）。
    private func fittedSize(in container: CGSize) -> CGSize {
        guard uiImage.size.width > 0, uiImage.size.height > 0,
              container.width > 0, container.height > 0 else {
            return container
        }
        let imageAspect = uiImage.size.width / uiImage.size.height
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            // 受宽度约束
            let w = container.width
            return CGSize(width: w, height: w / imageAspect)
        } else {
            // 受高度约束
            let h = container.height
            return CGSize(width: h * imageAspect, height: h)
        }
    }

    /// 根据当前缩放后的图片尺寸与容器尺寸，约束平移偏移，避免图片被拖出可视区域。
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat, fitted: CGSize, container: CGSize) -> CGSize {
        let scaledWidth = fitted.width * scale
        let scaledHeight = fitted.height * scale
        let maxX = max(0, (scaledWidth - container.width) / 2)
        let maxY = max(0, (scaledHeight - container.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

// MARK: - 重新识别成功提示

private struct ReparseSuccessBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text("已更新")
                .fontWeight(.medium)
        }
        .font(.subheadline)
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appGreen, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .accessibilityLabel("识别完成，已更新")
    }
}