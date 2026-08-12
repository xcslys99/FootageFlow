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
        _clipboardTimer.Tick += (_, _) =>
        {
            if (!IsActive || !_viewModel.IsLinkDownloaderPage || !_viewModel.ClipboardDetectionEnabled) return;
            try { if (Clipboard.ContainsText()) _viewModel.CheckClipboardCandidate(Clipboard.GetText()); }
            catch { }
        };
        Loaded += (_, _) => _clipboardTimer.Start();
        Closed += (_, _) => _clipboardTimer.Stop();
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
        var dialog = new OpenFolderDialog { Title = "Choose FootageFlow download folder", Multiselect = false };
        if (dialog.ShowDialog(this) == true) _viewModel.ChooseDownloadRoot(dialog.FolderName);
    }

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
