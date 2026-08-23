import Foundation

enum FootageFlowVersion {
  static let build = "0.10.0"
  static var current: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? build
  }
}
