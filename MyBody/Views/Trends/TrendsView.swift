import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TrendsViewModel()
    @State private var writeController: WeightHealthWriteController?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Metric picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MetricType.allCases) { metric in
                                Button {
                                    viewModel.selectedMetric = metric
                                } label: {
                                    Text(metric.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(viewModel.selectedMetric == metric ? .bold : .regular)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            viewModel.selectedMetric == metric
                                            ? Color.appGreen
                                            : Color.gray.opacity(0.1)
                                        )
                                        .foregroundColor(
                                            viewModel.selectedMetric == metric
                                            ? .white
                                            : .primary
                                        )
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Time filter
                    Picker("时间范围", selection: $viewModel.timeFilter) {
                        ForEach(TimeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Chart
                    MetricChartView(
                        data: viewModel.chartData,
                        metric: viewModel.selectedMetric
                    )
                    .frame(height: 250)
                    .cardStyle()
                    .padding(.horizontal)

                    // Insight
                    Text(viewModel.insightText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // History list
                    HistoryListView(records: viewModel.filteredRecords) {
                        viewModel.fetchRecords()
                    }
                }
                .padding(.vertical)
            }
            .background(Color.appBackground)
            .navigationTitle("趋势")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.appGreen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if viewModel.selectedMetric == .weight,
                   HealthKitService.shared.isAvailable,
                   let controller = writeController {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            controller.userTappedToolbarButton()
                        } label: {
                            Image(systemName: "heart.text.square")
                        }
                        .disabled(controller.isWriting)
                        .accessibilityLabel(Text("写入健康"))
                        .accessibilityHint(Text("将体重历史写入「健康」App"))
                    }
                }
            }
            .onAppear {
                viewModel.setup(context: modelContext)
                viewModel.fetchRecords()
                if writeController == nil {
                    writeController = WeightHealthWriteController { range in
                        switch range {
                        case .allHistory:
                            return viewModel.records
                        case .currentChart:
                            return viewModel.filteredRecords
                        case .last30Days:
                            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                            return viewModel.records.filter { $0.scanDate >= cutoff }
                        }
                    }
                }
            }
            .modifier(WeightHealthWriteOverlay(controller: $writeController))
        }
    }
}

// MARK: - Write flow overlays

/// Glues confirmationDialog / progress overlay / result alert / error alert onto the
/// host view. Lives in a modifier so `TrendsView` body stays scannable.
private struct WeightHealthWriteOverlay: ViewModifier {
    @Binding var controller: WeightHealthWriteController?

    func body(content: Content) -> some View {
        Group {
            if let ctrl = controller {
                content
                    .confirmationDialog(
                        Text("选择范围"),
                        isPresented: Binding(
                            get: { ctrl.showRangeDialog },
                            set: { ctrl.showRangeDialog = $0 }
                        ),
                        titleVisibility: .visible
                    ) {
                        ForEach(WeightHealthWriteController.Range.allCases) { range in
                            Button(range.localizedTitle) { ctrl.userPickedRange(range) }
                        }
                        Button("取消", role: .cancel) { }
                    }
                    .overlay {
                        if ctrl.isWriting {
                            WritingProgressOverlay()
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(Text("正在写入..."))
                        }
                    }
                    .alert(
                        Text("写入完成"),
                        isPresented: Binding(
                            get: { ctrl.showResultAlert },
                            set: { ctrl.showResultAlert = $0 }
                        ),
                        presenting: ctrl.resultForDisplay
                    ) { result in
                        if !result.failed.isEmpty {
                            Button("查看失败详情") { ctrl.showFailedDetails = true }
                        }
                        Button("好") { }
                    } message: { result in
                        Text(resultSummary(result))
                    }
                    .sheet(isPresented: Binding(
                        get: { ctrl.showFailedDetails },
                        set: { ctrl.showFailedDetails = $0 }
                    )) {
                        if case .result(let r) = ctrl.phase {
                            FailedRecordsSheet(failed: r.failed)
                        }
                    }
                    .alert(
                        Text("需要健康权限"),
                        isPresented: Binding(
                            get: { ctrl.showErrorAlert },
                            set: { ctrl.showErrorAlert = $0 }
                        ),
                        presenting: errorPayload(ctrl.phase)
                    ) { payload in
                        if payload.isAuthDenied {
                            Button("打开设置") { openSystemSettings() }
                        }
                        Button("好", role: .cancel) { }
                    } message: { payload in
                        Text(payload.message)
                    }
            } else {
                content
            }
        }
    }

    private func resultSummary(_ r: HealthKitWriteResult) -> String {
        var lines: [String] = []
        lines.append(String.localizedStringWithFormat(
            NSLocalizedString("已写入 %lld 条", comment: ""), Int64(r.written)
        ))
        if r.skippedDuplicate > 0 {
            lines.append(String.localizedStringWithFormat(
                NSLocalizedString("已跳过 %lld 条 (重复)", comment: ""), Int64(r.skippedDuplicate)
            ))
        }
        if r.skippedInvalid > 0 {
            lines.append(String.localizedStringWithFormat(
                NSLocalizedString("已跳过 %lld 条 (无效)", comment: ""), Int64(r.skippedInvalid)
            ))
        }
        if !r.failed.isEmpty {
            lines.append(String.localizedStringWithFormat(
                NSLocalizedString("失败 %lld 条", comment: ""), Int64(r.failed.count)
            ))
        }
        return lines.joined(separator: "\n")
    }

    private struct ErrorPayload: Identifiable {
        let id = UUID()
        let message: String
        let isAuthDenied: Bool
    }

    private func errorPayload(_ phase: WeightHealthWriteController.Phase) -> ErrorPayload? {
        if case .error(let message, let isAuthDenied) = phase {
            return ErrorPayload(message: message, isAuthDenied: isAuthDenied)
        }
        return nil
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct WritingProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                Text("正在写入...")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct FailedRecordsSheet: View {
    let failed: [(recordID: UUID, error: Error)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(failed, id: \.recordID) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.recordID.uuidString)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        Text(entry.error.localizedDescription)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("失败详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
