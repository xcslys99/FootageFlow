import Foundation

struct SearchKeyword: Identifiable, Codable, Hashable, Sendable {
  var id = UUID()
  var text: String
  var isEnabled = true
}

struct SearchRequest: Sendable {
  var query: String
  var mediaType: MediaType = .video
  var orientation: AssetOrientation = .all
  var resolution: ResolutionFilter = .all
  var duration: DurationFilter = .all
  var pageSize: Int = 16
}

struct ProviderInfo: Sendable {
  let id: ProviderID
  let displayName: String
  let requiresAPIKey: Bool
  let supportsVideo: Bool
  let supportsImage: Bool
  let supportsDownload: Bool
}

enum ProviderAvailability: String, Codable, Sendable {
  case available
  case unavailable
  case authenticationRequired
  case rateLimited
  case disabled

  var label: String {
    switch self {
    case .available: tr("provider.available")
    case .unavailable: tr("provider.unavailable")
    case .authenticationRequired: tr("provider.authenticationRequired")
    case .rateLimited: tr("provider.rateLimited")
    case .disabled: tr("provider.disabled")
    }
  }
}

struct ProviderRuntimeState: Codable, Equatable, Sendable {
  var availability: ProviderAvailability
  var message: String?

  static func from(error: Error) -> ProviderRuntimeState {
    guard let providerError = error as? ProviderError else {
      return ProviderRuntimeState(availability: .unavailable, message: error.localizedDescription)
    }
    let availability: ProviderAvailability =
      switch providerError {
      case .missingAPIKey, .invalidAPIKey: .authenticationRequired
      case .rateLimited: .rateLimited
      case .cancelled: .unavailable
      default: .unavailable
      }
    return ProviderRuntimeState(availability: availability, message: providerError.errorDescription)
  }
}

struct ProviderSearchResult: Sendable {
  let provider: ProviderID
  let assets: [MediaAsset]
  let error: ProviderError?
  let state: ProviderRuntimeState?
}

enum SearchStatus: Sendable {
  case initial
  case enterQuery
  case searchingProviders(Int)
  case stopped
  case noResults
  case found(Int)
  case searchingOthers
  case progressiveFound(Int)

  var text: String {
    switch self {
    case .initial: tr("search.initialStatus")
    case .enterQuery: tr("search.enterQuery")
    case .searchingProviders(let count): tr("search.searchingProviders", count)
    case .stopped: tr("search.stopped")
    case .noResults: tr("search.noResults")
    case .found(let count): tr("search.found", count)
    case .searchingOthers: tr("search.searchingOthers")
    case .progressiveFound(let count): tr("search.progressiveFound", count)
    }
  }
}

enum ProviderError: LocalizedError, Sendable {
  case missingAPIKey(ProviderID)
  case invalidAPIKey
  case noNetwork
  case rateLimited(retryAfter: TimeInterval?)
  case notFound
  case serverUnavailable
  case invalidResponse
  case unsupported
  case cancelled
  case message(String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey(let provider): tr("provider.missingKey", provider.displayName)
    case .invalidAPIKey: tr("error.invalidAPIKey")
    case .noNetwork: tr("error.noNetwork")
    case .rateLimited: tr("error.rateLimited")
    case .notFound: tr("error.notFound")
    case .serverUnavailable: tr("error.serverUnavailable")
    case .invalidResponse: tr("error.invalidResponse")
    case .unsupported: tr("error.unsupported")
    case .cancelled: tr("error.cancelled")
    case .message(let text): text
    }
  }
}

enum SearchSort: String, CaseIterable, Identifiable {
  case relevance, newest, resolution, duration
  var id: String { rawValue }
  var label: String {
    switch self {
    case .relevance: tr("sort.relevance")
    case .newest: tr("sort.newest")
    case .resolution: tr("sort.resolution")
    case .duration: tr("sort.duration")
    }
  }
}

enum LicenseFilter: String, CaseIterable, Identifiable {
  case all, safe, attribution, publicDomain, unknown
  var id: String { rawValue }
  var label: String {
    switch self {
    case .all: tr("common.all")
    case .safe: tr("license.safe")
    case .attribution: tr("license.attribution")
    case .publicDomain: tr("license.publicDomain")
    case .unknown: tr("license.unknown")
    }
  }
  func matches(_ status: LicenseStatus) -> Bool {
    switch self {
    case .all: true
    case .safe: status == .safe
    case .attribution: status == .attributionRequired
    case .publicDomain: status == .publicDomain
    case .unknown: status == .unknown
    }
  }
}
