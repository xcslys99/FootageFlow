import Foundation

private struct Sidecar: Codable {
  let title, assetID, provider, creator, sourcePage, originalFileURL: String
  let licenseName, licenseURL, licenseStatus, searchKeyword, downloadDate, projectName,
    segment: String
  let rightsSource: String
  let outputPreset: String?
  let clipStartSeconds, clipEndSeconds, clipDurationSeconds: Double?
}

enum SourceSidecar {
  static func write(asset: MediaAsset, mediaURL: URL, projectName: String?, segmentIndex: Int?)
    throws
  {
    let formatter = ISO8601DateFormatter()
    let rights = asset.effectiveRightsInfo
    let status = rights.known ? asset.licenseStatus.label : tr("sidecar.authorizationUnknown")
    let sidecar = Sidecar(
      title: asset.title, assetID: asset.id, provider: asset.sourceDisplayName,
      creator: asset.creator ?? tr("common.unknown"),
      sourcePage: LinkURLSecurity.redactedString(asset.sourcePageURL)
        ?? asset.sourcePageURL.absoluteString,
      originalFileURL: LinkURLSecurity.redactedString(asset.downloadURL) ?? tr("common.unknown"),
      licenseName: rights.statement ?? asset.license ?? tr("common.unknown"),
      licenseURL: rights.uri?.absoluteString ?? asset.licenseURL?.absoluteString
        ?? tr("common.unknown"), licenseStatus: status,
      searchKeyword: redactedKeyword(asset.searchKeyword),
      downloadDate: formatter.string(from: .now),
      projectName: projectName ?? tr("common.uncategorized"),
      segment: segmentIndex.map(String.init) ?? tr("common.notSpecified"),
      rightsSource: rights.source ?? asset.sourceDisplayName,
      outputPreset: asset.originalMetadata["linkOutputPreset"],
      clipStartSeconds: asset.originalMetadata["linkClipStart"].flatMap(Double.init),
      clipEndSeconds: asset.originalMetadata["linkClipEnd"].flatMap(Double.init),
      clipDurationSeconds: asset.originalMetadata["linkClipDuration"].flatMap(Double.init))
    let base = mediaURL.deletingPathExtension()
    let jsonURL = base.appendingPathExtension("source.json")
    let textURL = base.appendingPathExtension("source.txt")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(sidecar).write(to: jsonURL, options: .atomic)
    var text = """
      \(tr("sidecar.title")): \(sidecar.title)
      \(tr("sidecar.assetID")): \(sidecar.assetID)
      \(tr("sidecar.provider")): \(sidecar.provider)
      \(tr("sidecar.creator")): \(sidecar.creator)
      \(tr("sidecar.sourcePage")): \(sidecar.sourcePage)
      \(tr("sidecar.originalFile")): \(sidecar.originalFileURL)
      \(tr("sidecar.licenseName")): \(sidecar.licenseName)
      \(tr("sidecar.licenseURL")): \(sidecar.licenseURL)
      \(tr("sidecar.licenseStatus")): \(sidecar.licenseStatus)
      \(tr("sidecar.rightsSource")): \(sidecar.rightsSource)
      \(tr("sidecar.searchKeyword")): \(sidecar.searchKeyword)
      \(tr("sidecar.downloadDate")): \(sidecar.downloadDate)
      \(tr("sidecar.projectName")): \(sidecar.projectName)
      \(tr("sidecar.segment")): \(sidecar.segment)
      """
    if let rawPreset = sidecar.outputPreset,
      let preset = EditingOutputPreset(rawValue: rawPreset)
    {
      text += "\n\(tr("link.outputFormat")): \(preset.label)"
    }
    if let start = sidecar.clipStartSeconds, let end = sidecar.clipEndSeconds {
      text += "\n\(tr("link.clip.start")): \(TimecodeParser.string(start))"
      text += "\n\(tr("link.clip.end")): \(TimecodeParser.string(end))"
      if let duration = sidecar.clipDurationSeconds {
        text += "\n\(tr("link.clip.duration", TimecodeParser.string(duration)))"
      }
    }
    text += "\n"
    try Data(text.utf8).write(to: textURL, options: .atomic)
  }

  private static func redactedKeyword(_ value: String) -> String {
    guard let url = URL(string: value), url.scheme != nil else { return value }
    return LinkURLSecurity.redactedString(url) ?? value
  }
}
