import SwiftUI

struct SettingsView: View {
    @AppStorage("iCloudPhotoDownload") private var iCloudPhotoDownload = false
    @AppStorage("scanRange") private var scanRange: String = ScanRange.last90Days.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("扫描范围", selection: $scanRange) {
                        ForEach(ScanRange.allCases) { range in
                            Text(range.label).tag(range.rawValue)
                        }
                    }
                    Toggle("扫描 iCloud 照片", isOn: $iCloudPhotoDownload)
                } header: {
                    Text("相册扫描")
                } footer: {
                    Text("扫描范围越小，速度越快。开启 iCloud 扫描会自动下载未缓存的照片进行识别，可能较慢且消耗流量。")
                }
            }
            .navigationTitle("设置")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.appGreen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
