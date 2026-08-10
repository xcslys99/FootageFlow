using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Net.Http;
using FootageFlow.Windows.Models;

namespace FootageFlow.Windows.Services;

public sealed class DownloadQueueService
{
    private readonly SemaphoreSlim _slots = new(3, 3);
    private readonly HttpClient _http = new() { Timeout = Timeout.InfiniteTimeSpan };
    private readonly CoreHostClient _core;
    private readonly SettingsService _settings;
    private readonly YtDlpPlatformService _ytDlp;
    private readonly LocalizationService _localization;
    public ObservableCollection<DownloadTaskItem> Items { get; } = [];

    public DownloadQueueService(CoreHostClient core, SettingsService settings, YtDlpPlatformService ytDlp, LocalizationService localization)
    {
        _core = core;
        _settings = settings;
        _ytDlp = ytDlp;
        _localization = localization;
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("FootageFlow/0.2.0");
    }

    public DownloadTaskItem Enqueue(MediaAsset asset, Guid? projectId, string projectName)
    {
        var existing = Items.FirstOrDefault(x => x.Asset.StableId == asset.StableId && x.State is not "failed" and not "cancelled");
        if (existing is not null) return existing;
        var item = new DownloadTaskItem(asset, projectId, projectName);
        SetState(item, "waiting");
        Items.Insert(0, item);
        _ = RunAsync(item);
        return item;
    }

    public void Cancel(DownloadTaskItem item)
    {
        if (item.CanCancel) item.Cancellation.Cancel();
    }

    public void Retry(DownloadTaskItem item)
    {
        if (!item.CanRetry) return;
        item.ResetCancellation();
        item.ErrorMessage = null;
        item.Progress = 0;
        SetState(item, "waiting");
        _ = RunAsync(item);
    }

    public void RefreshLocalizedStatus()
    {
        foreach (var item in Items) SetState(item, item.State);
    }

    private async Task RunAsync(DownloadTaskItem item)
    {
        try
        {
            await _slots.WaitAsync(item.Cancellation.Token);
            try
            {
                SetState(item, "downloading");
                var projectFolder = WindowsPathSafety.SanitizeName(string.IsNullOrWhiteSpace(item.ProjectName) ? "Uncategorized" : item.ProjectName);
                var directory = Path.Combine(_settings.Current.DownloadRoot, projectFolder);
                Directory.CreateDirectory(directory);
                var nameResponse = await _core.SendAsync(new CoreRequest
                {
                    Action = "suggestFileName", Asset = item.Asset,
                    Language = _settings.Current.Language
                }, cancellationToken: item.Cancellation.Token);
                var preferredName = nameResponse.FileName ?? $"Media_{item.Asset.Id}.mp4";
                string saved;
                if (item.Asset.DownloadStrategy == "ytDLP" || item.Asset.Provider == "youtube")
                {
                    saved = await _ytDlp.DownloadAsync(
                        item.Asset.SourcePageURL, directory, Path.GetFileNameWithoutExtension(preferredName),
                        item.Cancellation.Token);
                    item.Progress = 100;
                }
                else
                {
                    if (string.IsNullOrWhiteSpace(item.Asset.DownloadURL))
                        throw new InvalidOperationException("This source does not provide a direct download.");
                    saved = WindowsPathSafety.UniquePath(directory, preferredName);
                    await DownloadDirectAsync(item.Asset.DownloadURL, saved, item, item.Cancellation.Token);
                }
                item.LocalPath = saved;
                var sidecar = await _core.SendAsync(new CoreRequest
                {
                    Action = "writeSidecar", Asset = item.Asset, MediaPath = saved,
                    ProjectName = item.ProjectName, ProjectID = item.ProjectId?.ToString(),
                    Language = _settings.Current.Language
                }, cancellationToken: item.Cancellation.Token);
                if (!sidecar.Success) throw new InvalidOperationException(sidecar.ErrorMessage ?? "Source information could not be saved.");
                await _core.SendAsync(new CoreRequest
                {
                    Action = "addDownload", Asset = item.Asset, LocalPath = saved,
                    ProjectID = item.ProjectId?.ToString(), Language = _settings.Current.Language
                }, cancellationToken: item.Cancellation.Token);
                SetState(item, "completed");
                item.Speed = "";
            }
            finally { _slots.Release(); }
        }
        catch (OperationCanceledException)
        {
            SetState(item, "cancelled");
            item.Speed = "";
        }
        catch (Exception error)
        {
            SetState(item, "failed");
            item.ErrorMessage = FriendlyMessage(error);
            item.Speed = "";
        }
    }

    private async Task DownloadDirectAsync(
        string url,
        string destination,
        DownloadTaskItem item,
        CancellationToken cancellationToken)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
            throw new InvalidOperationException("The provider returned an unsafe download address.");
        var temporary = destination + ".part";
        try
        {
            using var response = await _http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            response.EnsureSuccessStatusCode();
            var total = response.Content.Headers.ContentLength;
            await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 131072, true);
            var buffer = new byte[131072];
            long received = 0;
            var watch = Stopwatch.StartNew();
            int read;
            while ((read = await input.ReadAsync(buffer, cancellationToken)) > 0)
            {
                await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                received += read;
                if (total is > 0) item.Progress = Math.Min(100, received * 100d / total.Value);
                if (watch.Elapsed.TotalSeconds > 0.5)
                    item.Speed = $"{received / Math.Max(1, watch.Elapsed.TotalSeconds) / 1_048_576:0.0} MB/s";
            }
            await output.FlushAsync(cancellationToken);
            File.Move(temporary, destination);
            item.Progress = 100;
        }
        catch
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); }
            catch { }
            throw;
        }
    }

    private static string FriendlyMessage(Exception error) => error switch
    {
        HttpRequestException { StatusCode: System.Net.HttpStatusCode.TooManyRequests } => "Too many requests. Please try again later.",
        HttpRequestException => "The download server could not be reached.",
        ExternalToolException tool => tool.Message,
        CoreHostException core => core.Message,
        _ => error.Message
    };

    private void SetState(DownloadTaskItem item, string state)
    {
        item.State = state;
        item.Status = _localization.Text($"download.status.{state}");
    }
}
