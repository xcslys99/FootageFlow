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

enum ProviderCapabilityLevel: String, Codable, Sendable {
  case unavailable
  case supported
  case bestEffort

  var isAvailable: Bool { self != .unavailable }
}

enum ProviderAccessMethod: String, Codable, Hashable, Sendable {
  case officialAPI
  case publicAPI
  case publicInterface
  case directSearch
  case externalTool
}

enum ProviderMode: String, Codable, Sendable {
  case officialAPI
  case publicInterface
  case directSearch
  case ytDLP

  var label: String {
    switch self {
    case .officialAPI: tr("provider.mode.officialAPI")
    case .publicInterface: tr("provider.mode.publicInterface")
    case .directSearch: tr("provider.mode.directSearch")
    case .ytDLP: tr("provider.mode.ytDLP")
    }
  }
}

struct ProviderCapabilities: Codable, Sendable {
  let search: ProviderCapabilityLevel
  let preview: ProviderCapabilityLevel
  let metadata: ProviderCapabilityLevel
  let license: ProviderCapabilityLevel
  let download: ProviderCapabilityLevel
  let supportsVideo: Bool
  let supportsImage: Bool
  let accessMethods: Set<ProviderAccessMethod>
}

struct ProviderInfo: Sendable {
  let id: ProviderID
  let displayName: String
  let mode: ProviderMode
  let capabilities: ProviderCapabilities
  let requiresAPIKey: Bool

  var supportsVideo: Bool { capabilities.supportsVideo }
  var supportsImage: Bool { capabilities.supportsImage }
  var supportsDownload: Bool { capabilities.download.isAvailable }

  init(
    id: ProviderID, displayName: String, mode: ProviderMode, requiresAPIKey: Bool,
    capabilities: ProviderCapabilities
  ) {
    self.id = id
    self.displayName = displayName
    self.mode = mode
    self.requiresAPIKey = requiresAPIKey
    self.capabilities = capabilities
  }

  init(
    id: ProviderID, displayName: String, requiresAPIKey: Bool, supportsVideo: Bool,
    supportsImage: Bool, supportsDownload: Bool
  ) {
    self.init(
      id: id, displayName: displayName,
      mode: requiresAPIKey ? .officialAPI : .publicInterface,
      requiresAPIKey: requiresAPIKey,
      capabilities: ProviderCapabilities(
        search: .supported, preview: .supported, metadata: .supported, license: .supported,
        download: supportsDownload ? .supported : .unavailable, supportsVideo: supportsVideo,
        supportsImage: supportsImage,
        accessMethods: [requiresAPIKey ? .officialAPI : .publicInterface]))
  }
}

enum ProviderAvailability: String, Codable, Sendable {
  case available
  case unavailable
  case bestEffort
  case apiConnected
  case authenticationRequired
  case rateLimited
  case temporarilyBlocked
  case disabled

  var label: String {
    switch self {
    case .available: tr("provider.available")
    case .unavailable: tr("provider.unavailable")
    case .bestEffort: tr("provider.bestEffort")
    case .apiConnected: tr("provider.apiConnected")
    case .authenticationRequired: tr("provider.authenticationRequired")
    case .rateLimited: tr("provider.rateLimited")
    case .temporarilyBlocked: tr("provider.temporarilyBlocked")
    case .disabled: tr("provider.disabled")
    }
  }
}

struct ProviderRuntimeState: Codable, Equatable, Sendable {
  var availability: ProviderAvailability
  var message: String?
  var mode: ProviderMode? = nil

  static func from(error: Error) -> ProviderRuntimeState {
    guard let providerError = error as? ProviderError else {
      return ProviderRuntimeState(availability: .unavailable, message: error.localizedDescription)
    }
    let availability: ProviderAvailability =
      switch providerError {
      case .missingAPIKey, .invalidAPIKey: .authenticationRequired
      case .rateLimited: .rateLimited
      case .temporarilyBlocked: .temporarilyBlocked
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
  let mode: ProviderMode
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
  case temporarilyBlocked(ProviderID)
  case externalToolUnavailable
  case videoUnavailable
  case regionalRestriction
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
    case .temporarilyBlocked(let provider):
      tr("error.directTemporarilyBlocked", provider.displayName)
    case .externalToolUnavailable: tr("error.externalToolUnavailable")
    case .videoUnavailable: tr("error.videoUnavailable")
    case .regionalRestriction: tr("error.regionalRestriction")
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
  case all, knownOnly, safe, attribution, publicDomain, unknown
  var id: String { rawValue }
  var label: String {
    switch self {
    case .all: tr("common.all")
    case .knownOnly: tr("license.knownOnly")
    case .safe: tr("license.safe")
    case .attribution: tr("license.attribution")
    case .publicDomain: tr("license.publicDomain")
    case .unknown: tr("license.unknown")
    }
  }
  func matches(_ status: LicenseStatus) -> Bool {
    switch self {
    case .all: true
    case .knownOnly: status != .unknown
    case .safe: status == .safe
    case .attribution: status == .attributionRequired
    case .publicDomain: status == .publicDomain
    case .unknown: status == .unknown
    }
  }
}
