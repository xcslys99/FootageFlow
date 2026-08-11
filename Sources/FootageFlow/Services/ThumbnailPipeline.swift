#if os(macOS)
  import AppKit
  import Foundation

  struct ThumbnailPayload: Sendable {
    let data: Data
    let format: ThumbnailImageFormat
    let finalURL: URL
    let fromCache: Bool
  }

  enum ThumbnailPipelineError: Error, Equatable, Sendable {
    case unavailable
    case status(Int)
    case invalidContent
    case tooLarge
    case timedOut
  }

  actor ThumbnailMemoryCache {
    static let shared = ThumbnailMemoryCache()

    private struct Success: Sendable {
      let payload: ThumbnailPayload
      let expiresAt: Date
    }
    private struct Failure: Sendable {
      let error: ThumbnailPipelineError
      let expiresAt: Date
    }

    private var successes: [URL: Success] = [:]
    private var failures: [URL: Failure] = [:]
    private let successTTL: TimeInterval
    private let failureTTL: TimeInterval
    private let maximumEntries: Int

    init(
      successTTL: TimeInterval = 6 * 60 * 60, failureTTL: TimeInterval = 45,
      maximumEntries: Int = 240
    ) {
      self.successTTL = successTTL
      self.failureTTL = failureTTL
      self.maximumEntries = maximumEntries
    }

    func success(for url: URL, now: Date = .now) -> ThumbnailPayload? {
      guard let entry = successes[url] else { return nil }
      guard entry.expiresAt > now else {
        successes[url] = nil
        return nil
      }
      return ThumbnailPayload(
        data: entry.payload.data, format: entry.payload.format,
        finalURL: entry.payload.finalURL, fromCache: true)
    }

    func failure(for url: URL, now: Date = .now) -> ThumbnailPipelineError? {
      guard let entry = failures[url] else { return nil }
      guard entry.expiresAt > now else {
        failures[url] = nil
        return nil
      }
      return entry.error
    }

    func storeSuccess(_ payload: ThumbnailPayload, for url: URL, now: Date = .now) {
      failures[url] = nil
      successes[url] = Success(payload: payload, expiresAt: now.addingTimeInterval(successTTL))
      if successes.count > maximumEntries,
        let oldest = successes.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key
      {
        successes[oldest] = nil
      }
    }

    func storeFailure(_ error: ThumbnailPipelineError, for url: URL, now: Date = .now) {
      successes[url] = nil
      failures[url] = Failure(error: error, expiresAt: now.addingTimeInterval(failureTTL))
    }

    func clearFailure(for url: URL) { failures[url] = nil }
  }

  actor ThumbnailPipeline {
    static let shared = ThumbnailPipeline()

    private let session: URLSession
    private let cache: ThumbnailMemoryCache

    init(session: URLSession? = nil, cache: ThumbnailMemoryCache = .shared) {
      self.cache = cache
      if let session {
        self.session = session
      } else {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = [
          "User-Agent": "FootageFlow/\(FootageFlowVersion.current) (thumbnail loader)",
          "Accept": "image/avif,image/webp,image/png,image/jpeg,image/gif;q=0.9,*/*;q=0.1",
        ]
        self.session = URLSession(configuration: configuration)
      }
    }

    func load(_ url: URL, provider: ProviderID?, forceRetry: Bool = false) async throws
      -> ThumbnailPayload
    {
      if let cached = await cache.success(for: url) { return cached }
      if forceRetry {
        await cache.clearFailure(for: url)
      } else if let failure = await cache.failure(for: url) {
        throw failure
      }

      var request = URLRequest(url: url)
      request.timeoutInterval = 12
      request.setValue(
        "image/avif,image/webp,image/png,image/jpeg,image/gif;q=0.9,*/*;q=0.1",
        forHTTPHeaderField: "Accept")
      do {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
          throw ThumbnailPipelineError.invalidContent
        }
        let status = http.statusCode
        guard (200..<300).contains(status) else {
          throw ThumbnailPipelineError.status(status)
        }
        if let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init),
          length > ThumbnailResponseValidator.maximumBytes
        {
          throw ThumbnailPipelineError.tooLarge
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        guard
          let format = ThumbnailResponseValidator.validate(
            status: status, contentType: contentType, data: data)
        else { throw ThumbnailPipelineError.invalidContent }
        let finalURL = http.url ?? url
        let payload = ThumbnailPayload(
          data: data, format: format, finalURL: finalURL, fromCache: false)
        await cache.storeSuccess(payload, for: url)
        return payload
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as URLError where error.code == .cancelled {
        throw CancellationError()
      } catch let error as URLError where error.code == .timedOut {
        await cache.storeFailure(.timedOut, for: url)
        await log(provider: provider, url: url, status: nil, error: .timedOut)
        throw ThumbnailPipelineError.timedOut
      } catch let error as ThumbnailPipelineError {
        await cache.storeFailure(error, for: url)
        let status: Int? = if case .status(let code) = error { code } else { nil }
        await log(provider: provider, url: url, status: status, error: error)
        throw error
      } catch {
        await cache.storeFailure(.unavailable, for: url)
        await log(provider: provider, url: url, status: nil, error: .unavailable)
        throw ThumbnailPipelineError.unavailable
      }
    }

    func recordDecodeFailure(for url: URL, provider: ProviderID?) async {
      await cache.storeFailure(.invalidContent, for: url)
      await log(provider: provider, url: url, status: nil, error: .invalidContent)
    }

    private func log(
      provider: ProviderID?, url: URL, status: Int?, error: ThumbnailPipelineError
    ) async {
      let detail =
        "host=\(url.host ?? "-") format=\(url.pathExtension.lowercased()) reason=\(error)"
      await AppLogger.shared.write(
        provider: provider, requestType: "thumbnail", status: status, detail: detail)
    }
  }
#endif
