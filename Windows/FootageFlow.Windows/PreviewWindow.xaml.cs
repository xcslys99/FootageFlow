using System.Windows;
using System.Windows.Media.Imaging;
using FootageFlow.Windows.Models;
using FootageFlow.Windows.Services;

namespace FootageFlow.Windows;

public partial class PreviewWindow : Window
{
    private readonly MediaAsset _asset;
    private readonly Func<string, string> _text;

    public PreviewWindow(MediaAsset asset, Func<string, string> text)
    {
        _asset = asset;
        _text = text;
        InitializeComponent();
        Title = asset.Title;
        PlayButton.Content = $"▶ {_text("media.play")}";
        PauseButton.Content = $"⏸ {_text("media.pause")}";
        MuteButton.Content = $"🔊 {_text("media.mute")}";
        OpenSourceButton.Content = _text("media.openSource");
        if (asset.MediaType == "image")
        {
            ImagePreview.Visibility = Visibility.Visible;
            Player.Visibility = Visibility.Collapsed;
            var value = asset.PreviewURL ?? asset.DownloadURL ?? asset.ThumbnailURL;
            if (Uri.TryCreate(value, UriKind.Absolute, out var imageUri)) ImagePreview.Source = new BitmapImage(imageUri);
        }
        else
        {
            var value = asset.PreviewURL ?? (asset.Provider == "youtube" ? null : asset.DownloadURL);
            if (Uri.TryCreate(value, UriKind.Absolute, out var mediaUri))
            {
                Player.Source = mediaUri;
                Player.Play();
            }
            else
            {
                MessageBox.Show(_text("media.previewUnavailable"), "FootageFlow");
            }
        }
    }

    private void Player_MediaOpened(object sender, RoutedEventArgs e)
    {
        if (Player.NaturalDuration.HasTimeSpan) PositionSlider.Maximum = Player.NaturalDuration.TimeSpan.TotalSeconds;
    }
    private void Player_MediaEnded(object sender, RoutedEventArgs e) => Player.Stop();
    private void Play_Click(object sender, RoutedEventArgs e) => Player.Play();
    private void Pause_Click(object sender, RoutedEventArgs e) => Player.Pause();
    private void Mute_Click(object sender, RoutedEventArgs e)
    {
        Player.IsMuted = !Player.IsMuted;
        MuteButton.Content = Player.IsMuted ? $"🔇 {_text("media.unmute")}" : $"🔊 {_text("media.mute")}";
    }
    private void PositionSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (Player.NaturalDuration.HasTimeSpan) Player.Position = TimeSpan.FromSeconds(e.NewValue);
    }
    private void OpenSource_Click(object sender, RoutedEventArgs e) => ShellService.OpenUrl(_asset.SourcePageURL);
}
