import Foundation

enum URLValidationError: LocalizedError, Sendable {
    case missingURL
    case unsupportedScheme
    case missingHost
    case embeddedCredentials

    var errorDescription: String? {
        switch self {
        case .missingURL: tr("url.missing")
        case .unsupportedScheme: tr("url.unsupportedScheme")
        case .missingHost: tr("url.invalid")
        case .embeddedCredentials: tr("url.embeddedCredentials")
        }
    }
}

enum URLValidator {
    static func remote(_ url: URL?) throws -> URL {
        guard let url else { throw URLValidationError.missingURL }
        guard url.scheme?.lowercased() == "https" else { throw URLValidationError.unsupportedScheme }
        guard let host = url.host, !host.isEmpty else { throw URLValidationError.missingHost }
        guard url.user == nil, url.password == nil else { throw URLValidationError.embeddedCredentials }
        return url
    }

    static func remote(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value) else { return nil }
        return try? remote(url)
    }

    static func isSafeRemote(_ url: URL?) -> Bool {
        (try? remote(url)) != nil
    }
}
