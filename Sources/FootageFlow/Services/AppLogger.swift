import Foundation

actor AppLogger {
    static let shared = AppLogger()
    let logURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("FootageFlow/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("FootageFlow.log")
    }

    func write(provider: ProviderID?, requestType: String, status: Int? = nil, error: Error? = nil, detail: String? = nil) {
        let formatter = ISO8601DateFormatter()
        let safeDetail = detail.map(Self.redact) ?? "-"
        let line = "\(formatter.string(from: .now)) provider=\(provider?.rawValue ?? "app") request=\(Self.redact(requestType)) status=\(status.map(String.init) ?? "-") error=\(error.map { String(describing: type(of: $0)) } ?? "-") detail=\(safeDetail)\n"
        let data = Data(line.utf8)
        if !FileManager.default.fileExists(atPath: logURL.path) { try? data.write(to: logURL, options: .atomic); return }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.close() } catch { try? handle.close() }
    }

    static func redact(_ value: String) -> String {
        var output = String(value.prefix(1_000))
        let patterns = [
            "(?i)(authorization|cookie|password|token|api[_ -]?key)\\s*[:=]\\s*(bearer\\s+)?[^\\s,;]+",
            "(?i)bearer\\s+[A-Za-z0-9._~+/-]+",
            "AIza[0-9A-Za-z_-]{20,}",
            "sk-[A-Za-z0-9_-]{20,}"
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        return output.replacingOccurrences(of: "[\\r\\n]+", with: " ", options: .regularExpression)
    }
}
