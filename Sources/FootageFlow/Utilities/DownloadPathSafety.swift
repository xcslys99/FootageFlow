import Foundation

enum DownloadPathSafety {
    static func projectDirectory(projectName: String?, root: URL = AppSettings.downloadRootURL) -> URL {
        let fallback = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = FileNameSanitizer.sanitize((fallback?.isEmpty == false ? fallback : nil) ?? tr("common.uncategorized"), maxLength: 60)
        return root.standardizedFileURL.appendingPathComponent(folder, isDirectory: true)
    }

    static func isContained(_ candidate: URL, in root: URL = AppSettings.downloadRootURL) -> Bool {
        let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard normalizedCandidate.path != normalizedRoot.path else { return false }
        return normalizedCandidate.path.hasPrefix(normalizedRoot.path.hasSuffix("/") ? normalizedRoot.path : normalizedRoot.path + "/")
    }

    static func relatedFiles(for mediaURL: URL) -> [URL] {
        let base = mediaURL.deletingPathExtension()
        return [mediaURL, base.appendingPathExtension("source.txt"), base.appendingPathExtension("source.json")]
    }
}
