import SwiftUI
import SwiftData

struct PhotoScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ScanViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.showParseResult, let report = viewModel.parsedReport {
                    ParseConfirmView(
                        report: report,
                        image: viewModel.currentImage,
                        onSave: { updatedReport in
                            viewModel.saveCurrentRecord(report: updatedReport)
                            if viewModel.currentParseIndex >= viewModel.selectedPhotos.count {
                                dismiss()
                            } else {
                                Task { await viewModel.parseNextPhoto() }
                            }
                        },
                        onSkip: {
                            viewModel.skipCurrentPhoto()
                            if viewModel.currentParseIndex >= viewModel.selectedPhotos.count {
                                dismiss()
                            } else {
                                Task { await viewModel.parseNextPhoto() }
                            }
                        }
                    )
                } else if viewModel.showConfirmation {
                    ScanConfirmView(viewModel: viewModel) {
                        viewModel.showConfirmation = false
                        viewModel.currentParseIndex = 0
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
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在识别报告...")
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }
}
