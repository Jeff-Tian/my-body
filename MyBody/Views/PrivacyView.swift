import SwiftUI
import SafariServices

/// 用 `SFSafariViewController` 包装的 SwiftUI 视图，用于在 App 内打开外部网页。
///
/// 默认打开隐私政策。也可以传入任意 URL 用来打开官网或其它说明页面，
/// 这样 App Store Connect 与 App 内就可以共用同一套 marketing 页面，
/// 避免双份维护。
struct PrivacyView: UIViewControllerRepresentable {
    static let privacyURLString = "https://mybody.hardway.app/privacy/"
    static let websiteURLString = "https://mybody.hardway.app/"

    let url: URL

    init(url: URL = URL(string: PrivacyView.privacyURLString)!) {
        self.url = url
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}
