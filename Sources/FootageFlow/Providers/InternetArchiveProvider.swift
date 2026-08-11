import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct InternetArchiveProvider: MediaProvider {
  let info = ProviderInfo(
    id: .internetArchive, displayName: "Internet Archive", mode: .publicInterface,
    requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .supported, metadata: .supported, license: .bestEffort,
      download: .bestEffort, supportsVideo: true, supportsImage: true,
      supportsAudio: true,
      pagination: .supported,
      accessMethods: [.publicAPI, .publicInterface]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    let page = max(1, continuation?.page ?? 1)
    let mediaClause: String
    switch request.mediaType {
    case .video: mediaClause = "mediatype:movies"
    case .image: mediaClause = "mediatype:image"
    case .audio: mediaClause = "mediatype:audio"
    case .all: mediaClause = "(mediatype:movies OR mediatype:image OR mediatype:audio)"
    }
    var items = [
      URLQueryItem(name: "q", value: "(\(request.query)) AND \(mediaClause)"),
      URLQueryItem(name: "fl[]", value: "identifier"),
      URLQueryItem(name: "fl[]", value: "title"),
      URLQueryItem(name: "fl[]", value: "description"),
      URLQueryItem(name: "fl[]", value: "creator"),
      URLQueryItem(name: "fl[]", value: "year"),
      URLQueryItem(name: "fl[]", value: "date"),
      URLQueryItem(name: "fl[]", value: "mediatype"),
      URLQueryItem(name: "fl[]", value: "licenseurl"),
      URLQueryItem(name: "fl[]", value: "rights"),
      URLQueryItem(name: "rows", value: String(min(request.pageSize, 12))),
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "output", value: "json"),
    ]
    items.append(URLQueryItem(name: "sort[]", value: "downloads desc"))
    let url = try URL.endpoint("https://archive.org/advancedsearch.php", queryItems: items)
    let (data, _) = try await HTTPClient.shared.data(for: URLRequest(url: url))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let response = root["response"] as? [String: Any],
      let docs = response["docs"] as? [[String: Any]]
    else { throw ProviderError.invalidResponse }

    var assets: [MediaAsset] = []
    let indexed = Array(docs.enumerated())
    for start in stride(from: 0, to: indexed.count, by: 4) {
      if Task.isCancelled { break }
      let batch = Array(indexed[start..<min(start + 4, indexed.count)])
      let values = await withTaskGroup(of: MediaAsset?.self, returning: [MediaAsset].self) {
        group in
        for (index, doc) in batch {
          guard let identifier = string(doc["identifier"]) else { continue }
          group.addTask {
            await details(identifier: identifier, doc: doc, request: request, rank: index)
          }
        }
        var output: [MediaAsset] = []
        for await asset in group { if let asset { output.append(asset) } }
        return output
      }
      assets += values
    }
    let sorted = assets.sorted { $0.relevanceScore > $1.relevanceScore }
    let total = int(response["numFound"])
    let rows = min(request.pageSize, 12)
    let hasMoreByTotal = total.map { page * rows < $0 } ?? (docs.count == rows)
    let hasMore = !docs.isEmpty && hasMoreByTotal
    return ProviderPage(
      assets: sorted, continuation: hasMore ? .nextPage(page + 1) : nil,
      totalResults: total)
  }

  private func details(identifier: String, doc: [String: Any], request: SearchRequest, rank: Int)
    async -> MediaAsset?
  {
    do {
      let encoded =
        identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
      guard let metadataURL = URL(string: "https://archive.org/metadata/\(encoded)") else {
        return nil
      }
      let (data, _) = try await HTTPClient.shared.data(
        for: URLRequest(url: metadataURL), maxRetries: 1)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
      }
      let metadata = root["metadata"] as? [String: Any] ?? doc
      let files = root["files"] as? [[String: Any]] ?? []
      let mediatype = string(metadata["mediatype"]) ?? string(doc["mediatype"]) ?? ""
      let type: MediaType =
        mediatype == "movies" ? .video : (mediatype == "audio" ? .audio : .image)
      let candidates = files.compactMap { file -> IAFile? in
        guard let name = string(file["name"]), !name.hasPrefix("_") else { return nil }
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        let video = ["mp4", "m4v", "mov", "webm", "ogv"].contains(ext)
        let image = ["jpg", "jpeg", "png", "tif", "tiff", "webp"].contains(ext)
        let audio = ["mp3", "m4a", "wav", "flac", "ogg"].contains(ext)
        guard
          (type == .video && video) || (type == .image && image)
            || (type == .audio && audio)
        else { return nil }
        return IAFile(
          name: name, width: int(file["width"]), height: int(file["height"]),
          duration: duration(file["length"]), original: string(file["source"]) == "original",
          size: Int64(string(file["size"]) ?? ""), format: string(file["format"]))
      }
      let chosen = candidates.max { lhs, rhs in
        let leftPixels = (lhs.width ?? 0) * (lhs.height ?? 0)
        let rightPixels = (rhs.width ?? 0) * (rhs.height ?? 0)
        if leftPixels != rightPixels { return leftPixels < rightPixels }
        if lhs.original != rhs.original { return !lhs.original }
        return (lhs.size ?? 0) < (rhs.size ?? 0)
      }
      let previewFile = candidates.filter {
        ["mp4", "m4v", "mov"].contains(URL(fileURLWithPath: $0.name).pathExtension.lowercased())
      }.min { ($0.size ?? .max) < ($1.size ?? .max) }
      guard let source = URLValidator.remote("https://archive.org/details/\(encoded)") else {
        return nil
      }
      let download = chosen.flatMap { fileURL(identifier: identifier, name: $0.name) }
      let licenseURLText = string(metadata["licenseurl"]) ?? string(doc["licenseurl"])
      let rights = string(metadata["rights"]) ?? string(doc["rights"])
      let licenseName = ProviderUtilities.licenseName(name: rights, url: licenseURLText)
      let title = string(metadata["title"]) ?? string(doc["title"]) ?? identifier
      let description = ProviderUtilities.cleanHTML(
        string(metadata["description"]) ?? string(doc["description"]))
      let creator = string(metadata["creator"]) ?? string(doc["creator"])
      let dateText = string(metadata["date"]) ?? string(doc["date"]) ?? string(doc["year"])
      let thumbnails = ThumbnailResolver.candidates(
        provider: .internetArchive,
        rawValues: [
          "https://archive.org/services/img/\(encoded)",
          "https://archive.org/download/\(encoded)/__ia_thumb.jpg",
        ], originalPageURL: source)
      let thumbnail = thumbnails.first
      let relevanceText = "\(title) \(description ?? "")".lowercased()
      let tokens = request.query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }
      ).map(String.init).filter { $0.count > 2 }
      let matches = tokens.filter { relevanceText.contains($0) }.count
      let relevance = tokens.isEmpty ? 0 : Double(matches) / Double(tokens.count)
      let previewURL =
        type == .video || type == .audio
        ? (type == .audio ? chosen : previewFile).flatMap {
          fileURL(identifier: identifier, name: $0.name)
        }
        : (download ?? thumbnail)
      return MediaAsset(
        id: identifier, provider: .internetArchive, title: title, description: description,
        thumbnailURL: thumbnail, previewURL: previewURL, downloadURL: download,
        sourcePageURL: source, creator: creator, license: licenseName,
        licenseURL: URLValidator.remote(licenseURLText),
        licenseStatus: ProviderUtilities.licenseStatus(name: licenseName, url: licenseURLText),
        width: chosen?.width, height: chosen?.height,
        duration: chosen?.duration ?? duration(metadata["runtime"]),
        fileType: chosen.map { URL(fileURLWithPath: $0.name).pathExtension.lowercased() },
        mediaType: type, publishedDate: ProviderUtilities.parseDate(dateText),
        downloadable: download != nil,
        originalMetadata: ["identifier": identifier, "rights": rights ?? ""],
        searchKeyword: request.query, relevanceScore: relevance + (1 - Double(rank) * 0.01) * 0.1,
        thumbnailCandidates: thumbnails)
    } catch { return nil }
  }

  private func fileURL(identifier: String, name: String) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "archive.org"
    components.path = "/download/\(identifier)/\(name)"
    return components.url.flatMap { try? URLValidator.remote($0) }
  }
}

private struct IAFile {
  let name: String
  let width, height: Int?
  let duration: Double?
  let original: Bool
  let size: Int64?
  let format: String?
}
private func string(_ value: Any?) -> String? {
  if let text = value as? String { return text }
  if let number = value as? NSNumber { return number.stringValue }
  if let array = value as? [Any] { return array.compactMap { string($0) }.joined(separator: ", ") }
  return nil
}
private func int(_ value: Any?) -> Int? { string(value).flatMap(Int.init) }
private func duration(_ value: Any?) -> Double? {
  guard let text = string(value) else { return nil }
  if let number = Double(text) { return number }
  let parts = text.split(separator: ":").compactMap { Double($0) }
  if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
  if parts.count == 2 { return parts[0] * 60 + parts[1] }
  return nil
}
