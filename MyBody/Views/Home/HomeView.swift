import SwiftUI
import SwiftData
import PhotosUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()
    @State private var showImport = false
    @State private var showSinglePicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedPHAsset: PHAsset?
    @State private var importAsset: PHAsset?  // 用于 fullScreenCover 的预加载资产
    @State private var showImportSheet = false  // 控制 fullScreenCover 显示
    @State private var showSinglePhotoImport = false  // 驱动 fullScreenCover(isPresented:)，每次选择都触发
    @State private var singlePhotoItem: SinglePhotoItem?  // 单张照片导入的 PHAsset（包装为 Identifiable 以驱动 fullScreenCover(item:)）

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Score Ring
                        ScoreRingView(
                            score: viewModel.latestRecord?.inbodyScore,
                            size: 200
                        )
                        .padding(.top, 8)

                        if let record = viewModel.latestRecord {
                            Text("最近测量: \(record.formattedDate)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Body Composition
                        BodyCompositionCard(items: viewModel.bodyCompositionItems)

                        // Obesity Analysis
                        ObesityAnalysisCard(items: viewModel.obesityItems)

                        // Segmental Diagram
                        SegmentalDiagramView(record: viewModel.latestRecord)

                        // Risk Indicators
                        RiskIndicatorCard(items: viewModel.riskItems)

                        DisclaimerFooter()
                    }
                    .padding()
                }
                .background(Color.appBackground)

                // FAB
                Menu {
                    Button {
                        importAsset = nil  // 批量扫描：无预加载资产
                        showImportSheet = true
                    } label: {
                        Label("扫描相册", systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        showSinglePicker = true
                    } label: {
                        Label("选择单张照片", systemImage: "photo")
                    }
                } label: {
                    Label("导入报告", systemImage: "plus")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.appGreen)
                        .clipShape(Capsule())
                        .shadow(color: .appGreen.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .padding(20)
            }
            .navigationTitle("身记")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.appGreen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                viewModel.setup(context: modelContext)
            }
            .photosPicker(
                isPresented: $showSinglePicker,
                selection: $pickedItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: pickedItem) { _, newItem in
                LoggerService.shared.log("[HomeView.onChange] pickedItem changed")
                guard let newItem, let id = newItem.itemIdentifier else {
                    LoggerService.shared.log("[HomeView.onChange] pickedItem is nil, ignoring (user cancelled)")
                    return
                }
                let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                if let asset = fetch.firstObject {
                    LoggerService.shared.log("[HomeView.onChange] singlePhotoItem set to \(asset.localIdentifier), opening single photo import")
                    singlePhotoItem = SinglePhotoItem(asset: asset)
                    showSinglePhotoImport = true  // 每次选择都手动触发打开
                }
            }
            .fullScreenCover(item: $singlePhotoItem) { item in
                // 注意：cover 内容必须是单一根视图。之前在 PhotoScanView 旁边放了一个
                // OnAppearBlock 兄弟视图，导致 HomeView 因 SwiftData 变更重渲染时，
                // ViewBuilder 的 TupleView 子节点被重新识别，从而把 PhotoScanView 连同
                // 它的 @State viewModel 一起重建（batchFinished 被重置为 false），
                // 表现为「重新识别」后弹窗被关闭、照片未移动。这里改为单一根视图，
                // 并把 fetchRecords 放到关闭时（onDisappear）执行。
                PhotoScanView(preloadedAsset: item.asset)
                    // 用稳定的 asset id 固定视图身份，避免 HomeView body 重新求值时
                    // SwiftUI 丢失 PhotoScanView 的 @State（包括 viewModel、弹窗布尔值），
                    // 否则「移动并退出」后弹窗不消失、scannedPhotos 被重置导致相册为空。
                    .id(item.id)
                    .onDisappear {
                        viewModel.fetchRecords()
                        // 关闭时先重置布尔值，再延迟重置 pickedItem
                        // 延迟重置确保下次选择同一张照片时 onChange 能正常触发
                        singlePhotoItem = nil
                        // 延迟到下一个 runloop 再重置 pickedItem，避免与当前关闭流程冲突
                        Task {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 秒
                            pickedItem = nil
                        }
                    }
            }
            .fullScreenCover(isPresented: $showImportSheet) {
                PhotoScanView(preloadedAsset: importAsset)
                    .onDisappear {
                        viewModel.fetchRecords()
                        importAsset = nil
                    }
            }
        }
    }
}

// MARK: - Helpers

/// 包装单张导入的 PHAsset 为 Identifiable，用于驱动 `fullScreenCover(item:)`，
/// 保证打开 cover 时 asset 一定非 nil（避免落入全相册扫描分支）。
private struct SinglePhotoItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}
