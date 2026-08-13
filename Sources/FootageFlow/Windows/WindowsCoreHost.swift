#if os(Windows)
  import Foundation

  private struct WindowsCoreRequest: Decodable {
    let id: String
    let action: String
    var query: String? = nil
    var mediaType: String? = nil
    var orientation: String? = nil
    var resolution: String? = nil
    var duration: String? = nil
    var yearFrom: Int? = nil
    var yearTo: Int? = nil
    var downloadableOnly: Bool? = nil
    var pageSize: Int? = nil
    var continuation: ProviderContinuation? = nil
    var providerIDs: [String]? = nil
    var apiKeys: [String: String]? = nil
    var language: String? = nil
    var asset: MediaAsset? = nil
    var assets: [MediaAsset]? = nil
    var relevanceMode: String? = nil
    var mediaPath: String? = nil
    var projectName: String? = nil
    var projectID: String? = nil
    var projectScript: String? = nil
    var recordID: String? = nil
    var localPath: String? = nil
    var keywords: [String]? = nil
    var keywordDetails: [SearchKeyword]? = nil
    var resultCount: Int? = nil
    var segmentIndex: Int? = nil
    var externalToolOutputBase64: String? = nil
    var feedbackDestination: FeedbackDestination? = nil
    var smartExpansion: Bool? = nil
  }

  private struct WindowsCoreResponse: Encodable {
    let id: String
    let success: Bool
    var version = FootageFlowVersion.current
    var platform = "windows"
    var providers: [WindowsProviderDescriptor]? = nil
    var providerBatches: [WindowsProviderBatch]? = nil
    var assets: [MediaAsset]? = nil
    var keywords: [SearchKeyword]? = nil
    var segments: [String]? = nil
    var database: PersistentDatabase? = nil
    var project: ProjectRecord? = nil
    var fileName: String? = nil
    var errorCode: String? = nil
    var errorMessage: String? = nil
    var text: String? = nil
    var updateStatus: String? = nil
    var release: AppRelease? = nil
  }

  private struct WindowsProviderDescriptor: Encodable {
    let id: ProviderID
    let displayName: String
    let mode: ProviderMode
    let requiresAPIKey: Bool
    let capabilities: ProviderCapabilities

    init(_ info: ProviderInfo) {
      id = info.id
      displayName = info.displayName
      mode = info.mode
      requiresAPIKey = info.requiresAPIKey
      capabilities = info.capabilities
    }
  }

  private struct WindowsProviderBatch: Encodable {
    let provider: ProviderID
    let displayName: String
    let mode: ProviderMode
    let state: ProviderRuntimeState
    let assets: [MediaAsset]
    var continuation: ProviderContinuation? = nil
    var totalResults: Int? = nil
    var errorCode: String? = nil
  }

  @main
  enum WindowsCoreHost {
    static func main() async {
      if CommandLine.arguments.contains("--core-self-test") {
        write(
          WindowsCoreResponse(
            id: "self-test", success: true,
            providers: ProviderID.searchCases.map {
              WindowsProviderDescriptor(ProviderFactory.make($0, apiKey: "").info)
            }))
        return
      }

      guard CommandLine.arguments.contains("--core-request") else {
        write(
          WindowsCoreResponse(
            id: "startup", success: false, errorCode: "invalidArguments",
            errorMessage: "Use --core-request and provide one JSON request on standard input."))
        return
      }

      do {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let request = try decoder.decode(WindowsCoreRequest.self, from: data)
        configureLanguage(request.language)
        write(await handle(request))
      } catch {
        write(
          WindowsCoreResponse(
            id: "unknown", success: false, errorCode: "invalidRequest",
            errorMessage: "The core request could not be read."))
      }
    }

    private static func handle(_ request: WindowsCoreRequest) async -> WindowsCoreResponse {
      switch request.action {
      case "health":
        return WindowsCoreResponse(
          id: request.id, success: true,
          providers: selectedProviderIDs(request).map {
            WindowsProviderDescriptor(provider($0, request: request).info)
          })
      case "feedbackURL":
        guard let destination = request.feedbackDestination else {
          return WindowsCoreResponse(
            id: request.id, success: false, errorCode: "invalidRequest",
            errorMessage: "A feedback destination is required.")
        }
        return WindowsCoreResponse(
          id: request.id, success: true,
          text: FeedbackURLs.url(
            for: destination,
            context: FeedbackContext(
              platform: "Windows", osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
              language: request.language ?? "en")
          ).absoluteString)
      case "checkUpdate":
        return await checkUpdate(request)
      case "search":
        return await search(request)
      case "rankAssets":
        guard let query = nonempty(request.query), let assets = request.assets else {
          return WindowsCoreResponse(
            id: request.id, success: false, errorCode: "invalidRequest",
            errorMessage: "A query and candidate assets are required.")
        }
        let mode = SearchRelevanceMode(rawValue: request.relevanceMode ?? "") ?? .balanced
        return WindowsCoreResponse(
          id: request.id, success: true,
          assets: SearchRelevanceEngine.rank(
            assets, query: query, mode: mode, supportingQueries: request.keywords ?? [],
            inputLanguage: request.keywordDetails?.first(where: { $0.origin == .input })?.language,
            interfaceLanguage: request.language.flatMap(AppLanguage.init(rawValue:)) ?? .english))
      case "providerTest":
        return await providerTest(request)
      case "keywords":
        guard let query = nonempty(request.query) else { return missingQuery(request.id) }
        return WindowsCoreResponse(
          id: request.id, success: true,
          keywords: KeywordEngine.keywords(
            for: query, smartExpansion: request.smartExpansion ?? true,
            interfaceLanguage: request.language.flatMap(AppLanguage.init(rawValue:)) ?? .english))
      case "splitScript":
        guard let query = nonempty(request.query) else { return missingQuery(request.id) }
        return WindowsCoreResponse(
          id: request.id, success: true, segments: KeywordEngine.splitScript(query))
      case "mapYTDLPSearch":
        return mapYTDLPSearch(request)
      case "formatSource":
        guard let asset = request.asset else { return invalidRecordID(request.id) }
        return WindowsCoreResponse(
          id: request.id, success: true, text: AttributionFormatter.source(for: asset))
      case "formatAttribution":
        guard let asset = request.asset else { return invalidRecordID(request.id) }
        return WindowsCoreResponse(
          id: request.id, success: true, text: AttributionFormatter.attribution(for: asset))
      case "databaseSnapshot", "addProject", "deleteProject", "updateProject",
        "toggleFavorite", "addFavorite", "addHistory", "deleteHistory", "clearHistory",
        "addDownload",
        "deleteDownload":
        return database(request)
      case "suggestFileName":
        guard let asset = request.asset else {
          return WindowsCoreResponse(
            id: request.id, success: false, errorCode: "missingAsset",
            errorMessage: "Select an asset first.")
        }
        return WindowsCoreResponse(
          id: request.id, success: true,
          fileName: FileNameSanitizer.fileName(asset: asset, index: request.segmentIndex))
      case "writeSidecar":
        return writeSidecar(request)
      default:
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: "unsupportedAction",
          errorMessage: "Unsupported core action.")
      }
    }

    private static func checkUpdate(_ request: WindowsCoreRequest) async -> WindowsCoreResponse {
      do {
        switch try await AppUpdateService.shared.check() {
        case .upToDate:
          return WindowsCoreResponse(id: request.id, success: true, updateStatus: "upToDate")
        case .updateAvailable(let release):
          return WindowsCoreResponse(
            id: request.id, success: true, updateStatus: "available", release: release)
        }
      } catch let error as AppUpdateCheckError {
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: error.code,
          errorMessage: "Unable to check for updates.")
      } catch {
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: "invalidResponse",
          errorMessage: "Unable to check for updates.")
      }
    }

    private static func database(_ request: WindowsCoreRequest) -> WindowsCoreResponse {
      let store = PersistentStore()
      switch request.action {
      case "databaseSnapshot":
        break
      case "addProject":
        let project = store.addProject(name: request.projectName ?? "")
        return WindowsCoreResponse(
          id: request.id, success: true, database: store.database, project: project)
      case "deleteProject":
        guard let id = uuid(request.projectID) else { return invalidRecordID(request.id) }
        store.deleteProject(id: id)
      case "updateProject":
        guard let id = uuid(request.projectID),
          var project = store.projects.first(where: { $0.id == id })
        else { return invalidRecordID(request.id) }
        if let name = request.projectName { project.name = name }
        if let script = request.projectScript { project.script = script }
        store.updateProject(project)
      case "toggleFavorite":
        guard let asset = request.asset else {
          return WindowsCoreResponse(
            id: request.id, success: false, errorCode: "missingAsset",
            errorMessage: "Select an asset first.")
        }
        store.toggleFavorite(
          asset: asset, projectID: uuid(request.projectID), segmentIndex: request.segmentIndex)
      case "addFavorite":
        guard let asset = request.asset else { return invalidRecordID(request.id) }
        store.addFavorite(
          asset: asset, projectID: uuid(request.projectID), segmentIndex: request.segmentIndex)
      case "addHistory":
        guard let query = nonempty(request.query) else { return missingQuery(request.id) }
        let providers = Set((request.providerIDs ?? []).compactMap(ProviderID.init(rawValue:)))
        store.addHistory(
          SearchHistoryRecord(
            originalQuery: query, keywords: request.keywords ?? [], providers: providers,
            projectID: uuid(request.projectID), resultCount: max(0, request.resultCount ?? 0),
            keywordDetails: request.keywordDetails))
      case "deleteHistory":
        guard let id = uuid(request.recordID) else { return invalidRecordID(request.id) }
        store.deleteHistory(id: id)
      case "clearHistory":
        store.clearHistory()
      case "addDownload":
        guard let asset = request.asset, let path = nonempty(request.localPath) else {
          return WindowsCoreResponse(
            id: request.id, success: false, errorCode: "invalidDownloadRecord",
            errorMessage: "The downloaded asset and local path are required.")
        }
        store.addDownload(
          DownloadRecord(
            asset: asset, fileURL: URL(fileURLWithPath: path),
            projectID: uuid(request.projectID)))
      case "deleteDownload":
        guard let id = uuid(request.recordID) else { return invalidRecordID(request.id) }
        store.deleteDownloadRecord(id: id)
      default:
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: "unsupportedAction",
          errorMessage: "Unsupported database action.")
      }
      return WindowsCoreResponse(id: request.id, success: true, database: store.database)
    }

    private static func search(_ request: WindowsCoreRequest) async -> WindowsCoreResponse {
      guard let query = nonempty(request.query) else { return missingQuery(request.id) }
      let searchRequest = SearchRequest(
        query: query,
        mediaType: MediaType(rawValue: request.mediaType ?? "") ?? .video,
        orientation: AssetOrientation(rawValue: request.orientation ?? "") ?? .all,
        resolution: ResolutionFilter(rawValue: request.resolution ?? "") ?? .all,
        duration: DurationFilter(rawValue: request.duration ?? "") ?? .all,
        yearFrom: request.yearFrom, yearTo: request.yearTo,
        downloadableOnly: request.downloadableOnly ?? false,
        pageSize: max(1, min(request.pageSize ?? 16, 50)))
      let ids = selectedProviderIDs(request)
      let batches = await withTaskGroup(of: WindowsProviderBatch.self) { group in
        for id in ids {
          let selectedProvider = provider(id, request: request)
          group.addTask {
            do {
              let page = try await selectedProvider.searchPage(
                searchRequest, continuation: request.continuation)
              return successBatch(selectedProvider.info, page: page)
            } catch {
              return failureBatch(selectedProvider.info, error: error)
            }
          }
        }
        var values: [WindowsProviderBatch] = []
        for await value in group { values.append(value) }
        return values.sorted { providerOrder($0.provider) < providerOrder($1.provider) }
      }
      return WindowsCoreResponse(id: request.id, success: true, providerBatches: batches)
    }

    private static func providerTest(_ request: WindowsCoreRequest) async -> WindowsCoreResponse {
      guard let id = selectedProviderIDs(request).first else {
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: "invalidProvider",
          errorMessage: "Select one valid provider.")
      }
      let selectedProvider = provider(id, request: request)
      do {
        try await selectedProvider.testConnection()
        return WindowsCoreResponse(
          id: request.id, success: true,
          providerBatches: [
            successBatch(
              selectedProvider.info, page: ProviderPage(assets: [], continuation: nil))
          ])
      } catch {
        return WindowsCoreResponse(
          id: request.id, success: false,
          providerBatches: [failureBatch(selectedProvider.info, error: error)],
          errorCode: errorCode(error), errorMessage: userMessage(error))
      }
    }

    private static func mapYTDLPSearch(_ request: WindowsCoreRequest) -> WindowsCoreResponse {
      guard let query = nonempty(request.query),
        let encoded = request.externalToolOutputBase64,
        let data = Data(base64Encoded: encoded)
      else {
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: "invalidExternalToolOutput",
          errorMessage: "The external tool output was missing or invalid.")
      }
      do {
        let assets = try YouTubeYTDLPProvider.assets(fromJSON: data, query: query)
        return WindowsCoreResponse(
          id: request.id, success: true,
          assets: Array(assets.prefix(max(1, min(request.pageSize ?? 12, 12)))))
      } catch {
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: errorCode(error),
          errorMessage: userMessage(error))
      }
    }

    private static func writeSidecar(_ request: WindowsCoreRequest) -> WindowsCoreResponse {
      guard let asset = request.asset, let path = nonempty(request.mediaPath) else {
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: "invalidSidecarRequest",
          errorMessage: "The downloaded asset and local path are required.")
      }
      let mediaURL = URL(fileURLWithPath: path)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: mediaURL.path, isDirectory: &isDirectory),
        !isDirectory.boolValue
      else {
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: "downloadedFileMissing",
          errorMessage: "The downloaded file no longer exists.")
      }
      do {
        try SourceSidecar.write(
          asset: asset, mediaURL: mediaURL, projectName: request.projectName,
          segmentIndex: request.segmentIndex)
        return WindowsCoreResponse(id: request.id, success: true)
      } catch {
        return WindowsCoreResponse(
          id: request.id, success: false, errorCode: "sidecarWriteFailed",
          errorMessage: "The source information files could not be written.")
      }
    }

    private static func selectedProviderIDs(_ request: WindowsCoreRequest) -> [ProviderID] {
      guard let values = request.providerIDs else { return ProviderID.searchCases }
      return values.compactMap(ProviderID.init(rawValue:)).reduce(into: []) { result, value in
        if !result.contains(value) { result.append(value) }
      }
    }

    private static func provider(_ id: ProviderID, request: WindowsCoreRequest)
      -> any MediaProvider
    {
      ProviderFactory.make(id, apiKey: request.apiKeys?[id.rawValue] ?? "")
    }

    private static func successBatch(_ info: ProviderInfo, page: ProviderPage)
      -> WindowsProviderBatch
    {
      let availability: ProviderAvailability =
        switch info.mode {
        case .officialAPI: .apiConnected
        case .publicAPI: .publicAPI
        case .limited: .limitedMode
        case .directSearch, .ytDLP: .bestEffort
        case .publicInterface: .available
        }
      return WindowsProviderBatch(
        provider: info.id, displayName: info.displayName, mode: info.mode,
        state: ProviderRuntimeState(
          availability: availability, message: nil, mode: info.mode),
        assets: page.assets, continuation: page.continuation, totalResults: page.totalResults)
    }

    private static func failureBatch(_ info: ProviderInfo, error: Error) -> WindowsProviderBatch {
      var state = ProviderRuntimeState.from(error: error)
      state.mode = info.mode
      return WindowsProviderBatch(
        provider: info.id, displayName: info.displayName, mode: info.mode, state: state,
        assets: [], errorCode: errorCode(error))
    }

    private static func errorCode(_ error: Error) -> String {
      guard let error = error as? ProviderError else { return "unknown" }
      return switch error {
      case .missingAPIKey: "missingAPIKey"
      case .invalidAPIKey: "invalidAPIKey"
      case .noNetwork: "noNetwork"
      case .rateLimited: "rateLimited"
      case .notFound: "notFound"
      case .serverUnavailable: "serverUnavailable"
      case .invalidResponse: "invalidResponse"
      case .temporarilyBlocked: "temporarilyBlocked"
      case .externalToolUnavailable: "externalToolUnavailable"
      case .videoUnavailable: "videoUnavailable"
      case .regionalRestriction: "regionalRestriction"
      case .unsupported: "unsupported"
      case .limitedMode: "limitedMode"
      case .cancelled: "cancelled"
      case .message: "requestFailed"
      }
    }

    private static func userMessage(_ error: Error) -> String {
      (error as? ProviderError)?.errorDescription ?? tr("error.requestFailed")
    }

    private static func missingQuery(_ id: String) -> WindowsCoreResponse {
      WindowsCoreResponse(
        id: id, success: false, errorCode: "missingQuery",
        errorMessage: tr("search.enterQuery"))
    }

    private static func nonempty(_ value: String?) -> String? {
      let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return clean.isEmpty ? nil : clean
    }

    private static func uuid(_ value: String?) -> UUID? {
      value.flatMap(UUID.init(uuidString:))
    }

    private static func invalidRecordID(_ id: String) -> WindowsCoreResponse {
      WindowsCoreResponse(
        id: id, success: false, errorCode: "invalidRecordID",
        errorMessage: "The selected record is no longer available.")
    }

    private static func providerOrder(_ id: ProviderID) -> Int {
      ProviderID.searchCases.firstIndex(of: id) ?? Int.max
    }

    private static func configureLanguage(_ value: String?) {
      CoreLocalization.language = AppLanguage(rawValue: value ?? "") ?? .english
    }

    private static func write(_ response: WindowsCoreResponse) {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      encoder.dateEncodingStrategy = .iso8601
      guard let data = try? encoder.encode(response) else { return }
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data([0x0A]))
    }
  }
#endif
