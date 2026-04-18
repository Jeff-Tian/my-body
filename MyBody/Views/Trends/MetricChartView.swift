import SwiftUI
import Charts

struct MetricChartView: View {
    let data: [ChartDataPoint]
    let metric: MetricType

    var body: some View {
        if data.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.largeTitle)
                    .foregroundColor(.gray.opacity(0.4))
                Text("暂无数据")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                // Reference range band
                if let range = metric.referenceRange {
                    RectangleMark(
                        yStart: .value("Min", range.min),
                        yEnd: .value("Max", range.max)
                    )
                    .foregroundStyle(Color.appGreen.opacity(0.1))
                }

                // Data line
                ForEach(data) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value(metric.rawValue, point.value)
                    )
                    .foregroundStyle(Color.appGreen)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value(metric.rawValue, point.value)
                    )
                    .foregroundStyle(Color.appGreen)
                    .symbolSize(40)

                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value(metric.rawValue, point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appGreen.opacity(0.2), Color.appGreen.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.shortString)
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
    }
}
