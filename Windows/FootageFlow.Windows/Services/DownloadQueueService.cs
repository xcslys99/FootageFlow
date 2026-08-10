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
    public ObservableCollection<DownloadTaskItem> Items { get; } = [];

    public DownloadQueueService(CoreHostClient core, SettingsService settings, YtDlpPlatformService ytDlp)
    {
        _core = core;
        _settings = settings;
        _ytDlp = ytDlp;
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("FootageFlow/0.2.0");
    }

    public DownloadTaskItem Enqueue(MediaAsset asset, Guid? projectId, string projectName)
    {
        var existing = Items.FirstOrDefault(x => x.Asset.StableId == asset.StableId && x.Status is not "Failed" and not "Cancelled");
        if (existing is not null) return existing;
        var item = new DownloadTaskItem(asset, projectId, projectName);
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
        item.Status = "Queued";
        _ = RunAsync(item);
    }

    private async Task RunAsync(DownloadTaskItem item)
    {
        try
        {
            await _slots.WaitAsync(item.Cancellation.Token);
            try
            {
                item.Status = "Downloading";
                var projectFolder = SanitizeWindowsName(string.IsNullOrWhiteSpace(item.ProjectName) ? "Uncategorized" : item.ProjectName);
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
                    saved = UniquePath(directory, preferredName);
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
                item.Status = "Completed";
                item.Speed = "";
            }
            finally { _slots.Release(); }
        }
        catch (OperationCanceledException)
        {
            item.Status = "Cancelled";
            item.Speed = "";
        }
        catch (Exception error)
        {
            item.Status = "Failed";
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

    private static string UniquePath(string directory, string preferredName)
    {
        var safe = SanitizeWindowsName(Path.GetFileNameWithoutExtension(preferredName));
        var extension = Path.GetExtension(preferredName);
        if (string.IsNullOrWhiteSpace(extension)) extension = ".mp4";
        var candidate = Path.Combine(directory, safe + extension);
        for (var index = 2; File.Exists(candidate) || File.Exists(candidate + ".part"); index++)
            candidate = Path.Combine(directory, $"{safe}_{index}{extension}");
        return candidate;
    }

    private static string SanitizeWindowsName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var clean = new string(value.Select(character => invalid.Contains(character) ? '_' : character).ToArray()).Trim(' ', '.');
        if (string.IsNullOrWhiteSpace(clean)) clean = "Media";
        var stem = clean.Split('.')[0].ToUpperInvariant();
        string[] reserved = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"];
        if (reserved.Contains(stem)) clean = "_" + clean;
        return clean.Length > 80 ? clean[..80] : clean;
    }

    private static string FriendlyMessage(Exception error) => error switch
    {
        HttpRequestException { StatusCode: System.Net.HttpStatusCode.TooManyRequests } => "Too many requests. Please try again later.",
        HttpRequestException => "The download server could not be reached.",
        ExternalToolException tool => tool.Message,
        CoreHostException core => core.Message,
        _ => error.Message
    };
}
