import AppKit
import ApplicationServices
import Foundation

/// Runtime permission checks.
///
/// Both permissions below gate real features, and neither has a public
/// "is granted" API, so each is probed with the cheapest reliable operation.
/// The results are surfaced in Settings instead of failing silently.
enum Permissions {
    /// Accessibility: required to deliver ⌘V to the target app.
    /// Probed directly — this one does have an API.
    static var accessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Full Disk Access: required to read files that live inside another app's
    /// container (WeChat's temp pictures, for instance), which is what makes a
    /// pasted file URL actually resolvable by the target app.
    ///
    /// There is no public API, so the probe reads the user's TCC database — a
    /// location only FDA can open.
    static var fullDiskAccess: Bool {
        let tcc = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let data = try? Data(contentsOf: tcc) else { return false }
        return !data.isEmpty
    }

    /// Deep link that opens the exact pane for a given permission.
    static func openSettings(for permission: Permission) {
        let url: URL
        switch permission {
        case .accessibility:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .fullDiskAccess:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        }
        NSWorkspace.shared.open(url)
    }

    enum Permission {
        case accessibility, fullDiskAccess
    }
}
