import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct NationalArchivesProvider: MediaProvider {
  let apiKey: String
  let info = ProviderInfo(
    id: .nationalArchives, displayName: "National Archives", mode: .officialAPI,
    requiresAPIKey: true,
    capabilities: ProviderCapabilities(
      search: .supported, preview: .bestEffort, metadata: .supported, license: .bestEffort,
      download: .bestEffort, supportsVideo: true, supportsImage: true, supportsAudio: true,
      accessMethods: [.officialAPI]))

  func search(_ request: SearchRequest) async throws -> [MediaAsset] {
    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProviderError.missingAPIKey(.nationalArchives)
    }
    try await ProviderRequestLimiter.shared.wait(
      for: .nationalArchives, minimumInterval: .milliseconds(250))
    let url = try URL.endpoint(
      "https://catalog.archives.gov/api/v2/records/search",
      queryItems: [
        URLQueryItem(name: "q", value: request.query),
        URLQueryItem(name: "limit", value: String(min(request.pageSize, 20))),
      ])
    var urlRequest = URLRequest(url: url)
    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    let (data, _) = try await HTTPClient.shared.data(for: urlRequest, maxRetries: 1)
    return try Self.assets(from: data, request: request)
  }

  static func assets(from data: Data, request: SearchRequest) throws -> [MediaAsset] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ProviderError.invalidResponse
    }
    let body = root["body"] as? [String: Any] ?? root
    let hitsContainer = body["hits"] as? [String: Any]
    let hits =
      hitsContainer?["hits"] as? [[String: Any]]
      ?? body["results"] as? [[String: Any]] ?? []
    return hits.enumerated().compactMap { index, hit in
      let source = hit["_source"] as? [String: Any] ?? hit
      let record = source["record"] as? [String: Any] ?? source
      return asset(record, fallbackID: naraString(hit["_id"]), request: request, index: index)
    }
  }

  private static func asset(
    _ record: [String: Any], fallbackID: String?, request: SearchRequest, index: Int
  ) -> MediaAsset? {
    guard let naID = naraString(record["naId"]) ?? naraString(record["naid"]) ?? fallbackID,
      let source = URLValidator.remote("https://catalog.archives.gov/id/\(naID)")
    else { return nil }
    let objects =
      naraDictionaries(record["digitalObjects"])
      + naraDictionaries(record["digitalObjectArray"])
    let candidates = objects.compactMap { object -> (URL, MediaType)? in
      guard let url = naraURL(object["objectUrl"] ?? object["url"] ?? object["fileUrl"]),
        let type = naraMediaType(object: object, url: url)
      else { return nil }
      return (url, type)
    }
    let requested =
      candidates.first { request.mediaType == .all || $0.1 == request.mediaType }
      ?? candidates.first
    let type = requested?.1 ?? naraMediaType(record: record) ?? .image
    if request.mediaType != .all && request.mediaType != type { return nil }
    let thumbnail = objects.compactMap { naraURL($0["thumbnailLink"] ?? $0["thumbnailUrl"]) }.first
    let direct = requested?.0
    let restriction =
      naraNestedString(record["useRestriction"], keys: ["status", "note"])
      ?? naraNestedString(record["accessRestriction"], keys: ["status", "note"])
    let status = ProviderUtilities.licenseStatus(name: restriction)
    let rights = RightsInfo(
      statement: restriction, source: "National Archives Catalog item metadata",
      known: restriction != nil, publicDomain: status == .publicDomain,
      openLicense: [.safe, .attributionRequired, .publicDomain].contains(status),
      attributionRequired: status == .attributionRequired)
    return MediaAsset(
      id: naID, provider: .nationalArchives,
      title: naraString(record["title"]) ?? "National Archives \(naID)",
      description: ProviderUtilities.cleanHTML(
        naraString(record["scopeAndContentNote"]) ?? naraString(record["description"])),
      thumbnailURL: thumbnail, previewURL: type == .image ? (thumbnail ?? direct) : direct,
      downloadURL: direct, sourcePageURL: source,
      creator: naraCreator(record), license: restriction, licenseURL: nil,
      licenseStatus: status, width: nil, height: nil, duration: nil,
      fileType: direct?.pathExtension.nilIfEmpty, mediaType: type,
      publishedDate: ProviderUtilities.parseDate(
        naraString(record["productionDateArray"]) ?? naraString(record["date"])),
      downloadable: direct != nil,
      originalMetadata: [
        "naId": naID, "disclaimer": ProviderPolicy.nationalArchivesNotice,
        "accessRestriction": naraNestedString(record["accessRestriction"], keys: ["status"]) ?? "",
      ], searchKeyword: request.query, relevanceScore: 1 - Double(index) * 0.01,
      rightsInfo: rights, downloadAvailability: direct == nil ? .unavailable : .direct)
  }
}

private func naraString(_ value: Any?) -> String? {
  if let text = value as? String {
    return text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }
  if let number = value as? NSNumber { return number.stringValue }
  if let array = value as? [Any] { return array.compactMap(naraString).first }
  return nil
}
private func naraDictionaries(_ value: Any?) -> [[String: Any]] {
  if let values = value as? [[String: Any]] { return values }
  if let value = value as? [String: Any] { return [value] }
  return []
}
private func naraURL(_ value: Any?) -> URL? {
  guard let text = naraString(value), var components = URLComponents(string: text) else {
    return nil
  }
  if components.scheme == "http" { components.scheme = "https" }
  return components.url.flatMap { try? URLValidator.remote($0) }
}
private func naraNestedString(_ value: Any?, keys: [String]) -> String? {
  if let direct = naraString(value) { return direct }
  guard let dictionary = value as? [String: Any] else { return nil }
  return keys.compactMap { naraString(dictionary[$0]) }.joined(separator: "; ").nilIfEmpty
}
private func naraMediaType(object: [String: Any], url: URL) -> MediaType? {
  let text = "\(naraString(object["objectType"]) ?? "") \(url.pathExtension)".lowercased()
  if ["mp4", "mov", "m4v", "webm", "video"].contains(where: text.contains) { return .video }
  if ["mp3", "wav", "m4a", "audio", "sound"].contains(where: text.contains) { return .audio }
  if ["jpg", "jpeg", "png", "tif", "tiff", "image"].contains(where: text.contains) {
    return .image
  }
  return nil
}
private func naraMediaType(record: [String: Any]) -> MediaType? {
  let text = naraString(record["typeOfMaterials"])?.lowercased() ?? ""
  if text.contains("moving image") || text.contains("video") { return .video }
  if text.contains("sound") || text.contains("audio") { return .audio }
  if text.contains("photograph") || text.contains("image") { return .image }
  return nil
}
private func naraCreator(_ record: [String: Any]) -> String? {
  for key in ["creatingOrganizationArray", "creator", "creatingIndividualsArray"] {
    if let value = naraString(record[key]) { return value }
    if let dict = (record[key] as? [[String: Any]])?.first {
      if let value = naraString(dict["name"] ?? dict["creatorName"]) { return value }
    }
  }
  return nil
}
