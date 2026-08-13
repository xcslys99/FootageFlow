import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if canImport(Testing)
  import Testing

  @testable import FootageFlow

  @Suite("Update service networking", .serialized)
  struct AppUpdateServiceTests {
    @Test("HTTP and transport failures are classified without retries")
    func failureClassification() async {
      await expect(.rateLimited) { request in self.response(request, status: 403) }
      await expect(.rateLimited) { request in self.response(request, status: 429) }
      await expect(.serverUnavailable) { request in self.response(request, status: 503) }
      await expect(.invalidResponse) { request in
        self.response(request, status: 200, data: Data("not-json".utf8))
      }
      await expect(.noNetwork) { _ in throw URLError(.notConnectedToInternet) }
      await expect(.timedOut) { _ in throw URLError(.timedOut) }
    }

    @Test("A stable response returns the real release metadata")
    func stableResponse() async throws {
      let payload = Data(
        """
        {
          "tag_name":"v0.7.4",
          "name":"FootageFlow v0.7.4",
          "body":"## Fixed\\n- Update reminders",
          "html_url":"https://github.com/xcslys99/FootageFlow/releases/tag/v0.7.4",
          "published_at":"2026-08-13T00:00:00Z",
          "draft":false,
          "prerelease":false
        }
        """.utf8)
      UpdateStubURLProtocol.handler = { request in
        self.response(request, status: 200, data: payload)
      }
      let result = try await service().check(currentVersion: "0.7.3")
      guard case .updateAvailable(let release) = result else {
        Issue.record("The newer stable release was not offered")
        return
      }
      #expect(release.version == "0.7.4")
      #expect(release.notes.contains("• Update reminders"))
      #expect(release.publishedAt != nil)
    }

    private func expect(
      _ expected: AppUpdateCheckError,
      handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async {
      UpdateStubURLProtocol.handler = handler
      do {
        _ = try await service().check(currentVersion: "0.7.3")
        Issue.record("Expected update error \(expected.code)")
      } catch let error as AppUpdateCheckError {
        #expect(error == expected)
      } catch {
        Issue.record("Unexpected update error: \(error)")
      }
    }

    private func service() -> AppUpdateService {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [UpdateStubURLProtocol.self]
      return AppUpdateService(
        session: URLSession(configuration: configuration),
        endpoint: URL(string: "https://api.github.test/releases/latest")!)
    }

    private func response(
      _ request: URLRequest, status: Int, data: Data = Data()
    ) -> (HTTPURLResponse, Data) {
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"])!
      return (response, data)
    }
  }

  private final class UpdateStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      do {
        guard let handler = Self.handler else { throw URLError(.badServerResponse) }
        let (response, data) = try handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
      } catch {
        client?.urlProtocol(self, didFailWithError: error)
      }
    }

    override func stopLoading() {}
  }
#endif
