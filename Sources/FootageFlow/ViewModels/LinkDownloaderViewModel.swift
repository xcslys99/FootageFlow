import Foundation

struct LinkDownloaderItem: Identifiable {
  let id = UUID()
  let rawURL: String
  var analysis: LinkMediaAnalysis?
  var isSelected = true
  var quality: LinkDownloadQuality = .best
  var downloadSubtitles = false
  var subtitleLanguage = ""
  var scope: LinkDownloadScope = .full
  var outputPreset: EditingOutputPreset = .original
  var clipStart = "00:00:00"
  var clipEnd = ""
  var errorKey: String?

  var isReady: Bool { analysis != nil && errorKey == nil }
  var clipRange: ClipTimeRange? {
    guard scope == .clip, let analysis else { return nil }
    return try? ClipTimeRange.parse(
      start: clipStart, end: clipEnd, mediaDuration: analysis.duration)
  }
  var clipValidationKey: String? {
    guard scope == .clip, let analysis else { return nil }
    do {
      _ = try ClipTimeRange.parse(
        start: clipStart, end: clipEnd, mediaDuration: analysis.duration)
      return nil
    } catch let error as ClipRangeError {
      return error.localizationKey
    } catch {
      return "link.clip.invalidRange"
    }
  }
  var isDownloadReady: Bool { isReady && (scope == .full || clipRange != nil) }
}

@MainActor
final class LinkDownloaderViewModel: ObservableObject {
  @Published var input = ""
  @Published var items: [LinkDownloaderItem] = []
  @Published var isAnalyzing = false
  @Published var downloadRoot = AppSettings.downloadRootURL
  @Published var statusKey = "link.initialStatus"
  @Published var clipboardDetectionEnabled = AppSettings.clipboardDetectionEnabled {
    didSet { AppSettings.clipboardDetectionEnabled = clipboardDetectionEnabled }
  }
  @Published private(set) var detectedClipboardURLs: [URL] = []

  private var analysisTask: Task<Void, Never>?
  private let service: YTDLPService
  private var clipboardSession = ClipboardSuggestionSession()

  init(service: YTDLPService = YTDLPService()) { self.service = service }

  var detectedCount: Int { LinkURLParser.urls(from: input).count }
  var canDownloadSelected: Bool { items.contains { $0.isSelected && $0.isDownloadReady } }
  var hasClipboardSuggestion: Bool { !detectedClipboardURLs.isEmpty }

  func checkClipboard() {
    guard clipboardDetectionEnabled, DesktopPlatform.shared.isApplicationActive,
      let text = DesktopPlatform.shared.clipboardText()
    else { return }
    let newValues = clipboardSession.freshMediaURLs(
      from: text, existingURLs: LinkURLParser.urls(from: input))
    guard !newValues.isEmpty else { return }
    detectedClipboardURLs = newValues
  }

  func analyzeClipboardSuggestion() {
    guard !detectedClipboardURLs.isEmpty else { return }
    input = detectedClipboardURLs.map(\.absoluteString).joined(separator: "\n")
    detectedClipboardURLs = []
    analyzeAll()
  }

  func ignoreClipboardSuggestion() {
    detectedClipboardURLs = []
  }

  func disableClipboardDetection() {
    clipboardDetectionEnabled = false
    ignoreClipboardSuggestion()
  }

  func paste() {
    guard
      let text = DesktopPlatform.shared.clipboardText()?.trimmingCharacters(
        in: .whitespacesAndNewlines), !text.isEmpty
    else { return }
    input = text
  }

  func chooseFolder() {
    if let value = DesktopPlatform.shared.chooseDirectory(
      prompt: tr("settings.chooseDownloadFolder"))
    {
      downloadRoot = value
    }
  }

  func analyzeAll() {
    analysisTask?.cancel()
    let rawLines = input.split(whereSeparator: \.isNewline).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    guard !rawLines.isEmpty else {
      items = []
      statusKey = "link.invalidURL"
      return
    }
    items = Array(rawLines.prefix(25)).map { LinkDownloaderItem(rawURL: $0) }
    isAnalyzing = true
    statusKey = "link.analyzing"
    let snapshot = items
    let analyzer = service
    analysisTask = Task { [weak self] in
      guard let self else { return }
      for start in stride(from: 0, to: snapshot.count, by: 2) {
        guard !Task.isCancelled else { return }
        let end = min(start + 2, snapshot.count)
        await withTaskGroup(of: (UUID, Result<LinkMediaAnalysis, Error>).self) { group in
          for item in snapshot[start..<end] {
            group.addTask {
              guard let url = LinkURLParser.urls(from: item.rawURL).first else {
                return (item.id, .failure(ProviderError.unsupported))
              }
              do { return (item.id, .success(try await analyzer.analyze(sourceURL: url))) } catch {
                return (item.id, .failure(error))
              }
            }
          }
          for await (id, result) in group {
            guard !Task.isCancelled,
              let index = self.items.firstIndex(where: { $0.id == id })
            else { continue }
            switch result {
            case .success(let analysis):
              self.items[index].analysis = analysis
              self.items[index].quality = analysis.availableQualities.first ?? .best
              self.items[index].subtitleLanguage = analysis.subtitleLanguages.first ?? ""
              self.items[index].clipEnd = analysis.duration.map(TimecodeParser.string) ?? ""
            case .failure(let error):
              self.items[index].errorKey = Self.errorKey(error)
              await AppLogger.shared.write(
                provider: .linkDownloader, requestType: "link analysis", error: error)
            }
          }
        }
      }
      guard !Task.isCancelled else { return }
      self.isAnalyzing = false
      self.statusKey =
        self.items.contains(where: \.isReady) ? "link.analysisComplete" : "link.noneAnalyzed"
    }
  }

  func downloadSelected(downloads: DownloadManager) {
    for item in items where item.isSelected && item.isDownloadReady {
      guard let analysis = item.analysis else { continue }
      let asset = analysis.mediaAsset(
        quality: item.quality, downloadSubtitles: item.downloadSubtitles,
        subtitleLanguage: item.subtitleLanguage.nilIfEmpty, outputPreset: item.outputPreset,
        clipRange: item.scope == .clip ? item.clipRange : nil)
      downloads.start(
        asset: asset, projectID: nil, projectName: tr("common.uncategorized"),
        destinationRoot: downloadRoot)
    }
  }

  func cancelAnalysis() {
    analysisTask?.cancel()
    analysisTask = nil
    isAnalyzing = false
    statusKey = "search.stopped"
  }

  nonisolated static func errorKey(_ error: Error) -> String {
    guard let value = error as? ProviderError else { return "link.downloadUnavailable" }
    switch value {
    case .unsupported: return "link.unsupportedURL"
    case .videoUnavailable, .notFound: return "link.mediaUnavailable"
    case .temporarilyBlocked, .missingAPIKey, .invalidAPIKey: return "link.signInRequired"
    case .regionalRestriction: return "link.regionRestricted"
    case .rateLimited: return "link.rateLimited"
    case .externalToolUnavailable: return "link.toolUnavailable"
    case .cancelled: return "error.cancelled"
    default: return "link.downloadUnavailable"
    }
  }
}
