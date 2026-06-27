import SwiftUI

/// 日志查看视图，用户可以在 App 内查看、复制和清空日志。
struct LogView: View {
    @State private var viewModel = LoggerService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.count > 0 {
                    Text(viewModel.text)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("暂无日志")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("运行日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            copyLogs()
                        } label: {
                            Label("复制日志", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            viewModel.clear()
                        } label: {
                            Label("清空日志", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if viewModel.count > 0 {
                    Text("\(viewModel.count) 条")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appGreen, in: Capsule())
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func copyLogs() {
        UIPasteboard.general.string = viewModel.text
    }
}
