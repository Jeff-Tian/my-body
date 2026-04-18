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
                ProgressView(value: viewModel.scanProgress) {
                    Text("正在扫描相册...")
                        .font(.headline)
                }
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)

                Text("\(Int(viewModel.scanProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
