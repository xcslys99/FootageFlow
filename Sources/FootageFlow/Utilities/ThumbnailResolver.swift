import Foundation

/// Normalizes provider thumbnail metadata before it reaches either desktop UI.
/// Relative PeerTube paths are always resolved against the video's own instance.
enum ThumbnailResolver {
  static func candidates(
    provider: ProviderID,
    rawValues: [String?],
    originalPageURL: URL?,
    providerOriginURL: URL? = nil,
    instanceURL: URL? = nil,
    metadata: [String: String] = [:]
  ) -> [URL] {
    let metadataInstance =
      origin(from: URLValidator.remote(metadata["instanceURL"]))
      ?? origin(fromHost: metadata["instanceHost"] ?? metadata["host"])
    let pageOrigin = origin(from: originalPageURL)
    let preferredBase =
      provider == .peertube
      ? (origin(from: instanceURL) ?? metadataInstance ?? pageOrigin)
      : (origin(from: providerOriginURL) ?? pageOrigin ?? metadataInstance)

    var output: [URL] = []
    var seen = Set<String>()
    for raw in rawValues.compactMap({ $0 }) {
      guard let resolved = resolve(raw, relativeTo: preferredBase) else { continue }
      let key = resolved.absoluteString
      if seen.insert(key).inserted { output.append(resolved) }
    }
    return output
  }

  static func resolve(_ rawValue: String?, relativeTo baseURL: URL?) -> URL? {
    guard
      var value = rawValue?
        .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    value = decodeHTMLEntities(value)
    if value.hasPrefix("//") { value = "https:\(value)" }

    let parsed = parse(value, relativeTo: baseURL)
    guard var components = parsed.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: true) })
    else { return nil }
    if components.scheme?.lowercased() == "http" { components.scheme = "https" }
    guard components.scheme?.lowercased() == "https",
      let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty,
      components.user == nil, components.password == nil
    else { return nil }
    components.host = host.lowercased()
    return components.url.flatMap { try? URLValidator.remote($0.absoluteURL) }
  }

  static func origin(from value: URL?) -> URL? {
    guard let value, var components = URLComponents(url: value, resolvingAgainstBaseURL: true),
      let host = components.host, !host.isEmpty
    else { return nil }
    components.scheme = "https"
    components.user = nil
    components.password = nil
    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.url.flatMap { try? URLValidator.remote($0) }
  }

  static func origin(fromHost value: String?) -> URL? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    if value.contains("://") { return origin(from: URLValidator.remote(value)) }
    return origin(from: URLValidator.remote("https://\(value)"))
  }

  private static func parse(_ value: String, relativeTo baseURL: URL?) -> URL? {
    if let direct = URL(string: value, relativeTo: baseURL)?.absoluteURL { return direct }
    var allowed = CharacterSet.urlPathAllowed
    allowed.formUnion(.urlQueryAllowed)
    allowed.formUnion(.urlHostAllowed)
    guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
      return nil
    }
    return URL(string: encoded, relativeTo: baseURL)?.absoluteURL
  }

  private static func decodeHTMLEntities(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&#38;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
  }
}

enum ThumbnailImageFormat: String, Codable, Sendable {
  case jpeg, png, webp, avif, gif

  static func detect(data: Data, contentType: String?) -> ThumbnailImageFormat? {
    let bytes = [UInt8](data.prefix(32))
    if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
    if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
    if bytes.count >= 6, String(bytes: bytes[0..<6], encoding: .ascii)?.hasPrefix("GIF8") == true {
      return .gif
    }
    if bytes.count >= 12,
      String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
      String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP"
    {
      return .webp
    }
    if bytes.count >= 12, String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
      let brand = String(bytes: bytes[8..<min(bytes.count, 24)], encoding: .ascii) ?? ""
      if brand.contains("avif") || brand.contains("avis") { return .avif }
    }
    let normalized = contentType?.split(separator: ";").first?.lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return switch normalized {
    case "image/jpeg", "image/jpg": .jpeg
    case "image/png": .png
    case "image/webp": .webp
    case "image/avif": .avif
    case "image/gif": .gif
    default: nil
    }
  }
}

enum ThumbnailResponseValidator {
  static let maximumBytes = 20 * 1_024 * 1_024

  static func validate(status: Int, contentType: String?, data: Data) -> ThumbnailImageFormat? {
    guard (200..<300).contains(status), !data.isEmpty, data.count <= maximumBytes else {
      return nil
    }
    let normalized = contentType?.lowercased() ?? ""
    guard !normalized.contains("text/html"), !normalized.contains("application/json") else {
      return nil
    }
    return ThumbnailImageFormat.detect(data: data, contentType: contentType)
  }
}
