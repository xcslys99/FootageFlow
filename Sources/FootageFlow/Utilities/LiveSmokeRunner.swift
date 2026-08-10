import Foundation

enum LiveSmokeRunner {
  static func run() async -> Int32 {
    var failures: [String] = []
    do {
      let bank = try await WikimediaProvider().search(
        SearchRequest(query: "bank", mediaType: .image, pageSize: 6))
      print("SMOKE wikimedia_bank_images=\(bank.count)")
      if let first = bank.first {
        print(
          "SMOKE wikimedia_first=\(first.title) source=\(first.sourcePageURL.absoluteString) license=\(first.licenseText)"
        )
      }
      if bank.isEmpty { failures.append("Wikimedia bank") }
    } catch { failures.append("Wikimedia bank: \(error.localizedDescription)") }
    do {
      let history = try await WikimediaProvider().search(
        SearchRequest(query: "Argentina financial crisis 2001", mediaType: .all, pageSize: 8))
      print("SMOKE wikimedia_history=\(history.count)")
      if history.isEmpty { failures.append("Wikimedia history") }
    } catch { failures.append("Wikimedia history: \(error.localizedDescription)") }
    do {
      let archive = try await InternetArchiveProvider().search(
        SearchRequest(query: "Argentina financial crisis 2001", mediaType: .video, pageSize: 5))
      print("SMOKE archive_history=\(archive.count)")
      if let first = archive.first {
        print(
          "SMOKE archive_first=\(first.title) source=\(first.sourcePageURL.absoluteString) license=\(first.licenseText)"
        )
      }
      if archive.isEmpty { failures.append("Internet Archive history") }
    } catch { failures.append("Internet Archive: \(error.localizedDescription)") }
    do {
      let nasa = try await NASAProvider().search(
        SearchRequest(
          query: "Apollo 11", mediaType: .video, yearFrom: 1969, yearTo: 1970, pageSize: 4))
      print("SMOKE nasa_apollo=\(nasa.count)")
      if let first = nasa.first {
        print(
          "SMOKE nasa_first=\(first.title) source=\(first.sourcePageURL.absoluteString) downloadable=\(first.isDirectlyDownloadable)"
        )
      }
      if nasa.isEmpty { failures.append("NASA Apollo 11") }
    } catch { failures.append("NASA: \(error.localizedDescription)") }
    do {
      let loc = try await LibraryOfCongressProvider().search(
        SearchRequest(query: "Apollo 11", mediaType: .video, pageSize: 4))
      print("SMOKE loc_apollo=\(loc.count)")
      if let first = loc.first {
        print(
          "SMOKE loc_first=\(first.title) source=\(first.sourcePageURL.absoluteString) downloadable=\(first.isDirectlyDownloadable)"
        )
      }
      if loc.isEmpty { failures.append("Library of Congress Apollo 11") }
    } catch { failures.append("Library of Congress: \(error.localizedDescription)") }
    let pexelsWithoutKey = ProviderFactory.make(.pexels, apiKey: "")
    if pexelsWithoutKey.info.mode == .directSearch && !pexelsWithoutKey.info.requiresAPIKey {
      print("SMOKE pexels_without_key_mode=directSearch")
    } else {
      failures.append("Pexels no-key mode")
    }
    if ProviderFactory.make(.nationalArchives, apiKey: "").info.mode == .limited {
      print("SMOKE nationalArchives_without_key_mode=limited")
    } else {
      failures.append("National Archives no-key mode")
    }
    if ProviderFactory.make(.europeana, apiKey: "").info.mode == .limited {
      print("SMOKE europeana_without_key_mode=limited")
    } else {
      failures.append("Europeana no-key mode")
    }
    async let pexelsDirect = directSearchFailure(PexelsDirectProvider())
    async let pixabayDirect = directSearchFailure(PixabayDirectProvider())
    if let failure = await pexelsDirect { failures.append(failure) }
    if let failure = await pixabayDirect { failures.append(failure) }
    print("LIVE_SMOKE failed=\(failures.count)")
    for failure in failures { print("FAIL \(failure)") }
    return failures.isEmpty ? 0 : 1
  }

  private static func directSearchFailure(_ provider: any MediaProvider) async -> String? {
    do {
      let results = try await provider.search(
        SearchRequest(query: "bank", mediaType: .image, pageSize: 1))
      print("SMOKE \(provider.info.id.rawValue)_direct_results=\(results.count)")
      return nil
    } catch ProviderError.temporarilyBlocked {
      print("SMOKE \(provider.info.id.rawValue)_direct_block_handled=true")
      return nil
    } catch ProviderError.rateLimited {
      print("SMOKE \(provider.info.id.rawValue)_direct_rate_limit_handled=true")
      return nil
    } catch {
      return "\(provider.info.displayName) direct mode: \(error.localizedDescription)"
    }
  }
}
