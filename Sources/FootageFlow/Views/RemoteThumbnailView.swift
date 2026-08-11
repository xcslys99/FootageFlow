import AppKit
import SwiftUI

@MainActor
private final class RemoteThumbnailModel: ObservableObject {
  enum Phase {
    case loading
    case success(NSImage)
    case failure
  }

  @Published var phase: Phase = .loading

  func load(candidates: [URL], provider: ProviderID?, forceRetry: Bool) async {
    phase = .loading
    guard !candidates.isEmpty else {
      phase = .failure
      return
    }
    for url in candidates {
      do {
        let payload = try await ThumbnailPipeline.shared.load(
          url, provider: provider, forceRetry: forceRetry)
        try Task.checkCancellation()
        if let image = NSImage(data: payload.data), image.isValid {
          phase = .success(image)
          return
        }
        await ThumbnailPipeline.shared.recordDecodeFailure(for: url, provider: provider)
      } catch is CancellationError {
        return
      } catch {
        continue
      }
    }
    if !Task.isCancelled { phase = .failure }
  }
}

struct RemoteThumbnailView: View {
  let candidates: [URL]
  var provider: ProviderID? = nil
  var fallbackSystemImage = "photo"
  var showsRetryLabel = false

  @StateObject private var model = RemoteThumbnailModel()
  @State private var retryGeneration = 0

  private var identity: String {
    candidates.map(\.absoluteString).joined(separator: "|") + "#\(retryGeneration)"
  }

  var body: some View {
    ZStack {
      Color.secondary.opacity(0.08)
      switch model.phase {
      case .loading:
        ProgressView().controlSize(.small).accessibilityLabel(tr("common.loading"))
      case .success(let image):
        Image(nsImage: image).resizable().scaledToFill()
      case .failure:
        VStack(spacing: 5) {
          Image(systemName: fallbackSystemImage)
          Text(tr("media.thumbnailUnavailable")).font(.caption2).lineLimit(1)
          Button {
            retryGeneration += 1
          } label: {
            if showsRetryLabel {
              Label(tr("media.retryThumbnail"), systemImage: "arrow.clockwise")
            } else {
              Image(systemName: "arrow.clockwise")
            }
          }
          .buttonStyle(.plain)
          .help(tr("media.retryThumbnail"))
          .accessibilityLabel(tr("media.retryThumbnail"))
        }.foregroundStyle(.secondary)
      }
    }
    .clipped()
    .task(id: identity) {
      await model.load(
        candidates: candidates, provider: provider, forceRetry: retryGeneration > 0)
    }
  }
}
