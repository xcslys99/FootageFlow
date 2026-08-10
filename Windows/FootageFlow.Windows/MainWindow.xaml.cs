using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using FootageFlow.Windows.Models;
using FootageFlow.Windows.ViewModels;
using Microsoft.Win32;

namespace FootageFlow.Windows;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel = new();

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _viewModel;
        _viewModel.PreviewRequested += asset =>
        {
            if (asset is not null) new PreviewWindow(asset, _viewModel.T) { Owner = this }.Show();
        };
    }

    private void LanguageButton_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        var english = new MenuItem { Header = "English" };
        english.Click += (_, _) => _viewModel.SetLanguage("en");
        var chinese = new MenuItem { Header = "简体中文" };
        chinese.Click += (_, _) => _viewModel.SetLanguage("zh-Hans");
        menu.Items.Add(english); menu.Items.Add(chinese);
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
