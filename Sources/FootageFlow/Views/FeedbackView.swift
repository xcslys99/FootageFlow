import SwiftUI

struct FeedbackView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text(tr("nav.feedback")).font(.largeTitle.bold())
        Text(tr("feedback.intro")).foregroundStyle(.secondary)
        feedbackButton(.bug, title: tr("feedback.reportBug"), icon: "ladybug")
        feedbackButton(.feature, title: tr("feedback.suggestFeature"), icon: "lightbulb")
        feedbackButton(.question, title: tr("feedback.askQuestion"), icon: "questionmark.circle")
        feedbackButton(
          .repository, title: tr("feedback.viewGitHub"),
          icon: "chevron.left.forwardslash.chevron.right")
        feedbackButton(.releases, title: tr("feedback.viewReleases"), icon: "shippingbox")
        Divider().padding(.vertical, 4)
        Text(tr("feedback.starPrompt")).foregroundStyle(.secondary)
        Button("⭐ \(tr("feedback.viewGitHub"))") { open(.repository) }
          .buttonStyle(.borderedProminent)
        Text(tr("feedback.privacy")).font(.caption).foregroundStyle(.secondary)
      }.padding(24).frame(maxWidth: 760, alignment: .leading)
    }
  }

  private func feedbackButton(_ destination: FeedbackDestination, title: String, icon: String)
    -> some View
  {
    Button {
      open(destination)
    } label: {
      Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
    }.buttonStyle(.bordered)
  }

  private func open(_ destination: FeedbackDestination) {
    DesktopPlatform.shared.open(FeedbackURLs.url(for: destination))
  }
}
