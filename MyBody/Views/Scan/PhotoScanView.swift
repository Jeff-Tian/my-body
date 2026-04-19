import SwiftUI
import SwiftData

struct PhotoScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ScanViewModel()

    var body: some View {
        NavigationStack {
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
            .navigationTitle("导入报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.reset()
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.setup(context: modelContext)
                Task { await viewModel.startScan() }
            }
            .onChange(of: viewModel.batchFinished) { _, finished in
                if finished { dismiss() }
            }
        }
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
