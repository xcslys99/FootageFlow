#if os(macOS)
  import AppKit
  import Foundation

  enum ThumbnailDiagnosticsRunner {
    private struct ProviderReport: Sendable {
      let provider: ProviderID
      let mode: ProviderMode
      let resultCount: Int
      let primarySuccesses: Int
      let pipelineSuccesses: Int
      let details: [String]
      let error: String?
    }

    static func run(query: String = "city") async -> Int32 {
      let providers = ProviderID.searchCases.map { ($0, ProviderFactory.current($0)) }
      var reports: [ProviderReport] = []
      await withTaskGroup(of: ProviderReport.self) { group in
        for (id, provider) in providers {
          group.addTask { await probe(id: id, provider: provider, query: query) }
        }
        for await report in group { reports.append(report) }
      }
      reports.sort { $0.provider.rawValue < $1.provider.rawValue }
      var primaryTotal = 0
      var pipelineTotal = 0
      var sampledTotal = 0
      for report in reports {
        sampledTotal += min(report.resultCount, 5)
        primaryTotal += report.primarySuccesses
        pipelineTotal += report.pipelineSuccesses
        print(
          "THUMBNAIL provider=\(report.provider.rawValue) mode=\(report.mode.rawValue) results=\(report.resultCount) primary=\(report.primarySuccesses) pipeline=\(report.pipelineSuccesses) error=\(report.error ?? "-")"
        )
        for detail in report.details { print("THUMBNAIL_DETAIL \(detail)") }
      }
      let before = sampledTotal > 0 ? 100 * Double(primaryTotal) / Double(sampledTotal) : 0
      let after = sampledTotal > 0 ? 100 * Double(pipelineTotal) / Double(sampledTotal) : 0
      print(
        "THUMBNAIL_SMOKE sampled=\(sampledTotal) primary_rate=\(String(format: "%.1f", before)) pipeline_rate=\(String(format: "%.1f", after))"
      )
      return pipelineTotal > 0 ? 0 : 1
    }

    private static func probe(
      id: ProviderID, provider: any MediaProvider, query: String
    ) async -> ProviderReport {
      do {
        let requestedType: MediaType = provider.info.capabilities.supportsImage ? .all : .video
        let assets = try await provider.search(
          SearchRequest(query: query, mediaType: requestedType, pageSize: 5))
        var primarySuccesses = 0
        var pipelineSuccesses = 0
        var details: [String] = []
        for asset in assets.prefix(5) {
          var primary = false
          if let url = asset.thumbnailURL {
            primary = (try? await baselineLoad(url)) == true
          }
          if primary { primarySuccesses += 1 }
          var success = false
          var final = "-"
          var format = "-"
          var reason = "missing"
          for candidate in asset.effectiveThumbnailCandidates {
            do {
              let payload = try await ThumbnailPipeline.shared.load(candidate, provider: id)
              guard let image = NSImage(data: payload.data), image.isValid else {
                await ThumbnailPipeline.shared.recordDecodeFailure(for: candidate, provider: id)
                reason = "decode"
                continue
              }
              success = true
              final = safeURL(payload.finalURL)
              format = payload.format.rawValue
              reason = "-"
              break
            } catch let error as ThumbnailPipelineError {
              reason = String(describing: error)
            } catch {
              reason = "unavailable"
            }
          }
          if success { pipelineSuccesses += 1 }
          let firstCandidate = asset.effectiveThumbnailCandidates.first
          details.append(
            "provider=\(id.rawValue) id=\(asset.id.prefix(40)) raw=\(asset.originalMetadata["thumbnailRaw"] ?? "-") normalized=\(firstCandidate.map(safeURL) ?? "-") absolute=\(firstCandidate.map { $0.baseURL == nil } ?? false) https=\(firstCandidate?.scheme == "https") candidates=\(asset.effectiveThumbnailCandidates.count) final=\(final) format=\(format) macDecode=\(success) reason=\(reason)"
          )
        }
        return ProviderReport(
          provider: id, mode: provider.info.mode, resultCount: assets.count,
          primarySuccesses: primarySuccesses, pipelineSuccesses: pipelineSuccesses,
          details: details, error: nil)
      } catch {
        return ProviderReport(
          provider: id, mode: provider.info.mode, resultCount: 0, primarySuccesses: 0,
          pipelineSuccesses: 0, details: [], error: String(describing: type(of: error)))
      }
    }

    private static func baselineLoad(_ url: URL) async throws -> Bool {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 12
      configuration.timeoutIntervalForResource = 20
      configuration.httpAdditionalHeaders = [:]
      let session = URLSession(configuration: configuration)
      let (data, response) = try await session.data(from: url)
      guard let http = response as? HTTPURLResponse,
        ThumbnailResponseValidator.validate(
          status: http.statusCode,
          contentType: http.value(forHTTPHeaderField: "Content-Type"), data: data) != nil
      else { return false }
      return NSImage(data: data)?.isValid == true
    }

    private static func safeURL(_ url: URL) -> String {
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
        return "invalid"
      }
      components.query = nil
      components.fragment = nil
      return components.url?.absoluteString ?? "invalid"
    }
  }
#endif
