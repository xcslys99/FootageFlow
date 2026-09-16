import Foundation

/// Lightweight, user-initiated provider diagnostics. A check performs the
/// provider's existing one-result connection probe; it neither enumerates user
/// data nor changes a provider configuration.
enum ProviderHealthService {
  static func initialRecord(for id: ProviderID, enabled: Bool = true) -> ProviderHealthRecord {
    guard enabled else { return ProviderHealthRecord(providerID: id.rawValue, state: .disabled) }
    let provider = ProviderFactory.current(id)
    switch provider.info.mode {
    case .limited:
      return ProviderHealthRecord(providerID: id.rawValue, state: .limited, message: "limited")
    case .directSearch, .ytDLP:
      return ProviderHealthRecord(providerID: id.rawValue, state: .ready, message: "bestEffort")
    case .officialAPI, .publicAPI, .publicInterface:
      return ProviderHealthRecord(providerID: id.rawValue, state: .ready)
    }
  }

  static func test(_ id: ProviderID) async -> ProviderHealthRecord {
    let started = ContinuousClock.now
    let provider = ProviderFactory.current(id)
    do {
      try await provider.testConnection()
      let elapsed = started.duration(to: .now)
      let milliseconds =
        Int(elapsed.components.seconds * 1_000)
        + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
      return ProviderHealthRecord(
        providerID: id.rawValue, state: .healthy, testedAt: .now,
        responseTimeMilliseconds: max(0, milliseconds))
    } catch let error as ProviderError {
      let state: ProviderHealthState
      switch error {
      case .rateLimited: state = .rateLimited
      case .missingAPIKey: state = .apiKeyRequired
      case .invalidAPIKey: state = .authenticationRequired
      case .temporarilyBlocked, .accessRestricted, .serverUnavailable, .noNetwork:
        state = .unavailable
      default: state = .degraded
      }
      return ProviderHealthRecord(
        providerID: id.rawValue, state: state, message: error.errorDescription, testedAt: .now)
    } catch {
      return ProviderHealthRecord(
        providerID: id.rawValue, state: .unavailable, message: error.localizedDescription,
        testedAt: .now)
    }
  }
}
