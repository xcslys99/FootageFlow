import Foundation

enum FootageFlowVersion {
  static let build = "0.7.4"
  static var current: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? build
  }
}
