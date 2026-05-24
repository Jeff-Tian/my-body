import SwiftUI
import SwiftData
import PhotosUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()
    @State private var showImport = false
    @State private var showSinglePicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var showSingleImport = false

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
                        showImport = true
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
            .sheet(isPresented: $showImport) {
                viewModel.fetchRecords()
            } content: {
                PhotoScanView()
            }
            .photosPicker(
                isPresented: $showSinglePicker,
                selection: $pickedItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: pickedItem) { _, newItem in
                if newItem != nil {
                    showSingleImport = true
                }
            }
            .sheet(isPresented: $showSingleImport) {
                pickedItem = nil
                viewModel.fetchRecords()
            } content: {
                if let item = pickedItem {
                    SinglePhotoImportView(item: item)
                }
            }
        }
    }
}
