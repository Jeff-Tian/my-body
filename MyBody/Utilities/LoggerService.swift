import Foundation
import SwiftUI

/// 简单的应用日志服务，收集 print 输出供用户在 App 内查看。
@MainActor
@Observable
final class LoggerService {
    static let shared = LoggerService()

    private var entries: [LogEntry] = []
    private let maxEntries = 1000

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    private init() {}

    /// 添加一条日志。
    func log(_ message: String) {
        // 移除之前的换行符，避免产生空行
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        entries.append(LogEntry(timestamp: Date(), message: cleaned))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// 清空所有日志。
    func clear() {
        entries.removeAll()
    }

    /// 返回所有日志文本。
    var text: String {
        entries.map {
            "[\($0.timestamp.formatted(date: .abbreviated, time: .shortened))] \($0.message)"
        }.joined(separator: "\n")
    }

    var count: Int {
        entries.count
    }
}

// MARK: - Deprecated: Print redirection removed

// Swift 的 print 默认输出到 stdout，我们无法直接重定向到 LoggerService。
// 请在代码中直接使用 LoggerService.shared.log() 代替 print()。
