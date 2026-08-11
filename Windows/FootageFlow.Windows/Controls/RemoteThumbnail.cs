using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using FootageFlow.Windows.Services;

namespace FootageFlow.Windows.Controls;

public sealed class RemoteThumbnail : Grid
{
    public static readonly DependencyProperty CandidateURLsProperty = DependencyProperty.Register(
        nameof(CandidateURLs), typeof(IEnumerable<string>), typeof(RemoteThumbnail),
        new PropertyMetadata(null, OnSourceChanged));
    public static readonly DependencyProperty SourceURLProperty = DependencyProperty.Register(
        nameof(SourceURL), typeof(string), typeof(RemoteThumbnail),
        new PropertyMetadata(null, OnSourceChanged));
    public static readonly DependencyProperty FailureTextProperty = DependencyProperty.Register(
        nameof(FailureText), typeof(string), typeof(RemoteThumbnail),
        new PropertyMetadata("Thumbnail unavailable", OnFailureTextChanged));
    public static readonly DependencyProperty RetryTextProperty = DependencyProperty.Register(
        nameof(RetryText), typeof(string), typeof(RemoteThumbnail),
        new PropertyMetadata("Retry thumbnail", OnRetryTextChanged));

    private readonly Image _image;
    private readonly ProgressBar _progress;
    private readonly StackPanel _failure;
    private readonly TextBlock _failureLabel;
    private readonly Button _retry;
    private CancellationTokenSource? _cancellation;
    private int _generation;

    public RemoteThumbnail()
    {
        Background = new SolidColorBrush(Color.FromRgb(233, 237, 242));
        ClipToBounds = true;
        _image = new Image { Stretch = Stretch.UniformToFill, Visibility = Visibility.Collapsed };
        _progress = new ProgressBar
        {
            IsIndeterminate = true, Width = 58, Height = 4,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        _failureLabel = new TextBlock
        {
            Text = FailureText, FontSize = 11, Foreground = Brushes.DimGray,
            TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap,
            MaxWidth = 150
        };
        _retry = new Button
        {
            Content = "↻", ToolTip = RetryText, Padding = new Thickness(5, 1, 5, 1),
            MinHeight = 22, Margin = new Thickness(0, 3, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Center
        };
        _retry.Click += (_, _) => { _generation++; _ = ReloadAsync(forceRetry: true); };
        _failure = new StackPanel
        {
            Visibility = Visibility.Collapsed,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        _failure.Children.Add(_failureLabel);
        _failure.Children.Add(_retry);
        Children.Add(_image);
        Children.Add(_progress);
        Children.Add(_failure);
        Loaded += (_, _) => _ = ReloadAsync(forceRetry: false);
        Unloaded += (_, _) => Cancel();
    }

    public IEnumerable<string>? CandidateURLs
    {
        get => (IEnumerable<string>?)GetValue(CandidateURLsProperty);
        set => SetValue(CandidateURLsProperty, value);
    }
    public string? SourceURL
    {
        get => (string?)GetValue(SourceURLProperty);
        set => SetValue(SourceURLProperty, value);
    }
    public string FailureText
    {
        get => (string)GetValue(FailureTextProperty);
        set => SetValue(FailureTextProperty, value);
    }
    public string RetryText
    {
        get => (string)GetValue(RetryTextProperty);
        set => SetValue(RetryTextProperty, value);
    }

    private static void OnSourceChanged(DependencyObject value, DependencyPropertyChangedEventArgs args) =>
        _ = ((RemoteThumbnail)value).ReloadAsync(forceRetry: false);
    private static void OnFailureTextChanged(DependencyObject value, DependencyPropertyChangedEventArgs args) =>
        ((RemoteThumbnail)value)._failureLabel.Text = args.NewValue?.ToString() ?? "";
    private static void OnRetryTextChanged(DependencyObject value, DependencyPropertyChangedEventArgs args) =>
        ((RemoteThumbnail)value)._retry.ToolTip = args.NewValue?.ToString() ?? "";

    private async Task ReloadAsync(bool forceRetry)
    {
        if (!IsLoaded) return;
        Cancel();
        var localGeneration = _generation;
        _cancellation = new CancellationTokenSource();
        var token = _cancellation.Token;
        ShowLoading();
        var candidates = EnumerateCandidates().ToArray();
        foreach (var value in candidates)
        {
            try
            {
                var payload = await ThumbnailLoaderService.Shared.LoadOneAsync(value, forceRetry, token);
                token.ThrowIfCancellationRequested();
                var bitmap = Decode(payload.Data);
                if (bitmap is null)
                {
                    ThumbnailLoaderService.Shared.MarkDecodeFailure(value);
                    continue;
                }
                if (localGeneration != _generation) return;
                _image.Source = bitmap;
                _image.Visibility = Visibility.Visible;
                _progress.Visibility = Visibility.Collapsed;
                _failure.Visibility = Visibility.Collapsed;
                return;
            }
            catch (OperationCanceledException) { return; }
            catch { }
        }
        if (!token.IsCancellationRequested && localGeneration == _generation) ShowFailure();
    }

    private IEnumerable<string> EnumerateCandidates()
    {
        var values = new[] { SourceURL }.Concat(CandidateURLs ?? []);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var value in values)
        {
            var normalized = ThumbnailUrlNormalizer.NormalizeOne(value);
            if (normalized is not null && seen.Add(normalized)) yield return normalized;
        }
    }

    private static BitmapSource? Decode(byte[] data)
    {
        try
        {
            using var stream = new MemoryStream(data, writable: false);
            var decoder = BitmapDecoder.Create(
                stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            var frame = decoder.Frames.FirstOrDefault();
            frame?.Freeze();
            return frame;
        }
        catch { return null; }
    }

    private void ShowLoading()
    {
        _image.Source = null;
        _image.Visibility = Visibility.Collapsed;
        _failure.Visibility = Visibility.Collapsed;
        _progress.Visibility = Visibility.Visible;
    }

    private void ShowFailure()
    {
        _image.Visibility = Visibility.Collapsed;
        _progress.Visibility = Visibility.Collapsed;
        _failure.Visibility = Visibility.Visible;
    }

    private void Cancel()
    {
        _cancellation?.Cancel();
        _cancellation?.Dispose();
        _cancellation = null;
    }
}
