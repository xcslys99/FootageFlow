import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case pexels, pixabay, wikimedia, internetArchive, youtube

    var id: String { rawValue }
    var displayName: String {
        return switch self {
        case .pexels: "Pexels"
        case .pixabay: "Pixabay"
        case .wikimedia: "Wikimedia"
        case .internetArchive: "Internet Archive"
        case .youtube: "YouTube"
        }
    }
    var requiresAPIKey: Bool { [.pexels, .pixabay, .youtube].contains(self) }
}

enum MediaType: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, video, image
    var id: String { rawValue }
    var label: String { switch self { case .all: "全部"; case .video: "视频"; case .image: "图片" } }
}

enum AssetOrientation: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, landscape, portrait, square, unknown
    var id: String { rawValue }
    var label: String {
        switch self { case .all: "全部"; case .landscape: "横屏"; case .portrait: "竖屏"; case .square: "方形"; case .unknown: "未知" }
    }
}

enum ResolutionFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, hd720, fullHD, uhd4K
    var id: String { rawValue }
    var label: String { switch self { case .all: "全部"; case .hd720: "≥720p"; case .fullHD: "≥1080p"; case .uhd4K: "≥4K" } }
    var minimumHeight: Int? { switch self { case .all: nil; case .hd720: 720; case .fullHD: 1080; case .uhd4K: 2160 } }
}

enum DurationFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, under10, tenTo30, thirtyTo60, over60
    var id: String { rawValue }
    var label: String { switch self { case .all: "全部"; case .under10: "<10秒"; case .tenTo30: "10–30秒"; case .thirtyTo60: "30–60秒"; case .over60: "≥60秒" } }
    func matches(_ duration: Double?) -> Bool {
        guard self != .all else { return true }
        guard let duration else { return false }
        return switch self {
        case .all: true
        case .under10: duration < 10
        case .tenTo30: duration >= 10 && duration < 30
        case .thirtyTo60: duration >= 30 && duration < 60
        case .over60: duration >= 60
        }
    }
}

enum LicenseStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case safe = "SAFE"
    case attributionRequired = "ATTRIBUTION_REQUIRED"
    case publicDomain = "PUBLIC_DOMAIN"
    case unknown = "UNKNOWN"
    case restricted = "RESTRICTED"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .safe: "明确可用"
        case .attributionRequired: "需要署名"
        case .publicDomain: "Public Domain"
        case .unknown: "授权未知"
        case .restricted: "受限制"
        }
    }
}

struct MediaAsset: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let provider: ProviderID
    var title: String
    var description: String?
    var thumbnailURL: URL?
    var previewURL: URL?
    var downloadURL: URL?
    var sourcePageURL: URL
    var creator: String?
    var license: String?
    var licenseURL: URL?
    var licenseStatus: LicenseStatus
    var width: Int?
    var height: Int?
    var duration: Double?
    var fileType: String?
    var mediaType: MediaType
    var publishedDate: Date?
    var downloadable: Bool
    var originalMetadata: [String: String]
    var searchKeyword: String
    var relevanceScore: Double

    var stableID: String { "\(provider.rawValue):\(id)" }
    var orientation: AssetOrientation {
        guard let width, let height, width > 0, height > 0 else { return .unknown }
        if abs(Double(width - height)) / Double(max(width, height)) < 0.08 { return .square }
        return width > height ? .landscape : .portrait
    }
    var resolutionText: String {
        guard let width, let height else { return "未知" }
        return "\(width)×\(height)"
    }
    var durationText: String {
        guard let duration else { return "未知" }
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    var licenseText: String { license?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? licenseStatus.label }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
