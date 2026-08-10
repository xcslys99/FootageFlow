import Foundation

actor AppLogger {
    static let shared = AppLogger()
    let logURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("FootageFinder/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("FootageFinder.log")
    }

    func write(provider: ProviderID?, requestType: String, status: Int? = nil, error: Error? = nil) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: .now)) provider=\(provider?.rawValue ?? "app") request=\(requestType) status=\(status.map(String.init) ?? "-") error=\(error.map { String(describing: type(of: $0)) } ?? "-")\n"
        let data = Data(line.utf8)
        if !FileManager.default.fileExists(atPath: logURL.path) { try? data.write(to: logURL, options: .atomic); return }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.close() } catch { try? handle.close() }
    }
}
