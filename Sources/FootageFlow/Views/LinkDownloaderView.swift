import SwiftUI

struct LinkDownloaderView: View {
  @EnvironmentObject private var downloads: DownloadManager
  @StateObject private var viewModel = LinkDownloaderViewModel()
  let openDownloads: () -> Void
  private let clipboardTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(tr("nav.linkDownloader")).font(.largeTitle.bold())
      Text(tr("link.tagline")).foregroundStyle(.secondary)
      if viewModel.hasClipboardSuggestion {
        HStack(spacing: 10) {
          Image(systemName: "doc.on.clipboard.fill").foregroundStyle(.tint)
          Text(
            viewModel.detectedClipboardURLs.count == 1
              ? tr("clipboard.mediaLinkDetected")
              : tr("clipboard.mediaLinksDetected", viewModel.detectedClipboardURLs.count)
          ).fontWeight(.semibold)
          Spacer()
          Button(
            viewModel.detectedClipboardURLs.count == 1
              ? tr("link.analyze") : tr("link.analyzeAll")
          ) { viewModel.analyzeClipboardSuggestion() }
          .buttonStyle(.borderedProminent)
          Button(tr("clipboard.ignore")) { viewModel.ignoreClipboardSuggestion() }
          Menu {
            Button(tr("clipboard.disable"), role: .destructive) {
              viewModel.disableClipboardDetection()
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
        .padding(10)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
      }
      HStack(alignment: .top, spacing: 10) {
        TextEditor(text: $viewModel.input)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 94, maxHeight: 150)
          .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
        VStack {
          Button(tr("link.paste")) { viewModel.paste() }
          Button(viewModel.detectedCount > 1 ? tr("link.analyzeAll") : tr("link.analyze")) {
            viewModel.analyzeAll()
          }.buttonStyle(.borderedProminent).disabled(viewModel.isAnalyzing)
          if viewModel.isAnalyzing {
            Button(tr("common.stop")) { viewModel.cancelAnalysis() }
          }
        }
      }
      HStack {
        Text(tr("link.detectedCount", viewModel.detectedCount)).font(.callout.bold())
        Text(tr(viewModel.statusKey)).foregroundStyle(.secondary)
        Spacer()
        Text(viewModel.downloadRoot.path).lineLimit(1).foregroundStyle(.secondary)
        Button(tr("settings.choose")) { viewModel.chooseFolder() }
        Button(tr("link.downloadSelected")) {
          viewModel.downloadSelected(downloads: downloads)
          openDownloads()
        }.buttonStyle(.borderedProminent).disabled(!viewModel.canDownloadSelected)
      }
      Divider()
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach($viewModel.items) { $item in itemCard($item) }
        }.padding(.vertical, 2)
      }
      Text(tr("link.legalNotice")).font(.caption).foregroundStyle(.secondary)
    }
    .padding(24)
    .onAppear { viewModel.checkClipboard() }
    .onReceive(clipboardTimer) { _ in viewModel.checkClipboard() }
  }

  @ViewBuilder
  private func itemCard(_ item: Binding<LinkDownloaderItem>) -> some View {
    let value = item.wrappedValue
    HStack(alignment: .top, spacing: 14) {
      Toggle("", isOn: item.isSelected).labelsHidden().disabled(!value.isReady)
      RemoteThumbnailView(
        candidates: [value.analysis?.thumbnailURL].compactMap { $0 },
        fallbackSystemImage: "link"
      )
      .frame(width: 180, height: 102).clipShape(RoundedRectangle(cornerRadius: 7))
      VStack(alignment: .leading, spacing: 6) {
        Text(value.analysis?.title ?? value.rawURL).font(.headline).lineLimit(2)
        if let analysis = value.analysis {
          Text(
            [analysis.sourceName, analysis.creator, analysis.duration.map(durationText)]
              .compactMap { $0 }.joined(separator: " · ")
          )
          .font(.caption).foregroundStyle(.secondary)
          Text(tr("link.formatsCount", analysis.formats.count)).font(.caption)
          Picker(tr("link.downloadMode"), selection: item.scope) {
            ForEach(LinkDownloadScope.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 430)
          HStack {
            Picker(tr("link.quality"), selection: item.quality) {
              ForEach(analysis.availableQualities.filter { $0 != .audioOnly }) {
                Text($0.label).tag($0)
              }
            }.frame(width: 190)
            Picker(tr("link.outputFormat"), selection: item.outputPreset) {
              ForEach(EditingOutputPreset.allCases) { Text($0.label).tag($0) }
            }.frame(width: 230)
          }
          if item.scope.wrappedValue == .clip {
            clipControls(item, analysis: analysis)
          }
          HStack {
            if !analysis.subtitleLanguages.isEmpty {
              Toggle(tr("link.subtitles"), isOn: item.downloadSubtitles)
              if item.downloadSubtitles.wrappedValue {
                Picker(tr("link.subtitleLanguage"), selection: item.subtitleLanguage) {
                  ForEach(analysis.subtitleLanguages, id: \.self) { Text($0).tag($0) }
                }.frame(width: 130)
              }
            }
          }
          Button(tr("link.openOriginal")) { DesktopPlatform.shared.open(analysis.originalURL) }
            .buttonStyle(.link)
        } else if let key = value.errorKey {
          Text(tr(key)).foregroundStyle(.red)
          if let url = LinkURLParser.urls(from: value.rawURL).first {
            Button(tr("link.openOriginal")) { DesktopPlatform.shared.open(url) }
          }
        } else if viewModel.isAnalyzing {
          ProgressView().controlSize(.small)
        }
      }
      Spacer()
    }
    .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
  }

  @ViewBuilder
  private func clipControls(
    _ item: Binding<LinkDownloaderItem>, analysis: LinkMediaAnalysis
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        TextField(tr("link.clip.start"), text: item.clipStart).frame(width: 135)
        Text("→").foregroundStyle(.secondary)
        TextField(tr("link.clip.end"), text: item.clipEnd).frame(width: 135)
        if let range = item.wrappedValue.clipRange {
          Text(tr("link.clip.duration", durationText(range.duration)))
            .font(.caption).foregroundStyle(.secondary)
        }
        Button(tr("common.reset")) {
          item.clipStart.wrappedValue = "00:00:00"
          item.clipEnd.wrappedValue = analysis.duration.map(TimecodeParser.string) ?? ""
        }.buttonStyle(.link)
      }
      if let duration = analysis.duration, duration > 0 {
        HStack {
          Text(tr("link.clip.start")).font(.caption).foregroundStyle(.secondary)
          Slider(
            value: Binding(
              get: { min(TimecodeParser.seconds(item.clipStart.wrappedValue) ?? 0, duration) },
              set: { item.clipStart.wrappedValue = TimecodeParser.string($0) }),
            in: 0...duration)
          Text(tr("link.clip.end")).font(.caption).foregroundStyle(.secondary)
          Slider(
            value: Binding(
              get: { min(TimecodeParser.seconds(item.clipEnd.wrappedValue) ?? duration, duration) },
              set: { item.clipEnd.wrappedValue = TimecodeParser.string($0) }),
            in: 0...duration)
        }
      }
      if let key = item.wrappedValue.clipValidationKey {
        Text(tr(key)).font(.caption).foregroundStyle(.red)
      }
    }
  }

  private func durationText(_ value: Double) -> String {
    let seconds = Int(value.rounded())
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}
