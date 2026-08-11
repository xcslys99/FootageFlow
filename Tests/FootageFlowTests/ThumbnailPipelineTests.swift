import Foundation

#if os(macOS) && canImport(Testing)
  import Testing

  @testable import FootageFlow

  @Suite("Thumbnail pipeline", .serialized)
  struct ThumbnailPipelineTests {
    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test("PeerTube relative paths use the actual instance")
    func peerTubeInstanceResolution() {
      let values = ThumbnailResolver.candidates(
        provider: .peertube,
        rawValues: ["/lazy-static/thumbnails/video.jpg"],
        originalPageURL: URL(string: "https://sepiasearch.org/w/video"),
        instanceURL: URL(string: "https://peertube.example.net"))
      #expect(
        values.first?.absoluteString
          == "https://peertube.example.net/lazy-static/thumbnails/video.jpg")
    }

    @Test("resolver handles absolute, protocol-relative, encoding and malformed values")
    func resolverVariants() {
      let base = URL(string: "https://example.org/videos/1")
      #expect(
        ThumbnailResolver.resolve("//cdn.example.org/a.jpg", relativeTo: base)?.absoluteString
          == "https://cdn.example.org/a.jpg")
      #expect(
        ThumbnailResolver.resolve("http://cdn.example.org/a b.jpg", relativeTo: base)?.scheme
          == "https")
      #expect(ThumbnailResolver.resolve("not a URL", relativeTo: nil) == nil)
      #expect(ThumbnailResolver.resolve(nil, relativeTo: base) == nil)
    }

    @Test("JPEG PNG WebP AVIF GIF detection and HTML rejection")
    func formatDetection() {
      let webp = Data("RIFF0000WEBP".utf8)
      let avif = Data([0, 0, 0, 20] + Array("ftypavif".utf8) + [0, 0, 0, 0])
      let gif = Data("GIF89a".utf8)
      #expect(ThumbnailImageFormat.detect(data: Self.jpeg, contentType: nil) == .jpeg)
      #expect(ThumbnailImageFormat.detect(data: Self.png, contentType: nil) == .png)
      #expect(ThumbnailImageFormat.detect(data: webp, contentType: nil) == .webp)
      #expect(ThumbnailImageFormat.detect(data: avif, contentType: nil) == .avif)
      #expect(ThumbnailImageFormat.detect(data: gif, contentType: nil) == .gif)
      #expect(
        ThumbnailResponseValidator.validate(
          status: 200, contentType: "text/html", data: Data("<html>403</html>".utf8)) == nil)
      #expect(
        ThumbnailResponseValidator.validate(
          status: 403, contentType: "image/jpeg", data: Self.jpeg) == nil)
    }

    @Test("redirects resolve and successful responses are cached")
    func redirectAndCache() async throws {
      let counter = LockedCounter()
      ThumbnailStubURLProtocol.handler = { request in
        counter.increment()
        if request.url?.path == "/start" {
          return Self.response(request, status: 302, headers: ["Location": "/final"])
        }
        return Self.response(
          request, status: 200, headers: ["Content-Type": "image/jpeg"], data: Self.jpeg)
      }
      let pipeline = makePipeline()
      let url = try #require(URL(string: "https://thumbnail.test/start"))
      let first = try await pipeline.load(url, provider: .peertube)
      let second = try await pipeline.load(url, provider: .peertube)
      #expect(first.format == .jpeg)
      #expect(second.fromCache)
      #expect(counter.value == 2)
    }

    @Test("403 404 failed cache and explicit retry are bounded")
    func failuresAndRetry() async throws {
      let counter = LockedCounter()
      ThumbnailStubURLProtocol.handler = { request in
        let attempt = counter.increment()
        if request.url?.path == "/forbidden" { return Self.response(request, status: 403) }
        if attempt < 3 { return Self.response(request, status: 404) }
        return Self.response(
          request, status: 200, headers: ["Content-Type": "image/png"], data: Self.png)
      }
      let pipeline = makePipeline()
      let forbidden = try #require(URL(string: "https://thumbnail.test/forbidden"))
      do {
        _ = try await pipeline.load(forbidden, provider: .peertube)
        Issue.record("403 must fail")
      } catch let error as ThumbnailPipelineError {
        #expect(error == .status(403))
      }

      let missing = try #require(URL(string: "https://thumbnail.test/missing"))
      do { _ = try await pipeline.load(missing, provider: .peertube) } catch {}
      let requestsAfterFirstFailure = counter.value
      do { _ = try await pipeline.load(missing, provider: .peertube) } catch {}
      #expect(counter.value == requestsAfterFirstFailure)
      let recovered = try await pipeline.load(missing, provider: .peertube, forceRetry: true)
      #expect(recovered.format == .png)
    }

    @Test("timeout is classified without an automatic retry loop")
    func timeout() async throws {
      ThumbnailStubURLProtocol.handler = { _ in throw URLError(.timedOut) }
      let pipeline = makePipeline()
      let url = try #require(URL(string: "https://thumbnail.test/timeout"))
      do {
        _ = try await pipeline.load(url, provider: .peertube)
        Issue.record("timeout must fail")
      } catch let error as ThumbnailPipelineError {
        #expect(error == .timedOut)
      }
    }

    private func makePipeline() -> ThumbnailPipeline {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [ThumbnailStubURLProtocol.self]
      let session = URLSession(configuration: configuration)
      return ThumbnailPipeline(
        session: session,
        cache: ThumbnailMemoryCache(successTTL: 60, failureTTL: 60, maximumEntries: 20))
    }

    private static func response(
      _ request: URLRequest, status: Int, headers: [String: String] = [:], data: Data = Data()
    ) -> (HTTPURLResponse, Data) {
      (
        HTTPURLResponse(
          url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
          headerFields: headers)!,
        data
      )
    }
  }

  private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    @discardableResult func increment() -> Int {
      lock.lock()
      defer { lock.unlock() }
      storage += 1
      return storage
    }
    var value: Int {
      lock.lock()
      defer { lock.unlock() }
      return storage
    }
  }

  private final class ThumbnailStubURLProtocol: URLProtocol, @unchecked Sendable {
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
      } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
  }
#endif
