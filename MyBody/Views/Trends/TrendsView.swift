import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TrendsViewModel()

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
            .onAppear {
                viewModel.setup(context: modelContext)
                viewModel.fetchRecords()
            }
        }
    }
}
