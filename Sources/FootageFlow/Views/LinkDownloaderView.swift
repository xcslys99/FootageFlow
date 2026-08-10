import SwiftUI

struct LinkDownloaderView: View {
  @EnvironmentObject private var downloads: DownloadManager
  @StateObject private var viewModel = LinkDownloaderViewModel()
  let openDownloads: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(tr("nav.linkDownloader")).font(.largeTitle.bold())
      Text(tr("link.tagline")).foregroundStyle(.secondary)
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
    }.padding(24)
  }

  @ViewBuilder
  private func itemCard(_ item: Binding<LinkDownloaderItem>) -> some View {
    let value = item.wrappedValue
    HStack(alignment: .top, spacing: 14) {
      Toggle("", isOn: item.isSelected).labelsHidden().disabled(!value.isReady)
      Group {
        if let thumbnail = value.analysis?.thumbnailURL {
          AsyncImage(url: thumbnail) { phase in
            if let image = phase.image {
              image.resizable().scaledToFill()
            } else {
              Rectangle().fill(.quaternary)
            }
          }
        } else {
          Rectangle().fill(.quaternary).overlay(Image(systemName: "link"))
        }
      }.frame(width: 180, height: 102).clipShape(RoundedRectangle(cornerRadius: 7))
      VStack(alignment: .leading, spacing: 6) {
        Text(value.analysis?.title ?? value.rawURL).font(.headline).lineLimit(2)
        if let analysis = value.analysis {
          Text(
            [analysis.sourceName, analysis.creator, analysis.duration.map(durationText)]
              .compactMap { $0 }.joined(separator: " · ")
          )
          .font(.caption).foregroundStyle(.secondary)
          Text(tr("link.formatsCount", analysis.formats.count)).font(.caption)
          HStack {
            Picker(tr("link.quality"), selection: item.quality) {
              ForEach(analysis.availableQualities) { Text($0.label).tag($0) }
            }.frame(width: 190)
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

  private func durationText(_ value: Double) -> String {
    let seconds = Int(value.rounded())
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}
