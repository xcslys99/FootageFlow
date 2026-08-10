import Foundation

actor HTTPClient {
  static let shared = HTTPClient()

  private let session: URLSession
  private let decoder: JSONDecoder

  init() {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 25
    configuration.timeoutIntervalForResource = 60
    configuration.requestCachePolicy = .reloadRevalidatingCacheData
    configuration.httpAdditionalHeaders = [
      "User-Agent": "FootageFlow/0.1.0 (macOS open-source footage discovery app)"
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
        throw mapStatus(http.statusCode, retryAfter: retryAfter)
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

  private func mapStatus(_ status: Int, retryAfter: TimeInterval?) -> ProviderError {
    switch status {
    case 401, 403: .invalidAPIKey
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
