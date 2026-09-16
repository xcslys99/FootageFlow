import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

actor HTTPClient {
  static let shared = HTTPClient()

  private let session: URLSession
  private let decoder: JSONDecoder

  init() {
    // Provider credentials must never be persisted by URLSession. FootageFlow's normalized
    // SearchCache handles provider-required result caching without storing request URLs or keys.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 25
    configuration.timeoutIntervalForResource = 60
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpAdditionalHeaders = [
      "User-Agent": "FootageFlow/\(FootageFlowVersion.current) (open-source footage discovery app)"
    ]
    session = URLSession(configuration: configuration)
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  func data(for request: URLRequest, maxRetries: Int = 2) async throws -> (Data, HTTPURLResponse) {
    var attempt = 0
    while true {
      do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        if (200..<300).contains(http.statusCode) { return (data, http) }
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        if http.statusCode == 429, attempt < maxRetries {
          let delay = min(retryAfter ?? pow(2, Double(attempt + 1)), 15)
          try await Task.sleep(for: .seconds(delay))
          attempt += 1
          continue
        }
        if (500...599).contains(http.statusCode), attempt < maxRetries {
          try await Task.sleep(for: .seconds(pow(2, Double(attempt))))
          attempt += 1
          continue
        }
        throw Self.mapStatus(http.statusCode, request: request, retryAfter: retryAfter)
      } catch is CancellationError {
        throw ProviderError.cancelled
      } catch let error as ProviderError {
        throw error
      } catch let error as URLError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed,
          .cannotConnectToHost:
          throw ProviderError.noNetwork
        case .cancelled: throw ProviderError.cancelled
        case .timedOut: throw ProviderError.message(tr("error.timeout"))
        default: throw ProviderError.message(tr("error.requestFailed"))
        }
      } catch {
        throw ProviderError.invalidResponse
      }
    }
  }

  func decode<T: Decodable>(_ type: T.Type, request: URLRequest, maxRetries: Int = 2) async throws
    -> T
  {
    let (data, _) = try await data(for: request, maxRetries: maxRetries)
    do { return try decoder.decode(T.self, from: data) } catch {
      throw ProviderError.invalidResponse
    }
  }

  nonisolated static func mapStatus(
    _ status: Int, request: URLRequest, retryAfter: TimeInterval? = nil
  ) -> ProviderError {
    let headerNames = Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() })
    let queryNames = Set(
      (request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
        .queryItems ?? []).map { $0.name.lowercased() })
    let hasCredential =
      headerNames.contains("authorization") || headerNames.contains("x-api-key")
      || !queryNames.isDisjoint(with: ["key", "api_key", "apikey", "access_token", "token"])
    return switch status {
    case 401, 403: hasCredential ? .invalidAPIKey : .accessRestricted
    case 404: .notFound
    case 429: .rateLimited(retryAfter: retryAfter)
    case 500...599: .serverUnavailable
    default: .message(tr("error.http", status))
    }
  }
}

extension URL {
  static func endpoint(_ base: String, queryItems: [URLQueryItem]) throws -> URL {
    guard var components = URLComponents(string: base), components.scheme == "https",
      components.host != nil
    else { throw ProviderError.invalidResponse }
    components.queryItems = queryItems
    guard let url = components.url else { throw ProviderError.invalidResponse }
    return try URLValidator.remote(url)
  }
}
