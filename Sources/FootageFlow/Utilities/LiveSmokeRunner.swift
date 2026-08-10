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
      _ = try await PexelsProvider(apiKey: "").search(SearchRequest(query: "bank"))
      failures.append("Missing key handling")
    } catch ProviderError.missingAPIKey { print("SMOKE missing_key_handled=true") } catch {
      failures.append("Missing key wrong error")
    }
    print("LIVE_SMOKE failed=\(failures.count)")
    for failure in failures { print("FAIL \(failure)") }
    return failures.isEmpty ? 0 : 1
  }
}
