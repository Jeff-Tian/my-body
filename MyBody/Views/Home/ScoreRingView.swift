import SwiftUI

struct ScoreRingView: View {
    let score: Int?
    let size: CGFloat

    private var progress: Double {
        guard let score else { return 0 }
        return Double(score) / 100.0
    }

    private var ringColor: Color {
        guard let score else { return .gray }
        if score >= 80 { return .appGreen }
        if score >= 60 { return .appOrange }
        return .appRed
    }

    private var statusText: String {
        guard let score else { return "暂无" }
        if score >= 80 { return "优秀" }
        if score >= 60 { return "正常" }
        return "偏低"
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: size * 0.08)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(
                        lineWidth: size * 0.08,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.0), value: progress)

            // Center text
            VStack(spacing: 4) {
                if let score {
                    Text("\(score)")
                        .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                        .foregroundColor(ringColor)
                } else {
                    Text("--")
                        .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                        .foregroundColor(.gray)
                }
                Text(statusText)
                    .font(.system(size: size * 0.1))
                    .foregroundColor(.secondary)
                Text("InBody 评分")
                    .font(.system(size: size * 0.08))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
