import Foundation

enum FileNameSanitizer {
    static func sanitize(_ input: String, maxLength: Int = 80) -> String {
        let latin = input.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? input
        var value = latin.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        value = value.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        if value.isEmpty { value = "Media" }
        return String(value.prefix(maxLength))
    }

    static func fileName(asset: MediaAsset, index: Int? = nil) -> String {
        let number = index.map { String(format: "%02d_", $0) } ?? ""
        let stem = sanitize(asset.title, maxLength: 64)
        let ext: String = {
            let urlExt = asset.downloadURL?.pathExtension.lowercased() ?? ""
            if !urlExt.isEmpty { return urlExt }
            if asset.mediaType == .image { return "jpg" }
            return "mp4"
        }()
        return "\(number)\(stem)_\(asset.provider.displayName.replacingOccurrences(of: " ", with: ""))_\(sanitize(asset.id, maxLength: 24)).\(ext)"
    }

    static func uniqueURL(in directory: URL, preferredName: String) -> URL {
        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(preferredName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)_\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
