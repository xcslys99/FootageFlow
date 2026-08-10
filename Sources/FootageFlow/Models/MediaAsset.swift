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
    var label: String { switch self { case .all: tr("common.all"); case .video: tr("common.video"); case .image: tr("common.image") } }
}

enum AssetOrientation: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, landscape, portrait, square, unknown
    var id: String { rawValue }
    var label: String {
        switch self { case .all: tr("common.all"); case .landscape: tr("media.landscape"); case .portrait: tr("media.portrait"); case .square: tr("media.square"); case .unknown: tr("common.unknown") }
    }
}

enum ResolutionFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, hd720, fullHD, uhd4K
    var id: String { rawValue }
    var label: String { switch self { case .all: tr("common.all"); case .hd720: tr("filter.hd720"); case .fullHD: tr("filter.fullHD"); case .uhd4K: tr("filter.uhd4K") } }
    var minimumHeight: Int? { switch self { case .all: nil; case .hd720: 720; case .fullHD: 1080; case .uhd4K: 2160 } }
}

enum DurationFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, under10, tenTo30, thirtyTo60, over60
    var id: String { rawValue }
    var label: String { switch self { case .all: tr("common.all"); case .under10: tr("filter.under10"); case .tenTo30: tr("filter.tenTo30"); case .thirtyTo60: tr("filter.thirtyTo60"); case .over60: tr("filter.over60") } }
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
        case .safe: tr("license.safe")
        case .attributionRequired: tr("license.attribution")
        case .publicDomain: tr("license.publicDomain")
        case .unknown: tr("license.unknown")
        case .restricted: tr("license.restricted")
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
        guard let width, let height else { return tr("common.unknown") }
        return "\(width)×\(height)"
    }
    var durationText: String {
        guard let duration else { return tr("common.unknown") }
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    var licenseText: String { license?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? licenseStatus.label }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
