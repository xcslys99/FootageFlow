import Foundation

struct ExternalToolResult: Sendable {
  let standardOutput: Data
  let standardError: Data
  let exitCode: Int32

  var outputText: String { String(decoding: standardOutput, as: UTF8.self) }
  var errorText: String { String(decoding: standardError, as: UTF8.self) }
}

protocol ExternalToolRunning: Sendable {
  func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws
    -> ExternalToolResult
}

#if os(macOS)
  struct ProcessExternalToolRunner: ExternalToolRunning {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws
      -> ExternalToolResult
    {
      let operation = ProcessOperation()
      return try await withTaskCancellationHandler {
        try await operation.start(executable: executable, arguments: arguments, timeout: timeout)
      } onCancel: {
        operation.cancel()
      }
    }
  }

  private final class ProcessOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var didTimeOut = false
    private var wasCancelled = false
    private var output = Data()
    private var errorOutput = Data()
    private var timeoutWorkItem: DispatchWorkItem?

    func start(executable: URL, arguments: [String], timeout: TimeInterval) async throws
      -> ExternalToolResult
    {
      try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try? FileManager.default.createDirectory(
          at: PlatformPaths.cache, withIntermediateDirectories: true)
        process.environment = [
          "HOME": PlatformPaths.cache.path,
          "LANG": "en_US.UTF-8",
          "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
          self?.append(handle.availableData, isError: false)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
          self?.append(handle.availableData, isError: true)
        }
        process.terminationHandler = { [weak self] process in
          guard let self else { return }
          outputPipe.fileHandleForReading.readabilityHandler = nil
          errorPipe.fileHandleForReading.readabilityHandler = nil
          append(outputPipe.fileHandleForReading.readDataToEndOfFile(), isError: false)
          append(errorPipe.fileHandleForReading.readDataToEndOfFile(), isError: true)
          lock.lock()
          timeoutWorkItem?.cancel()
          let result = ExternalToolResult(
            standardOutput: output, standardError: errorOutput,
            exitCode: process.terminationStatus)
          let cancelled = wasCancelled
          let timedOut = didTimeOut
          self.process = nil
          lock.unlock()
          if cancelled {
            continuation.resume(throwing: ProviderError.cancelled)
          } else if timedOut {
            continuation.resume(throwing: ProviderError.message(tr("error.timeout")))
          } else {
            continuation.resume(returning: result)
          }
        }
        lock.lock()
        self.process = process
        lock.unlock()
        do {
          try process.run()
          let workItem = DispatchWorkItem { [weak self] in self?.timeOut() }
          lock.lock()
          timeoutWorkItem = workItem
          lock.unlock()
          DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(1, timeout), execute: workItem)
        } catch {
          outputPipe.fileHandleForReading.readabilityHandler = nil
          errorPipe.fileHandleForReading.readabilityHandler = nil
          lock.lock()
          self.process = nil
          lock.unlock()
          continuation.resume(throwing: ProviderError.externalToolUnavailable)
        }
      }
    }

    func cancel() {
      lock.lock()
      wasCancelled = true
      let process = process
      lock.unlock()
      if process?.isRunning == true { process?.terminate() }
    }

    private func timeOut() {
      lock.lock()
      didTimeOut = true
      let process = process
      lock.unlock()
      if process?.isRunning == true { process?.terminate() }
    }

    private func append(_ data: Data, isError: Bool) {
      guard !data.isEmpty else { return }
      lock.lock()
      if isError { errorOutput.append(data) } else { output.append(data) }
      lock.unlock()
    }
  }
#else
  struct ProcessExternalToolRunner: ExternalToolRunning {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws
      -> ExternalToolResult
    {
      throw ProviderError.externalToolUnavailable
    }
  }
#endif
