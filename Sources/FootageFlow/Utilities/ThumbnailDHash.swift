import Foundation

/// A 9 × 8 grayscale difference hash. Decoding remains in each platform layer.
enum ThumbnailDHash {
  static func compute(luminance: [UInt8]) -> UInt64? {
    guard luminance.count == 72,
      let low = luminance.min(), let high = luminance.max(), high - low >= 12
    else { return nil }  // Blank or near-solid thumbnails are not useful duplicate evidence.
    var bits: UInt64 = 0
    for row in 0..<8 {
      for column in 0..<8 {
        bits <<= 1
        if luminance[row * 9 + column] > luminance[row * 9 + column + 1] { bits |= 1 }
      }
    }
    return bits
  }
}
