import SwiftUI
import PhotosUI
import SwiftData

/// 单张照片导入流程：跳过相册扫描与确认网格，
/// 直接把选中的照片送进 OCR/保存管道（复用 `ScanViewModel`）。
struct SinglePhotoImportView: View {
    let item: PhotosPickerItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ScanViewModel()
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                parsingView
                Spacer()
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
            .task {
                guard !didStart else { return }
                didStart = true
                viewModel.setup(context: modelContext)

                // Prefer the PHAsset fast path (preserves dedup-by-localIdentifier).
                // Fall back to raw Data only if the system did not surface an identifier
                // (e.g. limited library access or non-asset source).
                let identifier = item.itemIdentifier
                let data: Data? = await {
                    do {
                        return try await item.loadTransferable(type: Data.self)
                    } catch {
                        return nil
                    }
                }()

                await viewModel.startSingleImport(
                    itemIdentifier: identifier,
                    fallbackImageData: data
                )
            }
            .onChange(of: viewModel.batchFinished) { _, finished in
                if finished { dismiss() }
            }
        }
    }

    private var parsingView: some View {
        VStack(spacing: 16) {
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

            Text("正在识别选中的照片")
                .font(.headline)

            if !viewModel.parseStageMessage.isEmpty {
                Label(viewModel.parseStageMessage, systemImage: "waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
