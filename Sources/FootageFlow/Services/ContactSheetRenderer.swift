#if os(macOS)
  import AppKit
  import SwiftUI

  @MainActor
  enum ProjectContactSheetRenderer {
    static func pngData(for plan: ContactSheetPlan) async throws -> Data {
      let images = await loadImages(for: plan.items)
      let columns = max(3, min(5, plan.columns))
      let rows = max(1, Int(ceil(Double(plan.items.count) / Double(columns))))
      let cellWidth: CGFloat = 340
      let imageHeight: CGFloat = 191
      let content = ContactSheetDocumentView(
        plan: plan, images: images, columns: columns, imageHeight: imageHeight
      )
      .frame(
        width: CGFloat(columns) * cellWidth + CGFloat(columns - 1) * 22 + 72,
        height: 88 + CGFloat(rows) * (imageHeight + (plan.includeRights ? 94 : 70) + 22) + 50
      )
      .background(Color.white)
      let renderer = ImageRenderer(content: content)
      renderer.scale = 2
      guard let image = renderer.nsImage,
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      else { throw ContactSheetRenderError.unavailable }
      return png
    }

    private static func loadImages(for items: [ContactSheetItem]) async -> [Int: NSImage] {
      await withTaskGroup(of: (Int, Data?).self) { group in
        for item in items {
          group.addTask {
            // The shared thumbnail pipeline consults its cache before using a
            // provider URL. Only after that fails do we access local image
            // data or extract a video frame with FFmpeg.
            if let url = item.thumbnailURL,
              let payload = try? await ThumbnailPipeline.shared.load(url, provider: nil)
            {
              return (item.index, payload.data)
            }
            if let path = item.localPath,
              let data = await localImageData(path: path, duration: item.duration)
            {
              return (item.index, data)
            }
            return (item.index, nil)
          }
        }
        var values: [Int: NSImage] = [:]
        for await (index, data) in group {
          if let data, let image = NSImage(data: data) { values[index] = image }
        }
        return values
      }
    }

    /// Contact sheets never copy media into a project backup. For locally
    /// available video, FFmpeg is only used as a bounded, best-effort frame
    /// reader; thumbnail/original metadata remains the shared source of truth.
    private static func localImageData(path: String, duration: Double?) async -> Data? {
      let url = URL(fileURLWithPath: path)
      let fileExtension = url.pathExtension.lowercased()
      if ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp"].contains(fileExtension) {
        return try? Data(contentsOf: url, options: .mappedIfSafe)
      }
      return await videoFrameData(path: path, duration: duration)
    }

    private static func videoFrameData(path: String, duration: Double?) async -> Data? {
      guard FileManager.default.fileExists(atPath: path),
        let ffmpeg = FFmpegToolLocator.ffmpegURL
      else { return nil }
      let seconds = await frameTimestamp(path: path, knownDuration: duration)
      do {
        let result = try await ProcessExternalToolRunner().run(
          executable: ffmpeg,
          arguments: [
            "-hide_banner", "-loglevel", "error", "-ss", String(format: "%.3f", seconds),
            "-i", path, "-frames:v", "1", "-vf", "scale=680:-2", "-f", "image2pipe",
            "-vcodec", "png", "pipe:1",
          ], timeout: 30)
        return result.exitCode == 0 && !result.standardOutput.isEmpty ? result.standardOutput : nil
      } catch { return nil }
    }

    private static func frameTimestamp(path: String, knownDuration: Double?) async -> Double {
      let duration: Double?
      if let knownDuration {
        duration = knownDuration
      } else {
        duration = await probedDuration(path: path)
      }
      guard let duration, duration.isFinite, duration > 0 else { return 1 }
      // The visual middle is often a title card. A 15% point is a predictable
      // preview while staying within the requested 10–20% range.
      return max(0, duration * 0.15)
    }

    private static func probedDuration(path: String) async -> Double? {
      guard let ffprobe = FFmpegToolLocator.ffprobeURL else { return nil }
      do {
        let result = try await ProcessExternalToolRunner().run(
          executable: ffprobe,
          arguments: [
            "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path,
          ],
          timeout: 15)
        guard result.exitCode == 0 else { return nil }
        return Double(result.outputText.trimmingCharacters(in: .whitespacesAndNewlines))
      } catch { return nil }
    }
  }

  private enum ContactSheetRenderError: Error { case unavailable }

  private struct ContactSheetDocumentView: View {
    let plan: ContactSheetPlan
    let images: [Int: NSImage]
    let columns: Int
    let imageHeight: CGFloat

    var body: some View {
      VStack(alignment: .leading, spacing: 18) {
        Text(plan.projectName).font(.system(size: 30, weight: .bold)).foregroundStyle(.black)
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: columns), spacing: 22
        ) {
          ForEach(plan.items) { item in
            VStack(alignment: .leading, spacing: 5) {
              ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.91, green: 0.93, blue: 0.96))
                if let image = images[item.index] {
                  Image(nsImage: image).resizable().scaledToFill().clipped()
                } else {
                  Text("FootageFlow").foregroundStyle(.secondary).font(.headline)
                }
              }.frame(height: imageHeight).clipShape(RoundedRectangle(cornerRadius: 8))
              Text(String(format: "%02d  %@", item.index, item.title)).font(
                .system(size: 14, weight: .semibold)
              )
              .lineLimit(2).foregroundStyle(.black)
              Text(item.provider).font(.system(size: 12)).foregroundStyle(.gray).lineLimit(1)
              if plan.includeRights {
                Text(item.rightsStatus).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
              }
            }
          }
        }
      }.padding(36)
    }
  }
#endif
