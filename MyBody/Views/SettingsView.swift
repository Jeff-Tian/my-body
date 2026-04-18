import SwiftUI

struct SettingsView: View {
    @AppStorage("iCloudPhotoDownload") private var iCloudPhotoDownload = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("扫描 iCloud 照片", isOn: $iCloudPhotoDownload)
                } header: {
                    Text("相册扫描")
                } footer: {
                    Text("开启后扫描时会自动下载 iCloud 中未缓存的照片进行识别，可能较慢且消耗流量。关闭则仅扫描本地已缓存的照片。")
                }
            }
            .navigationTitle("设置")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.appGreen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
