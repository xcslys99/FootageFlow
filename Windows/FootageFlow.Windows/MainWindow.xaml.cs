using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using FootageFlow.Windows.Models;
using FootageFlow.Windows.Services;
using FootageFlow.Windows.ViewModels;
using Microsoft.Win32;
using System.Windows.Threading;

namespace FootageFlow.Windows;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel = new();
    private readonly DispatcherTimer _clipboardTimer = new() { Interval = TimeSpan.FromSeconds(2) };

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _viewModel;
        _viewModel.PreviewRequested += asset =>
        {
            if (asset is not null) new PreviewWindow(asset, _viewModel.T) { Owner = this }.Show();
        };
        _viewModel.UpdateAvailable += ShowUpdateDialog;
        _clipboardTimer.Tick += (_, _) =>
        {
            if (!IsActive || !_viewModel.IsLinkDownloaderPage || !_viewModel.ClipboardDetectionEnabled) return;
            try { if (Clipboard.ContainsText()) _viewModel.CheckClipboardCandidate(Clipboard.GetText()); }
            catch { }
        };
        Loaded += async (_, _) =>
        {
            _clipboardTimer.Start();
            await _viewModel.CheckForUpdatesOnLaunchAsync();
        };
        Closed += (_, _) => _clipboardTimer.Stop();
    }

    private void ShowUpdateDialog(AppReleaseInfo release)
    {
        var dialog = new UpdateWindow(release, _viewModel.CurrentVersion, _viewModel.T)
        {
            Owner = this
        };
        if (dialog.ShowDialog() == true) _viewModel.ViewUpdate(release);
        else _viewModel.NotNow();
    }

    private void LanguageButton_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        foreach (var language in LocalizationService.SupportedLanguages)
        {
            var item = new MenuItem
            {
                Header = language.DisplayName,
                IsCheckable = true,
                IsChecked = _viewModel.LanguageCode == language.Code
            };
            item.Click += (_, _) => _viewModel.SetLanguage(language.Code);
            menu.Items.Add(item);
        }
        menu.PlacementTarget = LanguageButton;
        menu.IsOpen = true;
    }

    private void SaveApiKey_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not string provider) return;
        var box = FindVisualChild<PasswordBox>(FindVisualParent<Border>(button));
        if (box is null || string.IsNullOrWhiteSpace(box.Password)) return;
        try
        {
            _viewModel.SaveApiKey(provider, box.Password);
            box.Clear();
        }
        catch (Exception error) { MessageBox.Show(error.Message, "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private void RemoveApiKey_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not string provider) return;
        try { _viewModel.RemoveApiKey(provider); }
        catch (Exception error) { MessageBox.Show(error.Message, "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private async void TestProvider_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not string provider) return;
        button.IsEnabled = false;
        try { await _viewModel.TestProviderAsync(provider); }
        finally { button.IsEnabled = true; }
    }

    private void OpenProviderSearch_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string provider }) _viewModel.OpenOfficialSearch(provider);
    }

    private void ChooseDownloadFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = _viewModel.T("settings.choose"), Multiselect = false };
        if (dialog.ShowDialog(this) == true) _viewModel.ChooseDownloadRoot(dialog.FolderName);
    }

    private void ProjectExport_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        foreach (var (label, format) in new[]
        {
            (_viewModel.T("project.reportMarkdown"), "md"), (_viewModel.T("project.reportCSV"), "csv"),
            (_viewModel.T("project.reportJSON"), "json"), (_viewModel.T("project.reportHTML"), "html")
        })
        {
            var item = new MenuItem { Header = label, Tag = format };
            item.Click += async (_, _) => await SaveProjectReportAsync(format);
            menu.Items.Add(item);
        }
        menu.PlacementTarget = sender as Button; menu.IsOpen = true;
    }

    private async Task SaveProjectReportAsync(string format)
    {
        var project = _viewModel.CurrentProject;
        if (project is null) return;
        RightsAuditReport? audit;
        try { audit = await _viewModel.GetCurrentRightsAuditAsync(); }
        catch
        {
            MessageBox.Show(_viewModel.T("project.actionFailed"), "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (audit is not null && (audit.Summary.RightsUnknown > 0 || audit.Summary.OriginalPageUnavailable > 0))
        {
            var review = MessageBox.Show(
                _viewModel.T("project.rightsExportWarningDetail") + "\n\n" + _viewModel.T("project.rightsExportPrompt"),
                _viewModel.T("project.rightsExportWarning"), MessageBoxButton.YesNoCancel, MessageBoxImage.Warning);
            if (review == MessageBoxResult.Yes)
            {
                _viewModel.RefreshRightsAuditCommand.Execute(null);
                return;
            }
            if (review == MessageBoxResult.Cancel) return;
        }
        var paths = MessageBox.Show(
            _viewModel.T("project.exportLocalPathsQuestion"), "FootageFlow", MessageBoxButton.YesNoCancel,
            MessageBoxImage.Question);
        if (paths == MessageBoxResult.Cancel) return;
        var dialog = new SaveFileDialog
        {
            FileName = $"{WindowsPathSafety.SanitizeName(project.Name)}-attribution.{format}",
            Filter = $"{format.ToUpperInvariant()} files (*.{format})|*.{format}"
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var data = await _viewModel.BuildProjectReportAsync(format, paths == MessageBoxResult.Yes);
            if (data is not null) await File.WriteAllBytesAsync(dialog.FileName, data);
        }
        catch { MessageBox.Show(_viewModel.T("project.exportFailed"), "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private void ProjectCredits_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        AddCreditsMenuItem(menu, _viewModel.T("project.copyConciseCredits"), "concise", false, "txt");
        AddCreditsMenuItem(menu, _viewModel.T("project.copyDetailedCredits"), "detailed", false, "txt");
        AddCreditsMenuItem(menu, _viewModel.T("project.saveConciseCredits"), "concise", true, "txt");
        AddCreditsMenuItem(menu, _viewModel.T("project.saveDetailedCredits"), "detailed", true, "md");
        menu.PlacementTarget = sender as Button; menu.IsOpen = true;
    }

    private void AddCreditsMenuItem(ContextMenu menu, string label, string style, bool save, string extension)
    {
        var item = new MenuItem { Header = label };
        item.Click += async (_, _) =>
        {
            try
            {
                var text = await _viewModel.BuildProjectCreditsAsync(style);
                if (string.IsNullOrWhiteSpace(text)) return;
                if (!save) { Clipboard.SetText(text); return; }
                var project = _viewModel.CurrentProject;
                if (project is null) return;
                var dialog = new SaveFileDialog
                {
                    FileName = $"{WindowsPathSafety.SanitizeName(project.Name)}-credits.{extension}",
                    Filter = $"{extension.ToUpperInvariant()} files (*.{extension})|*.{extension}"
                };
                if (dialog.ShowDialog(this) == true) await File.WriteAllTextAsync(dialog.FileName, text);
            }
            catch { MessageBox.Show(_viewModel.T("project.creditsFailed"), "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Warning); }
        };
        menu.Items.Add(item);
    }

    private async void ProjectBackup_Click(object sender, RoutedEventArgs e)
    {
        var project = _viewModel.CurrentProject;
        if (project is null) return;
        var dialog = new SaveFileDialog
        {
            FileName = $"{WindowsPathSafety.SanitizeName(project.Name)}.footageflowproject",
            Filter = "FootageFlow project (*.footageflowproject)|*.footageflowproject"
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var data = await _viewModel.BuildProjectBackupAsync();
            if (data is not null) await File.WriteAllBytesAsync(dialog.FileName, data);
        }
        catch { MessageBox.Show(_viewModel.T("project.backupFailed"), "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private async void ProjectImport_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "FootageFlow project (*.footageflowproject)|*.footageflowproject", Multiselect = false };
        if (dialog.ShowDialog(this) != true) return;
        try { await _viewModel.ImportProjectBackupAsync(await File.ReadAllBytesAsync(dialog.FileName)); }
        catch { MessageBox.Show("This project backup could not be imported.", "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private void ContactSheet_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        foreach (var columns in new[] { 3, 4, 5 })
        {
            var withRights = new MenuItem { Header = $"{FormatCount("project.contactSheetColumns", columns)} — {_viewModel.T("project.includeRights")}" };
            withRights.Click += async (_, _) => await SaveContactSheetAsync(columns, true);
            var withoutRights = new MenuItem { Header = $"{FormatCount("project.contactSheetColumns", columns)} — {_viewModel.T("project.noRights")}" };
            withoutRights.Click += async (_, _) => await SaveContactSheetAsync(columns, false);
            menu.Items.Add(withRights); menu.Items.Add(withoutRights);
        }
        menu.PlacementTarget = sender as Button; menu.IsOpen = true;
    }

    private async Task SaveContactSheetAsync(int columns, bool includeRights)
    {
        var project = _viewModel.CurrentProject;
        if (project is null) return;
        var dialog = new SaveFileDialog
        {
            FileName = $"{WindowsPathSafety.SanitizeName(project.Name)}-contact-sheet.png",
            Filter = "PNG image (*.png)|*.png"
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var plan = await _viewModel.BuildContactSheetPlanAsync(columns, includeRights);
            if (plan is not null) await ContactSheetRenderer.RenderPngAsync(plan, dialog.FileName);
        }
        catch { MessageBox.Show(_viewModel.T("project.contactSheetFailed"), "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private void OpenProjectOriginal_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string url }) ShellService.OpenUrl(url);
    }

    private void RevealProjectItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string path } && File.Exists(path)) ShellService.Reveal(path);
    }

    private string FormatCount(string key, int value) => _viewModel.T(key).Replace("%d", value.ToString());

    private static T? FindVisualChild<T>(DependencyObject? parent) where T : DependencyObject
    {
        if (parent is null) return null;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is T match) return match;
            var nested = FindVisualChild<T>(child);
            if (nested is not null) return nested;
        }
        return null;
    }

    private static T? FindVisualParent<T>(DependencyObject? child) where T : DependencyObject
    {
        while (child is not null)
        {
            if (child is T match) return match;
            child = VisualTreeHelper.GetParent(child);
        }
        return null;
    }
}
