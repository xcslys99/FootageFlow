import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
  case pexels, pixabay, wikimedia, internetArchive, youtube
  case nasa, libraryOfCongress, nationalArchives, europeana
  case peertube, videvo, videezy, mixkit, coverr, vimeo
  case linkDownloader

  var id: String { rawValue }
  var displayName: String {
    return switch self {
    case .pexels: "Pexels"
    case .pixabay: "Pixabay"
    case .wikimedia: "Wikimedia"
    case .internetArchive: "Internet Archive"
    case .youtube: "YouTube"
    case .nasa: "NASA"
    case .libraryOfCongress: "Library of Congress"
    case .nationalArchives: "National Archives"
    case .europeana: "Europeana"
    case .peertube: "PeerTube / SepiaSearch"
    case .videvo: "Videvo"
    case .videezy: "Videezy"
    case .mixkit: "Mixkit"
    case .coverr: "Coverr"
    case .vimeo: "Vimeo"
    case .linkDownloader: "Link Downloader"
    }
  }
  var supportsAPIKey: Bool {
    [.pexels, .pixabay, .youtube, .nationalArchives, .europeana, .coverr, .vimeo].contains(self)
  }
  var requiresAPIKey: Bool { [.nationalArchives, .europeana].contains(self) }

  /// Providers shown by aggregated search. Link Downloader creates assets but is not a search source.
  static var searchCases: [ProviderID] { allCases.filter { $0 != .linkDownloader } }
}

enum MediaType: String, Codable, CaseIterable, Identifiable, Sendable {
  case all, video, image, audio
  var id: String { rawValue }
  var label: String {
    switch self {
    case .all: tr("common.all")
    case .video: tr("common.video")
    case .image: tr("common.image")
    case .audio: tr("common.audio")
    }
  }
}

enum AssetOrientation: String, Codable, CaseIterable, Identifiable, Sendable {
  case all, landscape, portrait, square, unknown
  var id: String { rawValue }
  var label: String {
    switch self {
    case .all: tr("common.all")
    case .landscape: tr("media.landscape")
    case .portrait: tr("media.portrait")
    case .square: tr("media.square")
    case .unknown: tr("common.unknown")
    }
  }
}

enum ResolutionFilter: String, Codable, CaseIterable, Identifiable, Sendable {
  case all, hd720, fullHD, uhd4K
  var id: String { rawValue }
  var label: String {
    switch self {
    case .all: tr("common.all")
    case .hd720: tr("filter.hd720")
    case .fullHD: tr("filter.fullHD")
    case .uhd4K: tr("filter.uhd4K")
    }
  }
  var minimumHeight: Int? {
    switch self {
    case .all: nil
    case .hd720: 720
    case .fullHD: 1080
    case .uhd4K: 2160
    }
  }
}

enum DurationFilter: String, Codable, CaseIterable, Identifiable, Sendable {
  case all, underMinute, oneToFive, fiveToTwenty, overTwenty
  var id: String { rawValue }
  var label: String {
    switch self {
    case .all: tr("common.all")
    case .underMinute: tr("filter.underMinute")
    case .oneToFive: tr("filter.oneToFive")
    case .fiveToTwenty: tr("filter.fiveToTwenty")
    case .overTwenty: tr("filter.overTwenty")
    }
  }
  func matches(_ duration: Double?) -> Bool {
    guard self != .all else { return true }
    guard let duration else { return false }
    return switch self {
    case .all: true
    case .underMinute: duration < 60
    case .oneToFive: duration >= 60 && duration < 300
    case .fiveToTwenty: duration >= 300 && duration < 1_200
    case .overTwenty: duration >= 1_200
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

enum AssetDownloadStrategy: String, Codable, Sendable {
  case directURL
  case ytDLP
}

enum DownloadAvailability: String, Codable, Sendable {
  case direct
  case conditional
  case unavailable
}

/// Rights facts supplied by the source. Unknown values remain nil/false by design.
struct RightsInfo: Codable, Hashable, Sendable {
  var statement: String?
  var uri: URL?
  var source: String?
  var known: Bool
  var publicDomain: Bool
  var openLicense: Bool
  var attributionRequired: Bool
  var commercialUseKnown: Bool?

  init(
    statement: String?, uri: URL? = nil, source: String? = nil, known: Bool? = nil,
    publicDomain: Bool = false, openLicense: Bool = false,
    attributionRequired: Bool = false, commercialUseKnown: Bool? = nil
  ) {
    self.statement = statement?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    self.uri = uri
    self.source = source
    self.known = known ?? (self.statement != nil || uri != nil)
    self.publicDomain = publicDomain
    self.openLicense = openLicense
    self.attributionRequired = attributionRequired
    self.commercialUseKnown = commercialUseKnown
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
  var downloadStrategy: AssetDownloadStrategy? = nil
  var rightsInfo: RightsInfo? = nil
  var downloadAvailability: DownloadAvailability? = nil
  /// Ordered, normalized alternatives. Optional keeps v0.1-v0.5 persisted JSON decodable.
  var thumbnailCandidates: [URL]? = nil

  var stableID: String { "\(provider.rawValue):\(id)" }
  var sourceDisplayName: String {
    originalMetadata["sourceName"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? provider.displayName
  }
  var effectiveDownloadStrategy: AssetDownloadStrategy { downloadStrategy ?? .directURL }
  var effectiveDownloadAvailability: DownloadAvailability {
    downloadAvailability ?? (downloadable && downloadURL != nil ? .direct : .unavailable)
  }
  var isDirectlyDownloadable: Bool { effectiveDownloadAvailability == .direct }
  var effectiveThumbnailCandidates: [URL] {
    let explicit = thumbnailCandidates ?? []
    var rawValues: [String?] = [thumbnailURL?.absoluteString]
    rawValues += explicit.map(\.absoluteString)
    if mediaType == .image {
      rawValues += [previewURL?.absoluteString, downloadURL?.absoluteString]
    }
    rawValues += [
      originalMetadata["thumbnail"], originalMetadata["previewImage"],
      originalMetadata["poster"], originalMetadata["image"],
    ]
    return ThumbnailResolver.candidates(
      provider: provider, rawValues: rawValues, originalPageURL: sourcePageURL,
      instanceURL: ThumbnailResolver.origin(fromHost: originalMetadata["instanceHost"]),
      metadata: originalMetadata)
  }
  var effectiveRightsInfo: RightsInfo {
    if let rightsInfo { return rightsInfo }
    return RightsInfo(
      statement: license, uri: licenseURL, source: provider.displayName,
      known: licenseStatus != .unknown,
      publicDomain: licenseStatus == .publicDomain,
      openLicense: [.safe, .attributionRequired, .publicDomain].contains(licenseStatus),
      attributionRequired: licenseStatus == .attributionRequired)
  }
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
  var licenseText: String {
    license?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? licenseStatus.label
  }
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
