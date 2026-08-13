using System.Globalization;
using System.Windows;
using FootageFlow.Windows.Models;

namespace FootageFlow.Windows;

public partial class UpdateWindow : Window
{
    public UpdateWindow(AppReleaseInfo release, string currentVersion, Func<string, string> text)
    {
        InitializeComponent();
        Title = text("update.settingsTitle");
        HeadingText.Text = text("update.availableTitle");
        VersionText.Text = string.Join(Environment.NewLine,
            Format(text("update.currentVersionValue"), currentVersion),
            Format(text("update.latestVersionValue"), release.Version));
        PublishedText.Text = release.PublishedAt is { } published
            ? Format(text("update.published"), published.ToLocalTime().ToString("D", CultureInfo.CurrentCulture)) : "";
        ReleaseTitleText.Text = release.Title;
        WhatsNewText.Text = text("update.whatsNew");
        NotesText.Text = string.IsNullOrWhiteSpace(release.Notes)
            ? text("update.notesUnavailable") : release.Notes;
        SafetyText.Text = text("update.noAutomaticInstall");
        LaterButton.Content = text("update.notNow");
        ViewButton.Content = text("update.viewUpdate");
    }

    private void View_Click(object sender, RoutedEventArgs e) => DialogResult = true;
    private void Later_Click(object sender, RoutedEventArgs e) => DialogResult = false;

    private static string Format(string value, params object[] arguments)
    {
        foreach (var argument in arguments)
        {
            var index = value.IndexOf("%@", StringComparison.Ordinal);
            if (index < 0) break;
            value = string.Concat(value.AsSpan(0, index), argument?.ToString(), value.AsSpan(index + 2));
        }
        return value;
    }
}
