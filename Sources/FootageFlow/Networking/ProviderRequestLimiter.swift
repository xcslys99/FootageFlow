import Foundation

actor ProviderRequestLimiter {
  static let shared = ProviderRequestLimiter()
  private var lastRequest: [ProviderID: ContinuousClock.Instant] = [:]
  private let clock = ContinuousClock()

  func wait(for provider: ProviderID, minimumInterval: Duration) async throws {
    if let last = lastRequest[provider] {
      let deadline = last.advanced(by: minimumInterval)
      if clock.now < deadline { try await clock.sleep(until: deadline) }
    }
    lastRequest[provider] = clock.now
  }
}
