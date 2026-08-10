import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct LibraryOfCongressProvider: MediaProvider {
  let info = ProviderInfo(
    id: .libraryOfCongress, displayName: "Library of Congress", mode: .publicAPI,
    requiresAPIKey: false,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .supported, metadata: .supported, license: .bestEffort,
      download: .bestEffort, supportsVideo: true, supportsImage: true, supportsAudio: true,
      pagination: .supported,
      accessMethods: [.officialAPI, .publicAPI]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    try await searchPage(request, continuation: nil).assets
  }

  func searchPage(
    _ request: SearchRequest, continuation: ProviderContinuation?
  ) async throws -> ProviderPage {
    // LOC currently documents 150 requests/minute. Keep a conservative shared interval.
    try await ProviderRequestLimiter.shared.wait(
      for: .libraryOfCongress, minimumInterval: .milliseconds(500))
    let page = max(1, continuation?.page ?? 1)
    let collection =
      switch request.mediaType {
      case .video: "film-and-videos"
      case .image: "photos"
      case .audio: "audio-recordings"
      case .all: "search"
      }
    var items = [
      URLQueryItem(name: "fo", value: "json"),
      URLQueryItem(name: "at", value: "results,pagination"),
      URLQueryItem(name: "c", value: String(min(request.pageSize, 20))),
      URLQueryItem(name: "q", value: request.query),
      URLQueryItem(name: "sp", value: String(page)),
    ]
    if let from = request.yearFrom, let to = request.yearTo {
      items.append(URLQueryItem(name: "dates", value: "\(from)/\(to)"))
    } else if let from = request.yearFrom {
      items.append(URLQueryItem(name: "dates", value: "\(from)-"))
    } else if let to = request.yearTo {
      items.append(URLQueryItem(name: "dates", value: "-\(to)"))
    }
    let url = try URL.endpoint("https://www.loc.gov/\(collection)/", queryItems: items)
    let (data, _) = try await HTTPClient.shared.data(for: URLRequest(url: url))
    let assets = try Self.assets(from: data, request: request)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ProviderError.invalidResponse
    }
    let pagination = root["pagination"] as? [String: Any]
    let total = locInt(pagination?["of"])
    let hasMore = locString(pagination?["next"]) != nil
    return ProviderPage(
      assets: assets, continuation: hasMore ? .nextPage(page + 1) : nil,
      totalResults: total)
  }

  static func assets(from data: Data, request: SearchRequest) throws -> [MediaAsset] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let results = root["results"] as? [[String: Any]]
    else { throw ProviderError.invalidResponse }
    return results.enumerated().compactMap { index, item in
      asset(item, request: request, index: index)
    }
  }

  private static func asset(_ item: [String: Any], request: SearchRequest, index: Int)
    -> MediaAsset?
  {
    guard let idText = locString(item["id"]), let source = secure(idText) else { return nil }
    let resources = item["resources"] as? [[String: Any]] ?? []
    let type = mediaType(item: item, resources: resources)
    if request.mediaType != .all && request.mediaType != type { return nil }
    let resource = resources.first ?? [:]
    let restricted = locBool(resource["download_restricted"]) ?? false
    let directText: String? =
      switch type {
      case .video: locString(resource["video"])
      case .audio: locString(resource["audio"])
      case .image, .all: nil
      }
    let direct = restricted ? nil : secure(directText)
    let preview: URL? =
      switch type {
      case .video: secure(locString(resource["video_stream"])) ?? direct
      case .audio: direct
      case .image: secure(firstString(item["image_url"]))
      case .all: nil
      }
    let thumbnail = secure(locString(resource["image"])) ?? secure(firstString(item["image_url"]))
    let advisory =
      firstString(item["rights_advisory"])
      ?? firstString(item["rights_information"]) ?? firstString(item["rights"])
    let status = ProviderUtilities.licenseStatus(name: advisory)
    let rights = RightsInfo(
      statement: advisory, source: "Library of Congress item metadata",
      known: advisory != nil, publicDomain: status == .publicDomain,
      openLicense: [.safe, .attributionRequired, .publicDomain].contains(status),
      attributionRequired: status == .attributionRequired)
    let title = locString(item["title"]) ?? source.lastPathComponent
    let dateText = locString(item["date"])
    let creator = firstString(item["creator"]) ?? firstString(item["contributor"])
    let description = ProviderUtilities.cleanHTML(firstString(item["description"]))
    return MediaAsset(
      id: source.lastPathComponent.nilIfEmpty ?? source.absoluteString,
      provider: .libraryOfCongress, title: title, description: description,
      thumbnailURL: thumbnail, previewURL: preview, downloadURL: direct,
      sourcePageURL: source, creator: creator, license: advisory, licenseURL: nil,
      licenseStatus: status, width: locInt(resource["width"]), height: locInt(resource["height"]),
      duration: locDuration(resource["duration"]), fileType: direct?.pathExtension.nilIfEmpty,
      mediaType: type, publishedDate: ProviderUtilities.parseDate(dateText),
      downloadable: direct != nil,
      originalMetadata: [
        "subjects": strings(item["subject"]).joined(separator: ", "),
        "originalFormat": strings(item["original_format"]).joined(separator: ", "),
        "onlineFormat": strings(item["online_format"]).joined(separator: ", "),
        "downloadRestricted": String(restricted),
      ], searchKeyword: request.query, relevanceScore: 1 - Double(index) * 0.01,
      rightsInfo: rights, downloadAvailability: direct == nil ? .unavailable : .direct)
  }

  private static func mediaType(item: [String: Any], resources: [[String: Any]]) -> MediaType {
    if resources.contains(where: { locString($0["video"]) != nil }) { return .video }
    if resources.contains(where: { locString($0["audio"]) != nil }) { return .audio }
    let formats = (strings(item["online_format"]) + strings(item["original_format"]))
      .joined(separator: " ").lowercased()
    if formats.contains("video") || formats.contains("moving image") { return .video }
    if formats.contains("audio") || formats.contains("sound") { return .audio }
    return .image
  }
}

private func secure(_ value: String?) -> URL? {
  guard var components = value.flatMap(URLComponents.init(string:)) else { return nil }
  if components.scheme == "http" { components.scheme = "https" }
  return components.url.flatMap { try? URLValidator.remote($0) }
}
private func locString(_ value: Any?) -> String? {
  if let value = value as? String {
    return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }
  if let number = value as? NSNumber { return number.stringValue }
  return nil
}
private func strings(_ value: Any?) -> [String] {
  if let array = value as? [Any] { return array.compactMap(locString) }
  return locString(value).map { [$0] } ?? []
}
private func firstString(_ value: Any?) -> String? { strings(value).first }
private func locBool(_ value: Any?) -> Bool? {
  if let value = value as? Bool { return value }
  return locString(value).flatMap(Bool.init)
}
private func locInt(_ value: Any?) -> Int? { locString(value).flatMap(Int.init) }
private func locDuration(_ value: Any?) -> Double? {
  guard let text = locString(value) else { return nil }
  if let seconds = Double(text) { return seconds }
  let parts = text.split(separator: ":").compactMap { Double($0) }
  if parts.count == 3 { return parts[0] * 3_600 + parts[1] * 60 + parts[2] }
  if parts.count == 2 { return parts[0] * 60 + parts[1] }
  return nil
}
