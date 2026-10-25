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
    /// There is no public API, so several FDA-protected locations are probed in
    /// turn — a real read, not a stat, because TCC denial happens at open time.
    /// The user-level TCC database alone proved unreliable: it can be missing,
    /// and it is not the only thing FDA unlocks.
    static var fullDiskAccess: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes: [URL] = [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            home.appendingPathComponent("Library/Mail"),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        ]
        for url in probes {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path),
                   !contents.isEmpty {
                    return true
                }
                continue
            }
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return true
            }
        }
        return false
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
