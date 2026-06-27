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
    @State private var showSinglePhotoImport = false  // 单张照片导入专用
    @State private var singlePhotoAsset: PHAsset?  // 单张照片导入的 PHAsset

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
                if let newItem, let id = newItem.itemIdentifier {
                    let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                    if let asset = fetch.firstObject {
                        singlePhotoAsset = asset
                        LoggerService.shared.log("[HomeView.onChange] singlePhotoAsset set to \(asset.localIdentifier), opening single photo import")
                        showSinglePhotoImport = true
                    }
                } else {
                    LoggerService.shared.log("[HomeView.onChange] pickedItem is nil, clearing singlePhotoAsset")
                    singlePhotoAsset = nil
                }
            }
            .fullScreenCover(isPresented: $showSinglePhotoImport) {
                OnAppearBlock {
                    viewModel.fetchRecords()
                }
                PhotoScanView(preloadedAsset: singlePhotoAsset)
                    .onDisappear {
                        singlePhotoAsset = nil
                    }
            }
            .fullScreenCover(isPresented: $showImportSheet) {
                OnAppearBlock {
                    viewModel.fetchRecords()
                }
                PhotoScanView(preloadedAsset: importAsset)
                    .onDisappear {
                        importAsset = nil
                    }
            }
        }
    }
}

// MARK: - Helpers

/// A zero-size view that runs a side-effect on appear.
/// Used to run non-View-returning code inside a SwiftUI view builder.
private struct OnAppearBlock: View {
    let action: () -> Void
    var body: some View {
        Color.clear.onAppear(perform: action)
    }
}
