import SwiftUI
import Charts

struct MetricChartView: View {
    let data: [ChartDataPoint]
    let metric: MetricType
    var onPointTap: ((UUID) -> Void)? = nil

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
            // Single overlay gesture for tap-to-detail. This replaces the previous
            // per-point invisible Rectangle annotations, which created one interactive
            // accessibility node per data point and bloated the accessibility tree.
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let onPointTap else { return }
                            if let recordID = nearestRecordID(to: location, proxy: proxy, geo: geo) {
                                onPointTap(recordID)
                            }
                        }
                }
            }
            // Collapse the chart's internal accessibility tree into a single element.
            // Swift Charts otherwise exposes one accessibility node per mark/point/axis
            // label, which makes XCUITest's UI-query traversal extremely slow and causes
            // snapshot timeouts ("main thread busy" / "Timed out while evaluating UI query").
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(metric.rawValue)趋势图"))
        }
    }

    /// Finds the record whose plotted x-position is closest to the tap location.
    private func nearestRecordID(to location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> UUID? {
        let plotFrame: CGRect
        if let anchor = proxy.plotFrame {
            plotFrame = geo[anchor]
        } else {
            plotFrame = geo.frame(in: .local)
        }
        let xInPlot = location.x - plotFrame.origin.x
        guard let tappedDate: Date = proxy.value(atX: xInPlot) else { return nil }
        return data.min(by: {
            abs($0.date.timeIntervalSince(tappedDate)) < abs($1.date.timeIntervalSince(tappedDate))
        })?.recordID
    }
}
