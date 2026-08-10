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
        guard let url = asset.downloadURL, asset.downloadable else {
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 0, status: .failed, message: "该来源不提供直接下载", localURL: nil)
            return
        }
        let folderName = FileNameSanitizer.sanitize(projectName ?? "未分类", maxLength: 60)
        let directory = AppSettings.downloadRootURL.appendingPathComponent(folderName, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch {
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 0, status: .failed, message: "无法创建下载目录", localURL: nil)
            return
        }
        let preferred = FileNameSanitizer.fileName(asset: asset, index: segmentIndex)
        let existing = directory.appendingPathComponent(preferred)
        if FileManager.default.fileExists(atPath: existing.path) {
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 1, status: .completed, message: "文件已存在，未重复下载", localURL: existing)
            return
        }
        let destination = FileNameSanitizer.uniqueURL(in: directory, preferredName: preferred)
        let context = DownloadContext(asset: asset, projectID: projectID, projectName: projectName, segmentIndex: segmentIndex, destination: destination, retryCount: 0)
        lock.lock()
        if activeCount < 3 {
            activeCount += 1
            let task = session.downloadTask(with: url); contexts[task.taskIdentifier] = context
            lock.unlock()
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 0, status: .downloading, message: "正在下载 0%", localURL: nil)
            task.resume()
        } else {
            pending.append(context); lock.unlock()
            states[asset.stableID] = DownloadProgress(id: asset.stableID, progress: 0, status: .waiting, message: "等待下载（最多同时 3 个）", localURL: nil)
        }
    }

    func cancel(stableID: String) {
        lock.lock(); pending.removeAll { $0.asset.stableID == stableID }; lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.states[stableID] = DownloadProgress(id: stableID, progress: 0, status: .cancelled, message: "下载已取消", localURL: nil) }
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
            self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: progress, status: .downloading, message: totalBytesExpectedToWrite > 0 ? "正在下载 \(Int(progress * 100))%" : "正在下载…", localURL: nil)
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
                self.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 1, status: .completed, message: "下载完成", localURL: context.destination)
                if let store = self.store {
                    let record = DownloadRecord(asset: context.asset, fileURL: context.destination, projectID: context.projectID)
                    store.addDownload(record)
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 0, status: .failed, message: "保存文件失败", localURL: nil) }
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
            DispatchQueue.main.async { [weak self] in self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 0, status: .cancelled, message: "下载已取消", localURL: nil) }
            startNextAfterTerminalTask()
            return
        }
        if context.retryCount < 2, let url = context.asset.downloadURL {
            context.retryCount += 1
            let retry = session.downloadTask(with: url)
            lock.lock(); contexts[retry.taskIdentifier] = context; lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 0, status: .downloading, message: "下载中断，正在第 \(context.retryCount) 次重试", localURL: nil) }
            retry.resume()
        } else {
            DispatchQueue.main.async { [weak self] in self?.states[context.asset.stableID] = DownloadProgress(id: context.asset.stableID, progress: 0, status: .failed, message: "下载失败，请稍后重试", localURL: nil) }
            startNextAfterTerminalTask()
        }
    }

    nonisolated private func startNextAfterTerminalTask() {
        lock.lock()
        activeCount = max(0, activeCount - 1)
        guard activeCount < 3, !pending.isEmpty else { lock.unlock(); return }
        let next = pending.removeFirst()
        guard let url = next.asset.downloadURL else { lock.unlock(); return }
        let task = session.downloadTask(with: url)
        contexts[task.taskIdentifier] = next; activeCount += 1
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.states[next.asset.stableID] = DownloadProgress(id: next.asset.stableID, progress: 0, status: .downloading, message: "正在下载 0%", localURL: nil) }
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
        let status = asset.licenseStatus == .unknown ? "未知，请在发布前检查原始来源页面" : asset.licenseStatus.label
        let sidecar = Sidecar(title: asset.title, assetID: asset.id, provider: asset.provider.displayName, creator: asset.creator ?? "未知", sourcePage: asset.sourcePageURL.absoluteString, originalFileURL: asset.downloadURL?.absoluteString ?? "未知", licenseName: asset.license ?? "未知", licenseURL: asset.licenseURL?.absoluteString ?? "未知", licenseStatus: status, searchKeyword: asset.searchKeyword, downloadDate: formatter.string(from: .now), projectName: projectName ?? "未分类", segment: segmentIndex.map(String.init) ?? "未指定")
        let base = mediaURL.deletingPathExtension()
        let jsonURL = base.appendingPathExtension("source.json")
        let textURL = base.appendingPathExtension("source.txt")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sidecar).write(to: jsonURL, options: .atomic)
        let text = """
        标题：\(sidecar.title)
        素材ID：\(sidecar.assetID)
        来源平台：\(sidecar.provider)
        作者/上传者：\(sidecar.creator)
        原始素材页面：\(sidecar.sourcePage)
        原始文件地址：\(sidecar.originalFileURL)
        License名称：\(sidecar.licenseName)
        License链接：\(sidecar.licenseURL)
        授权状态：\(sidecar.licenseStatus)
        搜索关键词：\(sidecar.searchKeyword)
        下载日期时间：\(sidecar.downloadDate)
        项目名称：\(sidecar.projectName)
        对应镜头编号：\(sidecar.segment)
        """
        try Data(text.utf8).write(to: textURL, options: .atomic)
    }
}
