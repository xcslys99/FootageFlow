import Foundation

/// Real-media verification for the creator workflow. It intentionally uses only public URLs,
/// never cookies, credentials, DRM workarounds, or browser state.
enum CreatorWorkflowSmokeRunner {
  private static let youtubeURL = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!
  private static let dailymotionURL = URL(string: "https://www.dailymotion.com/video/x7rvjrf")!
  private static let publicMediaURL = URL(
    string: "https://media.w3.org/2010/05/sintel/trailer.mp4")!

  static func run(directory: URL) async -> Int32 {
    var passed = 0
    var failures: [String] = []
    func check(_ condition: Bool, _ name: String) {
      if condition {
        passed += 1
        print("CREATOR_SMOKE PASS \(name)")
      } else {
        failures.append(name)
        print("CREATOR_SMOKE FAIL \(name)")
      }
    }

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      print("CREATOR_SMOKE FAIL create directory")
      return 1
    }

    let service = YTDLPService()
    check(service.isAvailable, "bundled yt-dlp")
    check(
      FFmpegToolLocator.ffmpegURL != nil && FFmpegToolLocator.ffprobeURL != nil,
      "bundled FFmpeg")
    guard service.isAvailable, let ffprobeURL = FFmpegToolLocator.ffprobeURL else { return 1 }

    for (name, url) in [
      ("YouTube analysis", youtubeURL), ("Dailymotion analysis", dailymotionURL),
      ("public media analysis", publicMediaURL),
    ] {
      do {
        let analysis = try await service.analyze(sourceURL: url)
        check(!analysis.title.isEmpty && !analysis.formats.isEmpty, name)
      } catch let error as ProviderError {
        if name == "YouTube analysis",
          case .temporarilyBlocked = error
        {
          check(true, "YouTube access limitation classified")
        } else if name == "YouTube analysis",
          case .rateLimited = error
        {
          check(true, "YouTube rate limit classified")
        } else {
          failures.append("\(name): \(error.localizedDescription)")
          print("CREATOR_SMOKE FAIL \(name) \(error.localizedDescription)")
        }
      } catch {
        failures.append("\(name): \(error.localizedDescription)")
        print("CREATOR_SMOKE FAIL \(name) \(error.localizedDescription)")
      }
    }

    do {
      let analysis = try await service.analyze(sourceURL: publicMediaURL)
      // Generic direct-file extractors do not always publish duration metadata. This fixed,
      // public Sintel fixture is longer than 12 seconds, so the smoke may supply its known
      // duration without weakening the user-facing unknown-duration validation.
      let fixtureDuration = analysis.duration ?? 52
      let range = try ClipTimeRange(start: 2, end: 12, mediaDuration: fixtureDuration)
      let options = YTDLPDownloadOptions(
        formatSelector: LinkDownloadQuality.p720.formatSelector,
        downloadSubtitles: false, subtitleLanguages: nil,
        outputPreset: .editingCompatibleMP4, clipRange: range,
        mediaDuration: fixtureDuration)
      let output = try await service.download(
        sourceURL: publicMediaURL, directory: directory, fileStem: "sintel-10-second-clip",
        options: options)
      let probe = try await probeMedia(output, ffprobeURL: ffprobeURL)
      check(output.pathExtension.lowercased() == "mp4", "editing MP4 extension")
      check(abs((probe.format.duration ?? 0) - 10) <= 0.25, "ten-second clip duration")
      check(
        probe.streams.contains {
          $0.codecType == "video" && $0.codecName == "h264" && $0.pixelFormat == "yuv420p"
        }, "H.264 yuv420p video")
      check(
        !probe.streams.contains { $0.codecType == "audio" && $0.codecName != "aac" },
        "AAC audio when present")
      check(try hasFastStart(output), "MP4 fast-start atom order")

      let asset = analysis.mediaAsset(
        quality: .p720, downloadSubtitles: false, subtitleLanguage: nil,
        outputPreset: .editingCompatibleMP4, clipRange: range)
      try SourceSidecar.write(
        asset: asset, mediaURL: output, projectName: "Creator Workflow Smoke", segmentIndex: 1)
      let base = output.deletingPathExtension()
      check(
        FileManager.default.fileExists(atPath: base.appendingPathExtension("source.txt").path),
        "text source sidecar")
      check(
        FileManager.default.fileExists(atPath: base.appendingPathExtension("source.json").path),
        "JSON source sidecar")
    } catch {
      failures.append("clip workflow: \(error.localizedDescription)")
      print("CREATOR_SMOKE FAIL clip workflow \(error.localizedDescription)")
    }

    print("CREATOR_WORKFLOW_SMOKE passed=\(passed) failed=\(failures.count)")
    for failure in failures { print("FAIL \(failure)") }
    return failures.isEmpty ? 0 : 1
  }

  private static func probeMedia(_ url: URL, ffprobeURL: URL) async throws -> CreatorProbe {
    let result = try await ProcessExternalToolRunner().run(
      executable: ffprobeURL,
      arguments: [
        "-v", "error", "-show_entries", "format=duration:stream=codec_type,codec_name,pix_fmt",
        "-of", "json", url.path,
      ], timeout: 60)
    guard result.exitCode == 0 else { throw ProviderError.invalidResponse }
    return try JSONDecoder().decode(CreatorProbe.self, from: result.standardOutput)
  }

  private static func hasFastStart(_ url: URL) throws -> Bool {
    let data = try Data(contentsOf: url, options: .mappedIfSafe).prefix(4 * 1_024 * 1_024)
    guard let moov = data.range(of: Data("moov".utf8))?.lowerBound,
      let mdat = data.range(of: Data("mdat".utf8))?.lowerBound
    else { return false }
    return moov < mdat
  }
}

private struct CreatorProbe: Decodable {
  let streams: [CreatorProbeStream]
  let format: CreatorProbeFormat
}

private struct CreatorProbeStream: Decodable {
  let codecType, codecName, pixelFormat: String?

  enum CodingKeys: String, CodingKey {
    case codecType = "codec_type"
    case codecName = "codec_name"
    case pixelFormat = "pix_fmt"
  }
}

private struct CreatorProbeFormat: Decodable {
  let duration: Double?

  enum CodingKeys: String, CodingKey { case duration }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let value = try? container.decode(Double.self, forKey: .duration) {
      duration = value
    } else if let value = try? container.decode(String.self, forKey: .duration) {
      duration = Double(value)
    } else {
      duration = nil
    }
  }
}
