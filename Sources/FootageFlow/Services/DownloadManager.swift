import Foundation

enum DownloadStatus: String { case waiting, downloading, completed, failed, cancelled }
struct DownloadProgress: Identifiable {
    let id: String
    var progress: Double
    var status: DownloadStatus
    var message: String
    var localURL: URL?
}

private struct DownloadContext {
    let asset: MediaAsset
    let projectID: UUID?
    let projectName: String?
    let segmentIndex: Int?
    let destination: URL
    var retryCount: Int
}

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = DownloadManager()
    @Published private(set) var states: [String: DownloadProgress] = [:]

    private var store: DataStore?
    private var session: URLSession!
    private var contexts: [Int: DownloadContext] = [:]
    private var pending: [DownloadContext] = []
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
        guard asset.downloadable, let url = try? URLValidator.remote(asset.downloadURL) else {
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 0, status: .failed, message: tr("download.notAvailable"), localURL: nil)
            return
        }
        let folderName = FileNameSanitizer.sanitize(projectName ?? tr("common.uncategorized"), maxLength: 60)
        let directory = AppSettings.downloadRootURL.appendingPathComponent(folderName, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch {
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 0, status: .failed, message: tr("download.createFolderFailed"), localURL: nil)
            return
        }
        let preferred = FileNameSanitizer.fileName(asset: asset, index: segmentIndex)
        let existing = directory.appendingPathComponent(preferred)
        if FileManager.default.fileExists(atPath: existing.path) {
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 1, status: .completed, message: tr("download.duplicate"), localURL: existing)
            return
        }
        let destination = FileNameSanitizer.uniqueURL(in: directory, preferredName: preferred)
        let context = DownloadContext(asset: asset, projectID: projectID, projectName: projectName, segmentIndex: segmentIndex, destination: destination, retryCount: 0)
        lock.lock()
        if activeCount < 3 {
            activeCount += 1
            let task = session.downloadTask(with: url); contexts[task.taskIdentifier] = context
            lock.unlock()
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 0, status: .downloading, message: tr("download.downloadingPercent", 0), localURL: nil)
            task.resume()
        } else {
            pending.append(context); lock.unlock()
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 0, status: .waiting, message: tr("download.waiting"), localURL: nil)
        }
    }

    func cancel(stableID: String) {
        lock.lock(); pending.removeAll { $0.asset.stableID == stableID }; lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.states[stableID] = DownloadProgress(id: stableID, progress: 0, status: .cancelled, message: tr("download.cancelled"), localURL: nil) }
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            self.lock.lock(); let ids = self.contexts.filter { $0.value.asset.stableID == stableID }.map(\.key); self.lock.unlock()
            tasks.filter { ids.contains($0.taskIdentifier) }.forEach { $0.cancel() }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        lock.lock(); let context = contexts[downloadTask.taskIdentifier]; lock.unlock()
        guard let context else { return }
        let progress = totalBytesExpectedToWrite > 0 ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1) : 0
        DispatchQueue.main.async { [weak self] in
            self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: progress, status: .downloading, message: totalBytesExpectedToWrite > 0 ? tr("download.downloadingPercent", Int(progress * 100)) : tr("download.downloading"), localURL: nil)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock(); let context = contexts[downloadTask.taskIdentifier]; lock.unlock()
        guard let context else { return }
        do {
            try FileManager.default.moveItem(at: location, to: context.destination)
            try SourceSidecar.write(asset: context.asset, mediaURL: context.destination, projectName: context.projectName, segmentIndex: context.segmentIndex)
            lock.lock(); finishedTasks.insert(downloadTask.taskIdentifier); lock.unlock()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 1, status: .completed, message: tr("download.completed"), localURL: context.destination)
                if let store = self.store {
                    let record = DownloadRecord(asset: context.asset, fileURL: context.destination, projectID: context.projectID)
                    store.addDownload(record)
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 0, status: .failed, message: tr("download.saveFailed"), localURL: nil) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard var context = contexts.removeValue(forKey: task.taskIdentifier) else { lock.unlock(); return }
        let alreadyFinished = finishedTasks.remove(task.taskIdentifier) != nil
        lock.unlock()
        if error == nil || alreadyFinished {
            startNextAfterTerminalTask()
            return
        }
        guard let error else { startNextAfterTerminalTask(); return }
        if (error as? URLError)?.code == .cancelled {
            DispatchQueue.main.async { [weak self] in self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 0, status: .cancelled, message: tr("download.cancelled"), localURL: nil) }
            startNextAfterTerminalTask()
            return
        }
        if context.retryCount < 2, let url = try? URLValidator.remote(context.asset.downloadURL) {
            context.retryCount += 1
            let retry = session.downloadTask(with: url)
            lock.lock(); contexts[retry.taskIdentifier] = context; lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 0, status: .downloading, message: tr("download.retrying", context.retryCount), localURL: nil) }
            retry.resume()
        } else {
            DispatchQueue.main.async { [weak self] in self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 0, status: .failed, message: tr("download.failed"), localURL: nil) }
            startNextAfterTerminalTask()
        }
    }

    nonisolated private func startNextAfterTerminalTask() {
        lock.lock()
        activeCount = max(0, activeCount - 1)
        guard activeCount < 3, !pending.isEmpty else { lock.unlock(); return }
        let next = pending.removeFirst()
        guard let url = try? URLValidator.remote(next.asset.downloadURL) else { lock.unlock(); return }
        let task = session.downloadTask(with: url)
        contexts[task.taskIdentifier] = next; activeCount += 1
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.states[next.asset.stableID] = DownloadProgress(id: next.asset.stableID, progress: 0, status: .downloading, message: tr("download.downloadingPercent", 0), localURL: nil) }
        task.resume()
    }
}

private struct Sidecar: Codable {
    let title, assetID, provider, creator, sourcePage, originalFileURL: String
    let licenseName, licenseURL, licenseStatus, searchKeyword, downloadDate, projectName, segment: String
}

enum SourceSidecar {
    static func write(asset: MediaAsset, mediaURL: URL, projectName: String?, segmentIndex: Int?) throws {
        let formatter = ISO8601DateFormatter()
        let status = asset.licenseStatus == .unknown ? tr("sidecar.authorizationUnknown") : asset.licenseStatus.label
        let sidecar = Sidecar(title: asset.title, assetID: asset.id, provider: asset.provider.displayName, creator: asset.creator ?? tr("common.unknown"), sourcePage: asset.sourcePageURL.absoluteString, originalFileURL: asset.downloadURL?.absoluteString ?? tr("common.unknown"), licenseName: asset.license ?? tr("common.unknown"), licenseURL: asset.licenseURL?.absoluteString ?? tr("common.unknown"), licenseStatus: status, searchKeyword: asset.searchKeyword, downloadDate: formatter.string(from: .now), projectName: projectName ?? tr("common.uncategorized"), segment: segmentIndex.map(String.init) ?? tr("common.notSpecified"))
        let base = mediaURL.deletingPathExtension()
        let jsonURL = base.appendingPathExtension("source.json")
        let textURL = base.appendingPathExtension("source.txt")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sidecar).write(to: jsonURL, options: .atomic)
        let text = """
        \(tr("sidecar.title")): \(sidecar.title)
        \(tr("sidecar.assetID")): \(sidecar.assetID)
        \(tr("sidecar.provider")): \(sidecar.provider)
        \(tr("sidecar.creator")): \(sidecar.creator)
        \(tr("sidecar.sourcePage")): \(sidecar.sourcePage)
        \(tr("sidecar.originalFile")): \(sidecar.originalFileURL)
        \(tr("sidecar.licenseName")): \(sidecar.licenseName)
        \(tr("sidecar.licenseURL")): \(sidecar.licenseURL)
        \(tr("sidecar.licenseStatus")): \(sidecar.licenseStatus)
        \(tr("sidecar.searchKeyword")): \(sidecar.searchKeyword)
        \(tr("sidecar.downloadDate")): \(sidecar.downloadDate)
        \(tr("sidecar.projectName")): \(sidecar.projectName)
        \(tr("sidecar.segment")): \(sidecar.segment)
        """
        try Data(text.utf8).write(to: textURL, options: .atomic)
    }
}
