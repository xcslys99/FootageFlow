import Foundation

enum DownloadStatus: String, Sendable { case waiting, downloading, completed, failed, cancelled }

struct DownloadProgress: Identifiable {
  let id: String
  let asset: MediaAsset
  let projectID: UUID?
  let projectName: String?
  let destination: URL?
  var progress: Double
  var status: DownloadStatus
  var bytesPerSecond: Double
  var retryCount: Int
  var detailKey: String?
  var localURL: URL?

  var statusLabel: String { tr("download.status.\(status.rawValue)") }
  var message: String {
    if let detailKey { return tr(detailKey) }
    switch status {
    case .waiting: return tr("download.waiting")
    case .downloading:
      if retryCount > 0 { return tr("download.retrying", retryCount) }
      return progress > 0
        ? tr("download.downloadingPercent", Int(progress * 100)) : tr("download.downloading")
    case .completed: return tr("download.completed")
    case .failed: return tr("download.failed")
    case .cancelled: return tr("download.cancelled")
    }
  }
  var speedText: String? {
    guard status == .downloading, bytesPerSecond > 0 else { return nil }
    let value = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file)
    return tr("download.speed", value)
  }
}

private struct DownloadContext {
  let asset: MediaAsset
  let projectID: UUID?
  let projectName: String?
  let segmentIndex: Int?
  let destination: URL
  var retryCount: Int
}

private struct DownloadSpeedSample {
  var bytes: Int64
  var time: Date
  var smoothedBytesPerSecond: Double
}

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate,
  @unchecked Sendable
{
  static let shared = DownloadManager()
  @Published private(set) var states: [String: DownloadProgress] = [:]

  private var store: DataStore?
  private var session: URLSession!
  private var contexts: [Int: DownloadContext] = [:]
  private var recoverableContexts: [String: DownloadContext] = [:]
  private var speedSamples: [Int: DownloadSpeedSample] = [:]
  private var pending: [DownloadContext] = []
  private var externalPending: [DownloadContext] = []
  private var externalTasks: [String: Task<Void, Never>] = [:]
  private var externalActive = false
  private var activeCount = 0
  private var finishedTasks = Set<Int>()
  private let lock = NSLock()

  override private init() {
    super.init()
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForResource = 60 * 60
    configuration.httpMaximumConnectionsPerHost = 3
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }

  @MainActor func configure(store: DataStore) { self.store = store }

  @MainActor
  func start(asset: MediaAsset, projectID: UUID?, projectName: String?, segmentIndex: Int? = nil) {
    if let current = states[asset.stableID],
      current.status == .waiting || current.status == .downloading
    {
      return
    }
    guard asset.downloadable, let url = try? URLValidator.remote(asset.downloadURL) else {
      states[asset.stableID] = progress(
        asset: asset, projectID: projectID, projectName: projectName, destination: nil,
        status: .failed, detailKey: "download.notAvailable")
      return
    }
    let directory = DownloadPathSafety.projectDirectory(projectName: projectName)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      states[asset.stableID] = progress(
        asset: asset, projectID: projectID, projectName: projectName, destination: directory,
        status: .failed, detailKey: "download.createFolderFailed")
      return
    }
    let preferred = FileNameSanitizer.fileName(asset: asset, index: segmentIndex)
    let existing = directory.appendingPathComponent(preferred)
    if FileManager.default.fileExists(atPath: existing.path) {
      states[asset.stableID] = progress(
        asset: asset, projectID: projectID, projectName: projectName, destination: existing,
        value: 1, status: .completed, detailKey: "download.duplicate", localURL: existing)
      if let store, !store.downloads.contains(where: { $0.localPath == existing.path }) {
        store.addDownload(DownloadRecord(asset: asset, fileURL: existing, projectID: projectID))
      }
      return
    }
    let destination = FileNameSanitizer.uniqueURL(in: directory, preferredName: preferred)
    let context = DownloadContext(
      asset: asset, projectID: projectID, projectName: projectName, segmentIndex: segmentIndex,
      destination: destination, retryCount: 0)
    lock.lock()
    recoverableContexts[asset.stableID] = context
    lock.unlock()
    if asset.effectiveDownloadStrategy == .ytDLP {
      enqueueExternal(context)
    } else {
      enqueue(context, validatedURL: url)
    }
  }

  @MainActor
  func retry(stableID: String) {
    if let current = states[stableID],
      current.status == .waiting || current.status == .downloading
    {
      return
    }
    lock.lock()
    let storedContext = recoverableContexts[stableID]
    lock.unlock()
    guard var context = storedContext,
      let url = try? URLValidator.remote(context.asset.downloadURL)
    else { return }
    context.retryCount = 0
    if FileManager.default.fileExists(atPath: context.destination.path) {
      let directory = context.destination.deletingLastPathComponent()
      context = DownloadContext(
        asset: context.asset, projectID: context.projectID, projectName: context.projectName,
        segmentIndex: context.segmentIndex,
        destination: FileNameSanitizer.uniqueURL(
          in: directory,
          preferredName: FileNameSanitizer.fileName(
            asset: context.asset, index: context.segmentIndex)), retryCount: 0)
    }
    lock.lock()
    recoverableContexts[stableID] = context
    lock.unlock()
    if context.asset.effectiveDownloadStrategy == .ytDLP {
      enqueueExternal(context)
    } else {
      enqueue(context, validatedURL: url)
    }
  }

  @MainActor
  func removeState(stableID: String) {
    guard let state = states[stableID], state.status != .waiting, state.status != .downloading
    else { return }
    states.removeValue(forKey: stableID)
    lock.lock()
    recoverableContexts.removeValue(forKey: stableID)
    lock.unlock()
  }

  @MainActor
  private func enqueue(_ context: DownloadContext, validatedURL url: URL) {
    lock.lock()
    if activeCount < 3 {
      activeCount += 1
      let task = session.downloadTask(with: url)
      contexts[task.taskIdentifier] = context
      speedSamples[task.taskIdentifier] = DownloadSpeedSample(
        bytes: 0, time: .now, smoothedBytesPerSecond: 0)
      lock.unlock()
      states[context.asset.stableID] = progress(context: context, status: .downloading)
      task.resume()
    } else {
      pending.append(context)
      lock.unlock()
      states[context.asset.stableID] = progress(context: context, status: .waiting)
    }
  }

  @MainActor func cancel(stableID: String) {
    if let task = externalTasks.removeValue(forKey: stableID) {
      task.cancel()
      states[stableID] = states[stableID].map { progress(from: $0, status: .cancelled) }
      return
    }
    if let index = externalPending.firstIndex(where: { $0.asset.stableID == stableID }) {
      externalPending.remove(at: index)
      states[stableID] = states[stableID].map { progress(from: $0, status: .cancelled) }
      return
    }
    lock.lock()
    pending.removeAll { $0.asset.stableID == stableID }
    lock.unlock()
    DispatchQueue.main.async { [weak self] in
      guard let self, let current = self.states[stableID] else { return }
      self.states[stableID] = self.progress(from: current, status: .cancelled)
    }
    session.getAllTasks { [weak self] tasks in
      guard let self else { return }
      self.lock.lock()
      let ids = self.contexts.filter { $0.value.asset.stableID == stableID }.map(\.key)
      self.lock.unlock()
      for task in tasks where ids.contains(task.taskIdentifier) { task.cancel() }
    }
  }

  @MainActor private func enqueueExternal(_ context: DownloadContext) {
    if externalActive {
      externalPending.append(context)
      states[context.asset.stableID] = progress(context: context, status: .waiting)
      return
    }
    externalActive = true
    runExternal(context)
  }

  @MainActor private func runExternal(_ context: DownloadContext) {
    states[context.asset.stableID] = progress(context: context, status: .downloading)
    let sourceURL = context.asset.sourcePageURL
    let directory = context.destination.deletingLastPathComponent()
    let stem = context.destination.deletingPathExtension().lastPathComponent
    let task = Task { [weak self] in
      guard let self else { return }
      do {
        let savedURL = try await YTDLPService().download(
          sourceURL: sourceURL, directory: directory, fileStem: stem)
        do {
          try SourceSidecar.write(
            asset: context.asset, mediaURL: savedURL, projectName: context.projectName,
            segmentIndex: context.segmentIndex)
        } catch {
          try? FileManager.default.removeItem(at: savedURL)
          throw error
        }
        finishExternal(context: context, savedURL: savedURL, error: nil)
      } catch {
        finishExternal(context: context, savedURL: nil, error: error)
      }
    }
    externalTasks[context.asset.stableID] = task
  }

  @MainActor private func finishExternal(
    context: DownloadContext, savedURL: URL?, error: Error?
  ) {
    externalTasks.removeValue(forKey: context.asset.stableID)
    externalActive = false
    if let savedURL {
      states[context.asset.stableID] = progress(
        context: context, value: 1, status: .completed, localURL: savedURL)
      if let store {
        store.addDownload(
          DownloadRecord(asset: context.asset, fileURL: savedURL, projectID: context.projectID))
      }
    } else if isCancellation(error) {
      states[context.asset.stableID] = progress(context: context, status: .cancelled)
    } else {
      states[context.asset.stableID] = progress(
        context: context, status: .failed, detailKey: downloadDetailKey(for: error))
      Task {
        await AppLogger.shared.write(
          provider: .youtube, requestType: "yt-dlp download", error: error)
      }
    }
    startNextExternal()
  }

  @MainActor private func startNextExternal() {
    guard !externalActive, !externalPending.isEmpty else { return }
    externalActive = true
    runExternal(externalPending.removeFirst())
  }

  private func downloadDetailKey(for error: Error?) -> String {
    guard let providerError = error as? ProviderError else { return "download.failed" }
    return switch providerError {
    case .rateLimited: "download.rateLimited"
    case .videoUnavailable: "download.videoUnavailable"
    case .regionalRestriction: "download.regionalRestriction"
    case .temporarilyBlocked: "download.accessRestricted"
    case .externalToolUnavailable: "download.ytDLPUnavailable"
    default: "download.failed"
    }
  }

  private func isCancellation(_ error: Error?) -> Bool {
    if error is CancellationError { return true }
    guard let providerError = error as? ProviderError else { return false }
    if case .cancelled = providerError { return true }
    return false
  }

  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    let now = Date()
    lock.lock()
    let context = contexts[downloadTask.taskIdentifier]
    var sample =
      speedSamples[downloadTask.taskIdentifier]
      ?? DownloadSpeedSample(bytes: 0, time: now, smoothedBytesPerSecond: 0)
    let elapsed = now.timeIntervalSince(sample.time)
    if elapsed >= 0.2 {
      let instantaneous = Double(max(0, totalBytesWritten - sample.bytes)) / elapsed
      sample.smoothedBytesPerSecond =
        sample.smoothedBytesPerSecond > 0
        ? sample.smoothedBytesPerSecond * 0.7 + instantaneous * 0.3 : instantaneous
      sample.bytes = totalBytesWritten
      sample.time = now
      speedSamples[downloadTask.taskIdentifier] = sample
    }
    lock.unlock()
    guard let context else { return }
    let progress =
      totalBytesExpectedToWrite > 0
      ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1) : 0
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.states[context.asset.stableID] = self.progress(
        context: context, value: progress, status: .downloading,
        speed: sample.smoothedBytesPerSecond)
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    lock.lock()
    let context = contexts[downloadTask.taskIdentifier]
    lock.unlock()
    guard let context else { return }
    do {
      try FileManager.default.moveItem(at: location, to: context.destination)
      do {
        try SourceSidecar.write(
          asset: context.asset, mediaURL: context.destination, projectName: context.projectName,
          segmentIndex: context.segmentIndex)
      } catch {
        try? FileManager.default.removeItem(at: context.destination)
        throw error
      }
      lock.lock()
      finishedTasks.insert(downloadTask.taskIdentifier)
      lock.unlock()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.states[context.asset.stableID] = self.progress(
          context: context, value: 1, status: .completed, localURL: context.destination)
        if let store = self.store {
          let record = DownloadRecord(
            asset: context.asset, fileURL: context.destination, projectID: context.projectID)
          store.addDownload(record)
        }
      }
    } catch {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.states[context.asset.stableID] = self.progress(
          context: context, status: .failed, detailKey: "download.saveFailed")
      }
    }
  }

  nonisolated func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    lock.lock()
    guard var context = contexts.removeValue(forKey: task.taskIdentifier) else {
      lock.unlock()
      return
    }
    speedSamples.removeValue(forKey: task.taskIdentifier)
    let alreadyFinished = finishedTasks.remove(task.taskIdentifier) != nil
    lock.unlock()
    if error == nil || alreadyFinished {
      startNextAfterTerminalTask()
      return
    }
    guard let error else {
      startNextAfterTerminalTask()
      return
    }
    if (error as? URLError)?.code == .cancelled {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.states[context.asset.stableID] = self.progress(context: context, status: .cancelled)
      }
      startNextAfterTerminalTask()
      return
    }
    if context.retryCount < 2, let url = try? URLValidator.remote(context.asset.downloadURL) {
      context.retryCount += 1
      let retry = session.downloadTask(with: url)
      lock.lock()
      contexts[retry.taskIdentifier] = context
      recoverableContexts[context.asset.stableID] = context
      speedSamples[retry.taskIdentifier] = DownloadSpeedSample(
        bytes: 0, time: .now, smoothedBytesPerSecond: 0)
      lock.unlock()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.states[context.asset.stableID] = self.progress(
          context: context, status: .downloading)
      }
      retry.resume()
    } else {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.states[context.asset.stableID] = self.progress(context: context, status: .failed)
      }
      startNextAfterTerminalTask()
    }
  }

  nonisolated private func startNextAfterTerminalTask() {
    lock.lock()
    activeCount = max(0, activeCount - 1)
    guard activeCount < 3, !pending.isEmpty else {
      lock.unlock()
      return
    }
    let next = pending.removeFirst()
    guard let url = try? URLValidator.remote(next.asset.downloadURL) else {
      lock.unlock()
      return
    }
    let task = session.downloadTask(with: url)
    contexts[task.taskIdentifier] = next
    recoverableContexts[next.asset.stableID] = next
    speedSamples[task.taskIdentifier] = DownloadSpeedSample(
      bytes: 0, time: .now, smoothedBytesPerSecond: 0)
    activeCount += 1
    lock.unlock()
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.states[next.asset.stableID] = self.progress(context: next, status: .downloading)
    }
    task.resume()
  }

  private func progress(
    context: DownloadContext, value: Double = 0, status: DownloadStatus, speed: Double = 0,
    detailKey: String? = nil, localURL: URL? = nil
  ) -> DownloadProgress {
    progress(
      asset: context.asset, projectID: context.projectID, projectName: context.projectName,
      destination: context.destination, value: value, status: status, speed: speed,
      retryCount: context.retryCount, detailKey: detailKey, localURL: localURL)
  }

  private func progress(
    asset: MediaAsset, projectID: UUID?, projectName: String?, destination: URL?,
    value: Double = 0,
    status: DownloadStatus, speed: Double = 0, retryCount: Int = 0, detailKey: String? = nil,
    localURL: URL? = nil
  ) -> DownloadProgress {
    DownloadProgress(
      id: asset.stableID, asset: asset, projectID: projectID, projectName: projectName,
      destination: destination, progress: value, status: status, bytesPerSecond: speed,
      retryCount: retryCount, detailKey: detailKey, localURL: localURL)
  }

  private func progress(from current: DownloadProgress, status: DownloadStatus)
    -> DownloadProgress
  {
    DownloadProgress(
      id: current.id, asset: current.asset, projectID: current.projectID,
      projectName: current.projectName, destination: current.destination,
      progress: current.progress, status: status, bytesPerSecond: 0,
      retryCount: current.retryCount,
      detailKey: nil, localURL: current.localURL)
  }
}
