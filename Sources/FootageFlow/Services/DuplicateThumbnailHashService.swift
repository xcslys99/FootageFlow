#if os(macOS)
  import Foundation
  import ImageIO
  import CoreGraphics

  /// Ephemeral, bounded hash cache. ThumbnailPipeline handles validated network loading.
  actor DuplicateThumbnailHashService {
    static let shared = DuplicateThumbnailHashService()
    private var cache: [URL: UInt64] = [:]
    private var order: [URL] = []

    func hashes(for assets: [MediaAsset], candidateIDs: [String]) async -> [String: UInt64] {
      let ids = Set(candidateIDs)
      var result: [String: UInt64] = [:]
      for asset in assets where ids.contains(asset.stableID) {
        if Task.isCancelled { break }
        for url in asset.effectiveThumbnailCandidates.prefix(2) {
          if let cached = cache[url] {
            result[asset.stableID] = cached
            break
          }
          guard
            let payload = try? await ThumbnailPipeline.shared.load(url, provider: asset.provider),
            !Task.isCancelled,
            let hash = Self.decodeAndHash(payload.data)
          else { continue }
          cache[url] = hash
          order.append(url)
          if order.count > 240 { cache.removeValue(forKey: order.removeFirst()) }
          result[asset.stableID] = hash
          break
        }
      }
      return result
    }

    func clear() {
      cache.removeAll()
      order.removeAll()
    }

    private static func decodeAndHash(_ data: Data) -> UInt64? {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int,
        width > 0, height > 0, width <= 4096, height <= 4096,
        width * height <= 16_000_000,
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
          ] as CFDictionary)
      else { return nil }
      var pixels = [UInt8](repeating: 0, count: 72)
      let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard
          let context = CGContext(
            data: buffer.baseAddress, width: 9, height: 8, bitsPerComponent: 8,
            bytesPerRow: 9, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
        return true
      }
      return drew ? ThumbnailDHash.compute(luminance: pixels) : nil
    }
  }
#endif
