#if DEBUG
import AppKit
import SwiftUI

/// A standalone copy of the About page used by the `--snapshot-about` debug
/// flag so the layout can be rendered without opening the settings window.
struct AboutSnapshotView: View {
    @ObservedObject var state: AppState
    let showDonation: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().aspectRatio(contentMode: .fit).frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
            Text("PasteNext").font(.system(size: 30, weight: .bold, design: .rounded))
            Text(L("版本 \(AppInfo.version) · 原生 macOS 剪贴板历史", "Version \(AppInfo.version) · Native macOS clipboard history"))
                .foregroundColor(.secondary)
            Divider().padding(.horizontal, 70)
            Text(L("轻量轮询 changeCount，仅在变化时读取内容。\n支持 macOS 通用剪贴板（接力），本地存储，无后台网络请求。",
                   "Lightweight changeCount polling; reads content only on change.\nUniversal Clipboard support, local storage, no background network requests."))
                .multilineTextAlignment(.center).font(.callout).foregroundColor(.secondary)
            HStack(spacing: 6) {
                Text(L("作者邮箱", "Author Email")).font(.caption).foregroundColor(.secondary)
                Text("xmilu0315@foxmail.com").font(.caption).textSelection(.enabled)
            }
            HStack(spacing: 5) {
                Image(systemName: "heart").font(.system(size: 10, weight: .semibold))
                Text(L("支持作者", "Support the Author")).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.09))
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
            Text("SwiftUI + AppKit · No third-party dependencies").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if showDonation {
                DonationPanelPreview()
                    .offset(y: 14)
            }
        }
    }
}

struct DonationPanelPreview: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                DonationQRPreview(named: "donate-wechat", title: L("微信收款码", "WeChat"))
                DonationQRPreview(named: "donate-alipay", title: L("支付宝收款码", "Alipay"))
            }
            Text(L("如果 PasteNext 帮到了你，欢迎请作者喝杯咖啡 ☕",
                   "If PasteNext is useful to you, consider buying the author a coffee ☕"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 260)
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

struct DonationQRPreview: View {
    let named: String
    let title: String
    var body: some View {
        VStack(spacing: 5) {
            if let image = NSImage(named: named) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
        }
    }
}
#endif
