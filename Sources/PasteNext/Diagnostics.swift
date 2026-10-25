import Foundation

/// Append-only diagnostics log.
///
/// Capture and paste both make a series of judgement calls — which flavour the
/// image came from, whether the text survived, what actually reached the
/// pasteboard. When something goes wrong on a real machine those decisions are
/// invisible, so they are written here. The log lives outside the app container
/// so it can be read while the app is running, and it costs nothing when there
/// is nothing to report.
///
/// Location: `~/Library/Logs/PasteNext/pastenext.log`
enum Diagnostics {
    private static let url: URL? = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Logs/PasteNext", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pastenext.log")
    }()

    private static let queue = DispatchQueue(label: "com.pastenext.diagnostics")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Appends one line. `fields` is printed as `key=value` pairs so the log
    /// stays greppable.
    static func log(_ event: String, _ fields: [String: String] = [:]) {
        guard let url else { return }
        let body = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.replacingOccurrences(of: "\n", with: "\\n").prefix(200))" }
            .joined(separator: " ")
        let line = "\(formatter.string(from: Date())) \(event)\(body.isEmpty ? "" : " " + body)\n"
        queue.async {
            guard let handle = try? FileHandle(forWritingTo: url) else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
                return
            }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        }
    }

    /// Removes the log. Exposed so the self-test and the settings UI can offer a
    /// "clear diagnostics" action.
    static func clear() {
        guard let url else { return }
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }

    static var location: String { url?.path ?? "" }
}
