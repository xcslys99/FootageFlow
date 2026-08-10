import Foundation

enum AcceptanceRunner {
  static func run(directory: URL) async -> Int32 {
    var passed = 0
    var failures: [String] = []
    func result(_ condition: Bool, _ name: String) {
      if condition {
        passed += 1
        print("ACCEPT PASS \(name)")
      } else {
        failures.append(name)
        print("ACCEPT FAIL \(name)")
      }
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      print("ACCEPT FAIL create directory")
      return 1
    }

    var sample: MediaAsset?
    do {
      let bank = try await WikimediaProvider().search(
        SearchRequest(query: "bank", mediaType: .image, pageSize: 8))
      result(!bank.isEmpty, "bank real provider")
      result(bank.allSatisfy { $0.mediaType == .image }, "image filter")
      result(bank.first?.sourcePageURL.host?.contains("wikimedia.org") == true, "source page URL")
    } catch { failures.append("bank real provider: \(error.localizedDescription)") }

    do {
      let history = try await WikimediaProvider().search(
        SearchRequest(query: "Argentina financial crisis 2001", mediaType: .image, pageSize: 15))
      let relevant = history.contains {
        $0.title.lowercased().contains("crisis") || $0.title.lowercased().contains("corralito")
      }
      result(relevant, "Argentina historical relevance")
    } catch { failures.append("historical search: \(error.localizedDescription)") }

    do {
      let videos = try await WikimediaProvider().search(
        SearchRequest(
          query: "Chase Manhattan Bank Logo Animation filetype:video", mediaType: .video,
          pageSize: 5))
      sample = videos.first { $0.licenseStatus == .publicDomain }
      result(!videos.isEmpty && videos.allSatisfy { $0.mediaType == .video }, "video filter")
      result(sample != nil, "public domain download candidate")
    } catch { failures.append("video search: \(error.localizedDescription)") }

    if let sample, let remote = sample.downloadURL {
      do {
        let (temporary, response) = try await URLSession.shared.download(from: remote)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let destination = directory.appendingPathComponent(
          FileNameSanitizer.fileName(asset: sample, index: 1))
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        try SourceSidecar.write(
          asset: sample, mediaURL: destination, projectName: "Test Project", segmentIndex: 1)
        let base = destination.deletingPathExtension()
        let fileSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        result(status == 200 && fileSize > 0, "real media download")
        result(
          FileManager.default.fileExists(atPath: base.appendingPathExtension("source.txt").path),
          "source txt")
        result(
          FileManager.default.fileExists(atPath: base.appendingPathExtension("source.json").path),
          "source json")
      } catch { failures.append("download: \(error.localizedDescription)") }
    }

    if let sample {
      let databaseURL = directory.appendingPathComponent("acceptance.database.json")
      if FileManager.default.fileExists(atPath: databaseURL.path) {
        try? FileManager.default.removeItem(at: databaseURL)
      }
      let persisted: Bool = await MainActor.run {
        let store = DataStore(fileURL: databaseURL)
        let project = store.addProject(name: "Test Project")
        store.toggleFavorite(asset: sample, projectID: project.id)
        let reopened = DataStore(fileURL: databaseURL)
        return reopened.projects.contains { $0.name == "Test Project" }
          && reopened.favorites.contains { $0.stableID == sample.stableID }
      }
      result(persisted, "project and favorite reopen")
    }

    do {
      _ = try await HTTPClient.shared.data(
        for: URLRequest(url: URL(string: "http://127.0.0.1:9/offline")!), maxRetries: 0)
      result(false, "friendly network error")
    } catch let error as ProviderError {
      result(
        error.errorDescription?.contains("网络") == true
          || error.errorDescription?.contains("失败") == true, "friendly network error")
    } catch { result(false, "friendly network error") }

    do {
      _ = try await PixabayProvider(apiKey: "").search(SearchRequest(query: "bank"))
      result(false, "missing API key")
    } catch ProviderError.missingAPIKey { result(true, "missing API key") } catch {
      result(false, "missing API key")
    }

    print("ACCEPTANCE passed=\(passed) failed=\(failures.count)")
    for failure in failures { print("FAIL \(failure)") }
    return failures.isEmpty ? 0 : 1
  }
}
