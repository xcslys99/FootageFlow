import SwiftUI
import Translation

struct QuickSearchView: View {
    @EnvironmentObject private var viewModel: SearchViewModel
    @EnvironmentObject private var store: DataStore
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var pendingTranslation = ""
    @State private var showHistory = false

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            if viewModel.isSearching { ProgressView().progressViewStyle(.linear) }
            statusArea
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(viewModel.filteredAssets) { asset in
                        MediaAssetCard(asset: asset, projectID: viewModel.currentProjectID, segmentIndex: nil) { PreviewWindowManager.shared.show($0) }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("快速搜索")
        .toolbar {
            ToolbarItemGroup {
                Button { showHistory = true } label: { Label("搜索历史", systemImage: "clock.arrow.circlepath") }
                Button { viewModel.search(forceRefresh: true) } label: { Label("刷新搜索", systemImage: "arrow.clockwise") }.disabled(viewModel.isSearching || viewModel.keywords.isEmpty)
            }
        }
        .sheet(isPresented: $showHistory) { SearchHistoryView(onUse: useHistory) }
        .onAppear { viewModel.selectedProviders = AppSettings.enabledProviders }
        .translationTask(translationConfiguration) { session in
            guard !pendingTranslation.isEmpty else { return }
            do {
                let response = try await session.translate(pendingTranslation)
                await MainActor.run { viewModel.acceptTranslation(response.targetText); viewModel.search() }
            } catch {
                await MainActor.run { viewModel.search() }
            }
            await MainActor.run { pendingTranslation = "" }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                TextField("例如：2001年阿根廷银行挤兑", text: $viewModel.query)
                    .textFieldStyle(.plain).font(.title3)
                    .onSubmit { beginSearch() }
                if viewModel.isSearching { Button("停止") { viewModel.stop() }.buttonStyle(.bordered) }
                else { Button("搜索素材") { beginSearch() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command) }
            }
            .padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .top) {
                Text("当前搜索词：").foregroundStyle(.secondary).padding(.top, 4)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach($viewModel.keywords) { $keyword in
                        HStack(spacing: 6) {
                            Toggle("", isOn: $keyword.isEnabled).labelsHidden()
                            TextField("关键词", text: $keyword.text).textFieldStyle(.roundedBorder)
                            Button { viewModel.removeKeyword(keyword.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    Button { viewModel.addKeyword() } label: { Label("添加关键词", systemImage: "plus") }.buttonStyle(.plain)
                }
            }
            filters
        }
        .padding(16)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("类型", selection: $viewModel.mediaType) { ForEach(MediaType.allCases) { Text($0.label).tag($0) } }.frame(width: 150)
                Picker("方向", selection: $viewModel.orientation) { ForEach(AssetOrientation.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) } }.frame(width: 150)
                Picker("清晰度", selection: $viewModel.resolution) { ForEach(ResolutionFilter.allCases) { Text($0.label).tag($0) } }.frame(width: 165)
                Picker("时长", selection: $viewModel.duration) { ForEach(DurationFilter.allCases) { Text($0.label).tag($0) } }.frame(width: 160)
                Picker("排序", selection: $viewModel.sort) { ForEach(SearchSort.allCases) { Text($0.label).tag($0) } }.frame(width: 150)
                Spacer()
                Picker("项目", selection: $viewModel.currentProjectID) {
                    Text("未分类").tag(Optional<UUID>.none)
                    ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
                }.frame(width: 210)
            }
            HStack(spacing: 12) {
                Text("来源").foregroundStyle(.secondary)
                ForEach(ProviderID.allCases) { provider in
                    Toggle(provider.displayName, isOn: Binding(get: { viewModel.selectedProviders.contains(provider) }, set: { enabled in if enabled { viewModel.selectedProviders.insert(provider) } else { viewModel.selectedProviders.remove(provider) }; AppSettings.enabledProviders = viewModel.selectedProviders })).toggleStyle(.checkbox)
                }
                Divider().frame(height: 18)
                Picker("授权", selection: $viewModel.licenseFilter) { ForEach(LicenseFilter.allCases) { Text($0.label).tag($0) } }.frame(width: 180)
            }
        }
    }

    @ViewBuilder private var statusArea: some View {
        if !viewModel.providerErrors.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.providerErrors.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { provider in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(viewModel.providerErrors[provider] ?? "搜索失败").lineLimit(1)
                            Button("重试") { viewModel.search(only: provider) }.buttonStyle(.link)
                        }.padding(.horizontal, 9).padding(.vertical, 5).background(.orange.opacity(0.1), in: Capsule())
                    }
                }.padding(.horizontal, 16).padding(.top, 8)
            }
        }
        HStack { Text(viewModel.statusText).foregroundStyle(.secondary); Spacer(); Text("显示 \(viewModel.filteredAssets.count) 条").foregroundStyle(.secondary) }
            .font(.caption).padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func beginSearch() {
        viewModel.prepareKeywords()
        if KeywordEngine.containsChinese(viewModel.query) {
            pendingTranslation = viewModel.query
            if translationConfiguration == nil {
                translationConfiguration = TranslationSession.Configuration(source: Locale.Language(identifier: "zh-Hans"), target: Locale.Language(identifier: "en"))
            } else { translationConfiguration?.invalidate() }
        } else { viewModel.search() }
    }

    private func useHistory(_ history: SearchHistoryRecord) {
        viewModel.query = history.originalQuery
        viewModel.keywords = history.keywords.map { SearchKeyword(text: $0) }
        viewModel.currentProjectID = history.projectID
        showHistory = false
        viewModel.search()
    }
}
