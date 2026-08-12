import Foundation

enum RelevanceSmokeRunner {
  private struct Probe: Sendable {
    let provider: ProviderID
    let assets: [MediaAsset]
    let error: String?
  }

  static func run(query: String = "台湾美食") async -> Int32 {
    let ids: [ProviderID] = [
      .wikimedia, .internetArchive, .libraryOfCongress, .peertube, .openverse, .dailymotion,
    ]
    let keywords = KeywordEngine.keywords(for: query)
    print(
      "RELEVANCE_QUERY original=\(query) expanded=\(keywords.map(\.text).joined(separator: " | "))")
    var probes: [Probe] = []
    await withTaskGroup(of: Probe.self) { group in
      for id in ids {
        group.addTask {
          let provider = ProviderFactory.make(id, apiKey: "")
          let queries = KeywordEngine.providerKeywordPlan(
            from: keywords, provider: id, mode: provider.info.mode)
          let outcomes = await boundedSearch(provider: provider, keywords: queries)
          var candidates: [MediaAsset] = []
          var firstError: String?
          for outcome in outcomes {
            if let error = outcome.error {
              firstError = firstError ?? String(describing: type(of: error))
              continue
            }
            candidates += (outcome.assets ?? []).map { value in
              var asset = value
              asset.originalMetadata["matchedQuery"] = outcome.keyword.text
              asset.originalMetadata["matchedQueryLanguage"] =
                outcome.keyword.language?.rawValue ?? ""
              return asset
            }
          }
          return Probe(
            provider: id, assets: SearchDeduplicator.apply(candidates), error: firstError)
        }
      }
      for await probe in group { probes.append(probe) }
    }

    let candidates = SearchDeduplicator.apply(probes.flatMap(\.assets))
    let intent = SearchRelevanceEngine.intent(for: query)
    let before = Array(candidates.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(20))
    let beforeRelevant = before.filter {
      SearchRelevanceEngine.assess($0, intent: intent, mode: .balanced).eligible
    }.count
    let ranked = SearchRelevanceEngine.rank(
      candidates, query: query, mode: .balanced, supportingQueries: keywords.map(\.text))
    let after = Array(ranked.prefix(20))
    let afterRelevant = after.filter {
      SearchRelevanceEngine.assess($0, intent: intent, mode: .balanced).eligible
    }.count

    for probe in probes.sorted(by: { $0.provider.rawValue < $1.provider.rawValue }) {
      let kept = SearchRelevanceEngine.rank(probe.assets, query: query, mode: .balanced).count
      print(
        "RELEVANCE_PROVIDER provider=\(probe.provider.rawValue) candidates=\(probe.assets.count) kept=\(kept) error=\(probe.error ?? "-")"
      )
    }
    for (index, asset) in after.enumerated() {
      print(
        "RELEVANCE_TOP rank=\(index + 1) provider=\(asset.provider.rawValue) score=\(String(format: "%.3f", asset.relevanceScore)) coverage=\(asset.originalMetadata["conceptCoverage"] ?? "-") title=\(asset.title.replacingOccurrences(of: "\n", with: " "))"
      )
    }
    let beforePrecision = before.isEmpty ? 0 : Double(beforeRelevant) / Double(before.count)
    let afterPrecision = after.isEmpty ? 0 : Double(afterRelevant) / Double(after.count)
    print(
      "RELEVANCE_SMOKE candidates=\(candidates.count) before_top20=\(before.count) before_relevant=\(beforeRelevant) before_precision=\(String(format: "%.3f", beforePrecision)) after_top20=\(after.count) after_relevant=\(afterRelevant) after_precision=\(String(format: "%.3f", afterPrecision))"
    )
    return !after.isEmpty && afterRelevant == after.count ? 0 : 1
  }

  private struct QueryOutcome: Sendable {
    let keyword: SearchKeyword
    let assets: [MediaAsset]?
    let error: Error?
  }

  private static func boundedSearch(
    provider: any MediaProvider, keywords: [SearchKeyword]
  ) async -> [QueryOutcome] {
    await withTaskGroup(of: QueryOutcome.self) { group in
      var next = 0
      func enqueue(_ index: Int) {
        let keyword = keywords[index]
        group.addTask {
          do {
            let page = try await provider.searchPage(
              SearchRequest(query: keyword.text, mediaType: .video, pageSize: 12),
              continuation: nil)
            return QueryOutcome(keyword: keyword, assets: page.assets, error: nil)
          } catch {
            return QueryOutcome(keyword: keyword, assets: nil, error: error)
          }
        }
      }
      while next < min(2, keywords.count) {
        enqueue(next)
        next += 1
      }
      var values: [QueryOutcome] = []
      var halted = false
      for await value in group {
        values.append(value)
        if let error = value.error as? ProviderError {
          switch error {
          case .rateLimited, .temporarilyBlocked: halted = true
          default: break
          }
        }
        if !halted, next < keywords.count {
          enqueue(next)
          next += 1
        }
      }
      return values
    }
  }
}
