import SwiftUI

private struct DraftSegment: Identifiable {
  enum Status {
    case waiting, searching
    case found(Int)
    var text: String {
      switch self {
      case .waiting: tr("script.waiting")
      case .searching: tr("script.searching")
      case .found(let count): tr("script.found", count)
      }
    }
  }
  let id = UUID()
  var index: Int
  var text: String
  var keyword: String
  var results: [MediaAsset] = []
  var status: Status = .waiting
}

struct ScriptSearchView: View {
  @EnvironmentObject private var store: DataStore
  @EnvironmentObject private var localization: LocalizationManager
  @State private var script = ""
  @State private var projectID: UUID?
  @State private var segments: [DraftSegment] = []
  @State private var batchTask: Task<Void, Never>?
  @State private var isSearching = false
  @State private var progress = 0

  var body: some View {
    let _ = localization.language
    VStack(spacing: 0) {
      HStack {
        Text(tr("script.title")).font(.largeTitle.bold())
        Spacer()
        Picker(tr("script.project"), selection: $projectID) {
          Text(tr("common.uncategorized")).tag(Optional<UUID>.none)
          ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
        }.id(localization.language).frame(width: 220)
      }.padding()
      Divider()
      if segments.isEmpty { editor } else { segmentList }
    }
    .onDisappear { batchTask?.cancel() }
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(tr("script.paste")).font(.headline)
      TextEditor(text: $script).font(.body).padding(10).background(
        .quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
      Text(tr("script.help")).font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button(tr("script.analyze")) { analyze() }.buttonStyle(.borderedProminent).disabled(
          script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24)
  }

  private var segmentList: some View {
    VStack(spacing: 0) {
      HStack {
        Button(tr("script.back")) {
          batchTask?.cancel()
          segments = []
          isSearching = false
        }
        Text(tr("script.segmentCount", segments.count)).foregroundStyle(.secondary)
        Spacer()
        if isSearching {
          ProgressView(value: Double(progress), total: Double(max(segments.count, 1))).frame(
            width: 180)
          Text(tr("script.searchingProgress", progress, segments.count))
          Button(tr("common.stop")) {
            batchTask?.cancel()
            isSearching = false
          }
        } else {
          Button(tr("script.searchAll")) { searchAll() }.buttonStyle(.borderedProminent)
        }
      }.padding()
      Divider()
      ScrollView {
        LazyVStack(spacing: 14) {
          ForEach($segments) { $segment in
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text(tr("script.shot", segment.index)).font(.headline)
                Spacer()
                Text(segment.status.text).font(.caption).foregroundStyle(.secondary)
                Button(tr("script.searchFootage")) { searchOne(segment.id) }
              }
              TextEditor(text: $segment.text).frame(height: 62).padding(6).background(
                .quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
              HStack {
                Text(tr("script.searchKeyword")).foregroundStyle(.secondary)
                TextField(tr("script.keywordPlaceholder"), text: $segment.keyword).textFieldStyle(
                  .roundedBorder)
              }
              if !segment.results.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 12) {
                    ForEach(segment.results.prefix(6)) { asset in
                      MediaAssetCard(
                        asset: asset, projectID: projectID, segmentIndex: segment.index
                      ) { PreviewWindowManager.shared.show($0) }.frame(width: 270)
                    }
                  }
                }
              }
            }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(
              RoundedRectangle(cornerRadius: 10).stroke(.separator))
          }
        }.padding(16)
      }
    }
  }

  private func analyze() {
    let parts = KeywordEngine.splitScript(script)
    segments = parts.enumerated().map { index, text in
      let keyword =
        KeywordEngine.keywords(for: text).first(where: { !KeywordEngine.containsChinese($0.text) })?
        .text ?? KeywordEngine.keywords(for: text).first?.text ?? text
      return DraftSegment(index: index + 1, text: text, keyword: keyword)
    }
    if let projectID, let project = store.projects.first(where: { $0.id == projectID }) {
      var updated = project
      updated.script = script
      store.updateProject(updated)
    }
    persistSegments()
  }

  private func searchOne(_ id: UUID) {
    guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
    let keyword = segments[index].keyword
    segments[index].status = .searching
    Task {
      let found = await BatchSearchService.search(keyword)
      await MainActor.run {
        if let current = segments.firstIndex(where: { $0.id == id }) {
          segments[current].results = found
          segments[current].status = .found(found.count)
        }
      }
    }
  }

  private func searchAll() {
    batchTask?.cancel()
    isSearching = true
    progress = 0
    let snapshots = segments.enumerated().map { ($0.offset, $0.element.id, $0.element.keyword) }
    batchTask = Task {
      await withTaskGroup(of: (Int, UUID, [MediaAsset]).self) { group in
        var next = 0
        func addNext() {
          guard next < snapshots.count else { return }
          let item = snapshots[next]
          next += 1
          group.addTask { (item.0, item.1, await BatchSearchService.search(item.2)) }
        }
        for _ in 0..<min(3, snapshots.count) { addNext() }
        for await (_, id, assets) in group {
          if Task.isCancelled {
            group.cancelAll()
            break
          }
          await MainActor.run {
            if let current = segments.firstIndex(where: { $0.id == id }) {
              segments[current].results = assets
              segments[current].status = .found(assets.count)
            }
            progress += 1
          }
          addNext()
        }
      }
      await MainActor.run {
        isSearching = false
        persistSegments()
      }
    }
  }

  private func persistSegments() {
    let values = segments.map {
      ScriptSegmentRecord(
        projectID: projectID, index: $0.index, text: $0.text,
        keywords: [SearchKeyword(text: $0.keyword)])
    }
    store.replaceSegments(projectID: projectID, values: values)
  }
}

enum BatchSearchService {
  static func search(_ keyword: String) async -> [MediaAsset] {
    let providers: [any MediaProvider] = [
      PexelsProvider(apiKey: KeychainService.read(.pexels)),
      PixabayProvider(apiKey: KeychainService.read(.pixabay)), WikimediaProvider(),
      InternetArchiveProvider(), YouTubeProvider(apiKey: KeychainService.read(.youtube)),
    ]
    .filter { AppSettings.enabledProviders.contains($0.info.id) }
    let request = SearchRequest(query: keyword, mediaType: .video, pageSize: 5)
    let batches = await withTaskGroup(of: [MediaAsset].self, returning: [[MediaAsset]].self) {
      group in
      for provider in providers { group.addTask { (try? await provider.search(request)) ?? [] } }
      var values: [[MediaAsset]] = []
      for await result in group { values.append(result) }
      return values
    }
    var seen = Set<String>()
    return batches.flatMap { $0 }.filter { seen.insert($0.stableID).inserted }.prefix(24).map { $0 }
  }
}
