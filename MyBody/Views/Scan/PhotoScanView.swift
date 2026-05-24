import SwiftUI
import SwiftData

struct PhotoScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ScanViewModel()

    // MARK: - 批量「重新识别」交互状态
    /// 批量结束后，若 `duplicateAssetIds.count > 0`，弹出确认 alert。
    @State private var showReparseDuplicatesConfirm = false
    /// reparse 期间显示全屏 overlay；同时屏蔽返回按钮。
    @State private var isReparsing = false
    /// 完成后展示的汇总文案（成功/失败条数）；非 nil 时显示顶部 banner。
    @State private var reparseSummary: ReparseSummary?

    fileprivate struct ReparseSummary {
        let succeeded: Int
        let failed: Int
        var hasFailures: Bool { failed > 0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if viewModel.showConfirmation {
                        ScanConfirmView(viewModel: viewModel) {
                            viewModel.showConfirmation = false
                            viewModel.currentParseIndex = 0
                            viewModel.isParsing = true   // 立即显示 loading，避免等 Task 调度时闪白
                            Task { await viewModel.parseNextPhoto() }
                        }
                    } else {
                        scanningView
                    }
                }
                if isReparsing {
                    reparsingOverlay
                }
            }
            .navigationTitle("导入报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.reset()
                        dismiss()
                    }
                    .disabled(isReparsing)
                }
            }
            .onAppear {
                viewModel.setup(context: modelContext)
                Task { await viewModel.startScan() }
            }
            .onChange(of: viewModel.batchFinished) { _, finished in
                guard finished else { return }
                if viewModel.duplicateAssetIds.isEmpty {
                    dismiss()
                } else {
                    showReparseDuplicatesConfirm = true
                }
            }
            .alert("重新识别已有报告？", isPresented: $showReparseDuplicatesConfirm) {
                Button("跳过", role: .cancel) {
                    dismiss()
                }
                Button("重新识别") {
                    Task { await runBatchReparse() }
                }
            } message: {
                Text("本次扫描发现 \(viewModel.duplicateAssetIds.count) 张报告之前已经导入过。是否用最新版本的识别引擎重新读取并覆盖这些报告的数值？\n\n（原始照片仍保留，只替换识别出的数值。）")
            }
            .overlay(alignment: .top) {
                if let summary = reparseSummary {
                    BatchReparseBanner(summary: summary)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - 批量「重新识别」overlay & action

    private var reparsingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.2)
                Text(reparseProgressText)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在重新识别已有报告")
    }

    /// 文案优先使用 ViewModel 暴露的索引；为 0 时退化为「重新识别中…」。
    private var reparseProgressText: String {
        let total = viewModel.reparseTotal
        let idx = viewModel.reparseIndex
        if total > 0 && idx > 0 {
            return "重新识别中 \(min(idx, total))/\(total)…"
        }
        return "重新识别中…"
    }

    private func runBatchReparse() async {
        isReparsing = true
        defer { isReparsing = false }

        let result = await viewModel.reparseDuplicateRecords()
        let summary = ReparseSummary(succeeded: result.succeeded, failed: result.failed)
        withAnimation { reparseSummary = summary }

        try? await Task.sleep(nanoseconds: 2_500_000_000)
        withAnimation { reparseSummary = nil }
        dismiss()
    }

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()

            if viewModel.isScanning {
                VStack(spacing: 12) {
                    Text("正在扫描相册...")
                        .font(.headline)

                    if viewModel.totalCount > 0 {
                        Text("共 \(viewModel.totalCount) 张照片")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ProgressView(value: viewModel.scanProgress)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 40)

                        HStack(spacing: 4) {
                            Text("\(viewModel.processedCount) / \(viewModel.totalCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(viewModel.scanProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !viewModel.stageMessage.isEmpty {
                            Text(viewModel.stageMessage)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                                .padding(.horizontal, 40)
                        }
                    } else {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(viewModel.stageMessage.isEmpty ? "正在准备..." : viewModel.stageMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if viewModel.scannedPhotos.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(.gray.opacity(0.4))
                Text("未在相册中找到 InBody 报告")
                    .foregroundColor(.secondary)

                Button {
                    Task { await viewModel.startScan() }
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.appGreen)
                        .clipShape(Capsule())
                }
            }

            if viewModel.isParsing {
                parsingView
            } else if !viewModel.isScanning && !viewModel.scannedPhotos.isEmpty {
                // 兜底：不扫描、有照片、又没在 parse（状态过渡或错误）—— 至少显示一个加载态
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在准备识别…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var parsingView: some View {
        let total = viewModel.selectedPhotos.count
        let current = min(viewModel.currentParseIndex + 1, max(total, 1))
        let progress = total > 0 ? Double(viewModel.currentParseIndex) / Double(total) : 0

        return VStack(spacing: 16) {
            // Thumbnail preview of the photo currently being OCR'd
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 180, height: 240)

                if let thumb = viewModel.currentThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.appGreen.opacity(0.6), lineWidth: 2)
                        )
                }

                // Shimmer / activity indicator overlay
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 180, height: 240)

                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.3)
                    Text("识别中")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }

            Text("正在识别第 \(current) / \(total) 张")
                .font(.headline)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.appGreen)
                .padding(.horizontal, 40)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)

            if !viewModel.parseStageMessage.isEmpty {
                Label(viewModel.parseStageMessage, systemImage: "waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 批量「重新识别」结果 banner

private struct BatchReparseBanner: View {
    let summary: PhotoScanView.ReparseSummary

    private var text: String {
        if summary.hasFailures {
            return "已更新 \(summary.succeeded) 条，\(summary.failed) 条失败"
        } else {
            return "已更新 \(summary.succeeded) 条"
        }
    }

    private var background: Color {
        summary.hasFailures ? .appOrange : .appGreen
    }

    private var icon: String {
        summary.hasFailures ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .fontWeight(.medium)
        }
        .font(.subheadline)
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(background, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .accessibilityLabel(text)
    }
}
