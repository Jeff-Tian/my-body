import SwiftUI

struct SettingsView: View {
    @AppStorage("iCloudPhotoDownload") private var iCloudPhotoDownload = false
    @AppStorage("scanRange") private var scanRange: String = ScanRange.last90Days.rawValue
    @AppStorage("syncWeightToHealth") private var syncWeightToHealth = false
    @State private var showingPrivacy = false
    @State private var showingWebsite = false
    @State private var healthAuthError: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

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

                Section {
                    Toggle("同步体重到「健康」", isOn: $syncWeightToHealth)
                        .onChange(of: syncWeightToHealth) { _, enabled in
                            guard enabled else { return }
                            Task {
                                do {
                                    try await HealthKitService.shared.requestAuthorization()
                                } catch {
                                    syncWeightToHealth = false
                                    healthAuthError = error.localizedDescription
                                }
                            }
                        }
                } header: {
                    Text("健康")
                } footer: {
                    Text("开启后，每次识别或编辑保存时，会把体重数据写入系统「健康」App。其他指标暂不同步。")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showingPrivacy = true
                    } label: {
                        HStack {
                            Text("隐私政策")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("openPrivacyButton")
                    .foregroundStyle(.primary)

                    Button {
                        showingWebsite = true
                    } label: {
                        HStack {
                            Text("访问官网")
                            Spacer()
                            Text("mybody.hardway.app")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("openWebsiteButton")
                    .foregroundStyle(.primary)
                } header: {
                    Text("关于")
                } footer: {
                    Text("身记不会上传任何健康数据，所有信息仅保存在你的设备上。")
                }
            }
            .navigationTitle("设置")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.appGreen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingPrivacy) {
                PrivacyView()
                    .ignoresSafeArea()
                    .accessibilityIdentifier("privacySheetRoot")
            }
            .sheet(isPresented: $showingWebsite) {
                PrivacyView(url: URL(string: PrivacyView.websiteURLString)!)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("websiteSheetRoot")
            }
            .alert("无法启用同步", isPresented: .init(
                get: { healthAuthError != nil },
                set: { if !$0 { healthAuthError = nil } }
            )) {
                Button("好的", role: .cancel) { healthAuthError = nil }
            } message: {
                Text(healthAuthError ?? "")
            }
        }
    }
}
