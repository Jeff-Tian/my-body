import SwiftUI

extension Color {
    static let appGreen = Color(red: 46/255, green: 204/255, blue: 113/255)
    static let appGreenLight = Color(red: 46/255, green: 204/255, blue: 113/255).opacity(0.15)
    static let appOrange = Color(red: 243/255, green: 156/255, blue: 18/255)
    static let appRed = Color(red: 231/255, green: 76/255, blue: 60/255)
    static let appBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.systemBackground)
}

extension Double {
    var formatted1: String { String(format: "%.1f", self) }
    var formatted0: String { String(format: "%.0f", self) }
    var formatted2: String { String(format: "%.2f", self) }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

extension Date {
    var shortString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }

    var mediumString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: self)
    }
}
