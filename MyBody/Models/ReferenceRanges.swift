import Foundation

struct ReferenceRange {
    let min: Double
    let max: Double
    let unit: String

    func status(for value: Double) -> MetricStatus {
        if value < min { return .low }
        if value > max { return .high }
        return .normal
    }

    var displayRange: String {
        "\(formatNumber(min))–\(formatNumber(max)) \(unit)"
    }

    private func formatNumber(_ n: Double) -> String {
        n.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", n)
            : String(format: "%.1f", n)
    }
}

enum MetricStatus {
    case low, normal, high, excellent, warning, danger

    var label: String {
        switch self {
        case .low: return "偏低"
        case .normal: return "正常"
        case .high: return "偏高"
        case .excellent: return "优秀"
        case .warning: return "注意"
        case .danger: return "危险"
        }
    }

    var color: AppColor {
        switch self {
        case .low: return .statusOrange
        case .normal: return .primaryGreen
        case .high: return .statusRed
        case .excellent: return .primaryGreen
        case .warning: return .statusOrange
        case .danger: return .statusRed
        }
    }
}

enum AppColor {
    case primaryGreen
    case statusOrange
    case statusRed

    var swiftUIColor: SwiftUIColor {
        switch self {
        case .primaryGreen: return SwiftUIColor(red: 46/255, green: 204/255, blue: 113/255)
        case .statusOrange: return SwiftUIColor(red: 243/255, green: 156/255, blue: 18/255)
        case .statusRed: return SwiftUIColor(red: 231/255, green: 76/255, blue: 60/255)
        }
    }
}

import SwiftUI
typealias SwiftUIColor = Color

struct ReferenceRanges {
    static let weight = ReferenceRange(min: 53.4, max: 72.3, unit: "kg")
    static let skeletalMuscle = ReferenceRange(min: 26.8, max: 32.7, unit: "kg")
    static let bodyFatMass = ReferenceRange(min: 7.6, max: 15.1, unit: "kg")
    static let bmi = ReferenceRange(min: 18.5, max: 25.0, unit: "")
    static let bodyFatPercent = ReferenceRange(min: 10.0, max: 20.0, unit: "%")
    static let whr = ReferenceRange(min: 0.80, max: 0.90, unit: "")
    static let bmr = ReferenceRange(min: 1497, max: 1747, unit: "kcal")

    static func scoreStatus(_ score: Int) -> MetricStatus {
        if score >= 80 { return .excellent }
        if score >= 60 { return .normal }
        return .low
    }

    static func visceralFatStatus(_ level: Int) -> MetricStatus {
        if level <= 9 { return .normal }
        if level <= 14 { return .warning }
        return .danger
    }
}
