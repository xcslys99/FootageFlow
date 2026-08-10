import Foundation

protocol MediaProvider: Sendable {
    var info: ProviderInfo { get }
    func search(_ request: SearchRequest) async throws -> [MediaAsset]
    func testConnection() async throws
}

extension MediaProvider {
    func testConnection() async throws {
        _ = try await search(SearchRequest(query: "bank", pageSize: 1))
    }
}

enum ProviderUtilities {
    static func cleanHTML(_ value: String?) -> String? {
        guard let value else { return nil }
        let replaced = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        let compact = replaced.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? nil : compact
    }

    static func licenseStatus(name: String?, url: String? = nil) -> LicenseStatus {
        let text = "\(name ?? "") \(url ?? "")".lowercased()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .unknown }
        if text.contains("public domain") || text.contains("creativecommons.org/publicdomain") || text.contains("cc0") { return .publicDomain }
        if text.contains("cc by") || text.contains("creativecommons.org/licenses/by") || text.contains("attribution") { return .attributionRequired }
        if text.contains("open government licence") || text.contains("ogl 3") || text.contains("ogl v3") { return .attributionRequired }
        if text.contains("all rights reserved") || text.contains("restricted") { return .restricted }
        if text.contains("pexels") || text.contains("pixabay content license") { return .safe }
        return .unknown
    }

    static func licenseName(name: String?, url: String?) -> String? {
        guard let raw = cleanHTML(name ?? url) else { return nil }
        guard raw.lowercased().hasPrefix("http") else { return raw }
        let text = raw.lowercased()
        if text.contains("publicdomain") || text.contains("/zero/") { return "Public Domain" }
        if text.contains("/by-sa/") { return "CC BY-SA" + versionSuffix(text) }
        if text.contains("/by-nd/") { return "CC BY-ND" + versionSuffix(text) }
        if text.contains("/by-nc/") { return "CC BY-NC" + versionSuffix(text) }
        if text.contains("/by/") { return "CC BY" + versionSuffix(text) }
        return raw
    }

    private static func versionSuffix(_ text: String) -> String {
        for version in ["4.0", "3.0", "2.5", "2.0", "1.0"] where text.contains("/\(version)/") { return " \(version)" }
        return ""
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        for format in ["yyyy-MM-dd", "yyyy", "yyyy-MM-dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    static func safeURL(_ string: String?) -> URL? {
        URLValidator.remote(string)
    }
}
