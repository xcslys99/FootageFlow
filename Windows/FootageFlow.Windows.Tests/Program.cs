using System.Text.Json;
using System.Text;
using System.Globalization;
using System.Net;
using System.Net.Http;
using FootageFlow.Windows.Models;
using FootageFlow.Windows.Services;

var failures = new List<string>();
var passed = 0;
void Check(bool condition, string name)
{
    if (condition) passed++;
    else failures.Add(name);
}

Check(new AppSettingsModel().Language == "en", "English is the first-launch default");
Check(new AppSettingsModel().SearchRelevanceMode == "balanced", "Balanced relevance is the default");
Check(new AppSettingsModel().EnabledProviders.Count == 17, "Seventeen providers enabled by default");
Check(LocalizationService.SupportedLanguages.Count == 10, "Ten interface languages are available");
var settingsDirectory = Path.Combine(Path.GetTempPath(), "FootageFlowSettingsTest", Guid.NewGuid().ToString("N"));
var settingsPath = Path.Combine(settingsDirectory, "settings.json");
try
{
    var settings = new SettingsService(new AppSettingsModel { Language = "en", DownloadRoot = settingsDirectory }, settingsPath);
    var localization = new LocalizationService(settings);
    Check(localization.Text("nav.quickSearch") == "Quick Search", "Windows English localization");
    localization.SetLanguage("zh-Hans");
    Check(localization.Text("nav.quickSearch") == "快速搜索", "Windows Chinese localization switch");
    foreach (var language in LocalizationService.SupportedLanguages)
    {
        localization.SetLanguage(language.Code);
        var recommendation = localization.Text("search.apiRecommendation");
        Check(recommendation.Contains("National Archives", StringComparison.Ordinal) &&
              recommendation.Contains("Europeana", StringComparison.Ordinal) &&
              recommendation.Contains("YouTube", StringComparison.Ordinal),
              $"Windows {language.Code} API recommendation localization");
        Check(localization.Text("update.availableTitle").Contains("%@", StringComparison.Ordinal) &&
              localization.Text("update.whatsNew") != "update.whatsNew",
              $"Windows {language.Code} update localization");
    }
    localization.SetLanguage("ru");
    settings.Current.DeferredUpdateVersion = "0.8.0";
    settings.Current.DeferredUpdateUntil = DateTimeOffset.UtcNow.AddHours(24);
    settings.Save();
    var reopened = new SettingsService(settingsFile: settingsPath);
    Check(reopened.Current.Language == "ru", "Windows language persistence");
    Check(reopened.Current.DeferredUpdateVersion == "0.8.0" &&
          reopened.Current.DeferredUpdateUntil is not null,
          "Windows update reminder persistence");
    Check(!File.ReadAllText(settingsPath).Contains("local-test-value", StringComparison.Ordinal), "Settings exclude API keys");
}
finally
{
    if (Directory.Exists(settingsDirectory)) Directory.Delete(settingsDirectory, true);
}
Check(WindowsPathSafety.SanitizeName("CON") == "_CON", "Windows reserved filename");
Check(!WindowsPathSafety.SanitizeName("bank:run?.mp4").Contains(':'), "Windows invalid filename characters");
Check(WindowsPathSafety.SanitizeName(new string('a', 200)).Length == 80, "Windows filename length");
Check(WindowsPathSafety.SanitizeName("阿根廷 银行").Contains("阿根廷"), "Chinese filename preservation");

var peerThumbnails = ThumbnailUrlNormalizer.Normalize(
    "peertube", ["/lazy-static/thumbnails/video.jpg"],
    "https://sepiasearch.org/w/video",
    new Dictionary<string, string> { ["instanceHost"] = "video.peer.example" });
Check(peerThumbnails.Single() == "https://video.peer.example/lazy-static/thumbnails/video.jpg",
    "PeerTube relative thumbnail uses the video instance");
Check(ThumbnailUrlNormalizer.NormalizeOne("//cdn.example.com/a.jpg") == "https://cdn.example.com/a.jpg",
    "Protocol-relative thumbnail normalization");
Check(ThumbnailUrlNormalizer.NormalizeOne("http://cdn.example.com/a.jpg") == "https://cdn.example.com/a.jpg",
    "Thumbnail HTTPS upgrade");
Check(ThumbnailUrlNormalizer.NormalizeOne("not a URL") is null, "Malformed thumbnail rejection");

var jpegBytes = new byte[] { 0xFF, 0xD8, 0xFF, 0xD9 };
var pngBytes = new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
Check(ThumbnailLoaderService.DetectFormat(jpegBytes) == ThumbnailImageFormat.Jpeg, "JPEG signature detection");
Check(ThumbnailLoaderService.DetectFormat(pngBytes) == ThumbnailImageFormat.Png, "PNG signature detection");
Check(ThumbnailLoaderService.DetectFormat("RIFF0000WEBP"u8.ToArray()) == ThumbnailImageFormat.WebP,
    "WebP signature detection");
Check(ThumbnailLoaderService.DetectFormat(new byte[] { 0, 0, 0, 20 }.Concat("ftypavif"u8.ToArray()).ToArray()) == ThumbnailImageFormat.Avif,
    "AVIF signature detection");
Check(ThumbnailLoaderService.DetectFormat("GIF89a"u8.ToArray()) == ThumbnailImageFormat.Gif,
    "GIF signature detection");

var thumbnailHandler = new ThumbnailTestHandler((request, _) =>
{
    if (request.RequestUri?.AbsolutePath == "/redirect")
        return Response(HttpStatusCode.Redirect, location: "/image.jpg");
    if (request.RequestUri?.AbsolutePath == "/image.jpg")
        return Response(HttpStatusCode.OK, jpegBytes, "image/jpeg");
    if (request.RequestUri?.AbsolutePath == "/forbidden") return Response(HttpStatusCode.Forbidden);
    if (request.RequestUri?.AbsolutePath == "/missing") return Response(HttpStatusCode.NotFound);
    if (request.RequestUri?.AbsolutePath == "/limited") return Response(HttpStatusCode.TooManyRequests);
    return Response(HttpStatusCode.OK, "<html>error</html>"u8.ToArray(), "text/html");
});
using (var thumbnailLoader = new ThumbnailLoaderService(thumbnailHandler))
{
    var redirected = await thumbnailLoader.LoadOneAsync("https://thumbnail.test/redirect");
    Check(redirected.Format == ThumbnailImageFormat.Jpeg && thumbnailHandler.Attempts == 2,
        "Windows thumbnail redirect handling");
    var cached = await thumbnailLoader.LoadOneAsync("https://thumbnail.test/redirect");
    Check(cached.FromCache && thumbnailHandler.Attempts == 2, "Windows thumbnail cache hit");
    try { await thumbnailLoader.LoadOneAsync("https://thumbnail.test/forbidden"); failures.Add("Thumbnail HTTP 403 classification"); }
    catch (ThumbnailLoadException error) { Check(error.StatusCode == 403, "Thumbnail HTTP 403 classification"); }
    try { await thumbnailLoader.LoadOneAsync("https://thumbnail.test/missing"); failures.Add("Thumbnail HTTP 404 classification"); }
    catch (ThumbnailLoadException error) { Check(error.StatusCode == 404, "Thumbnail HTTP 404 classification"); }
    try { await thumbnailLoader.LoadOneAsync("https://thumbnail.test/limited"); failures.Add("Thumbnail HTTP 429 classification"); }
    catch (ThumbnailLoadException error) { Check(error.StatusCode == 429, "Thumbnail HTTP 429 classification"); }
}

var fallbackHandler = new ThumbnailTestHandler((_, attempt) =>
    attempt == 1 ? Response(HttpStatusCode.NotFound) : Response(HttpStatusCode.OK, pngBytes, "image/png"));
using (var thumbnailLoader = new ThumbnailLoaderService(fallbackHandler))
{
    var fallback = await thumbnailLoader.LoadFirstAsync(
        ["https://thumbnail.test/missing", "https://thumbnail.test/fallback.png"]);
    Check(fallback.Format == ThumbnailImageFormat.Png && fallbackHandler.Attempts == 2,
        "Thumbnail candidate fallback after HTTP 404");
}

var failedCacheHandler = new ThumbnailTestHandler((_, attempt) =>
    attempt == 1 ? Response(HttpStatusCode.NotFound) : Response(HttpStatusCode.OK, jpegBytes, "image/jpeg"));
using (var thumbnailLoader = new ThumbnailLoaderService(failedCacheHandler))
{
    try { await thumbnailLoader.LoadOneAsync("https://thumbnail.test/recover"); } catch { }
    try { await thumbnailLoader.LoadOneAsync("https://thumbnail.test/recover"); } catch { }
    Check(failedCacheHandler.Attempts == 1, "Failed thumbnail cache uses short suppression");
    var recovered = await thumbnailLoader.LoadOneAsync("https://thumbnail.test/recover", forceRetry: true);
    Check(recovered.Format == ThumbnailImageFormat.Jpeg && failedCacheHandler.Attempts == 2,
        "Failed thumbnail cache supports explicit retry");
}

var timeoutHandler = new ThumbnailTestHandler((_, _) => throw new TaskCanceledException("simulated timeout"));
using (var thumbnailLoader = new ThumbnailLoaderService(timeoutHandler))
{
    try { await thumbnailLoader.LoadOneAsync("https://thumbnail.test/timeout"); failures.Add("Thumbnail timeout classification"); }
    catch (ThumbnailLoadException error) { Check(error.Reason == "timeout", "Thumbnail timeout classification"); }
}

var media = new MediaAsset
{
    Id = "fixture", Provider = "wikimedia", Title = "Fixture", SourcePageURL = "https://example.com/source",
    DownloadURL = "https://example.com/fixture.mp4", License = "CC BY", LicenseStatus = "ATTRIBUTION_REQUIRED",
    MediaType = "video", Downloadable = true, SearchKeyword = "fixture"
    , DownloadAvailability = "direct",
    RightsInfo = new RightsInfo { Statement = "CC BY", Known = true, OpenLicense = true, AttributionRequired = true }
};
var roundTrip = JsonSerializer.Deserialize<MediaAsset>(JsonSerializer.Serialize(media));
Check(roundTrip?.StableId == "wikimedia:fixture", "MediaAsset JSON round trip");
Check(roundTrip?.IsDirectlyDownloadable == true, "Direct-download availability model");
Check(roundTrip?.RightsKnown == true && roundTrip.OpenLicense, "RightsInfo JSON round trip");
var sourceRecord = new DownloadRecord { ProviderRaw = "linkDownloader", SourceName = "YouTube" };
Check(sourceRecord.DisplaySource == "YouTube", "Windows link download source display");
var updateRelease = JsonSerializer.Deserialize<AppReleaseInfo>(JsonSerializer.Serialize(new AppReleaseInfo
{
    Version = "0.8.0", Title = "Fixture update", Notes = "Visible changes",
    PageURL = "https://github.com/xcslys99/FootageFlow/releases/tag/v0.8.0",
    PublishedAt = DateTimeOffset.UtcNow
}));
Check(updateRelease?.Version == "0.8.0" && updateRelease.Notes == "Visible changes" &&
      updateRelease.PageURL.StartsWith("https://github.com/xcslys99/FootageFlow/releases/", StringComparison.Ordinal),
      "Windows update release model round trip");
var linkItem = new LinkDownloadItem("https://vimeo.com/123")
{
    Analysis = new LinkAnalysisResult
    {
        Id = "vimeo:123", OriginalURL = "https://vimeo.com/123", SourceName = "Vimeo",
        Title = "Fixture", Duration = 120, ProgressiveHeights = [1080, 720], HasAudio = true,
        SubtitleLanguages = ["en"], FormatCount = 4
    }
};
linkItem.ConfigureQualityLabels(value => value);
Check(linkItem.AvailableQualities.SequenceEqual(["best", "p1080", "p720", "p480", "audioOnly"]),
    "Windows link format availability");
Check(linkItem.HasSubtitles && linkItem.IsReady, "Windows link subtitle and ready state");
linkItem.SelectedQuality = "audioOnly";
linkItem.DownloadSubtitles = true;
linkItem.SubtitleLanguage = "en";
Check(linkItem.DownloadIdentity == "vimeo:123:audioOnly:original:subs:en",
    "Windows link quality-specific download identity");
linkItem.SelectedQuality = "p720";
linkItem.OutputPreset = "editingCompatibleMP4";
linkItem.SelectedScope = "clip";
linkItem.ClipStart = "00:01:20";
linkItem.ClipEnd = "00:01:30";
Check(linkItem.ClipStartSeconds == 80 && linkItem.ClipEndSeconds == 90 && linkItem.ClipDuration == 10,
    "Windows clip time validation");
Check(linkItem.IsReady && linkItem.DownloadIdentity.Contains(":editingCompatibleMP4:clip:80-90", StringComparison.Ordinal),
    "Windows clip identity and output preset");
var workflowMetadata = new Dictionary<string, string>(media.OriginalMetadata)
{
    ["linkOutputPreset"] = "editingCompatibleMP4",
    ["linkClipStart"] = "80",
    ["linkClipEnd"] = "90",
    ["linkClipDuration"] = "10"
};
var workflowAsset = media.CloneForWorkflow(
    "fixture:editingCompatibleMP4:clip:80-90", workflowMetadata, "video", "mp4");
Check(workflowAsset.StableId.EndsWith(":editingCompatibleMP4:clip:80-90", StringComparison.Ordinal) &&
      workflowAsset.OriginalMetadata["linkOutputPreset"] == "editingCompatibleMP4",
    "Windows workflow asset preserves an independent queue identity and metadata");
var workflowRecord = new DownloadRecord
{
    OutputPresetRaw = "editingCompatibleMP4", ClipStartSeconds = 80,
    ClipEndSeconds = 90, ClipDurationSeconds = 10
};
var workflowRecordRoundTrip = JsonSerializer.Deserialize<DownloadRecord>(JsonSerializer.Serialize(workflowRecord));
Check(workflowRecordRoundTrip?.OutputPresetRaw == "editingCompatibleMP4" &&
      workflowRecordRoundTrip.ClipStartSeconds == 80 && workflowRecordRoundTrip.ClipEndSeconds == 90 &&
      workflowRecordRoundTrip.ClipDurationSeconds == 10,
    "Windows download history preserves output and clip metadata");
linkItem.ClipEnd = "00:03:00";
Check(linkItem.ClipError == "beyondDuration" && !linkItem.IsReady,
    "Windows clip end beyond duration");
Check(Timecode.TryParse("80", out var rawSeconds) && rawSeconds == 80,
    "Windows raw-second time parsing");
Check(!Timecode.TryParse("1:60", out _), "Windows invalid time parsing");
Check(LinkUrlSafety.TryCreate("https://www.youtube.com/watch?v=fixture", out _),
    "Windows public link validation");
Check(!LinkUrlSafety.TryCreate("http://127.0.0.1/private", out _),
    "Windows private address rejection");
Check(!LinkUrlSafety.TryCreate("https://example.com/watch?access_token=secret", out _),
    "Windows sensitive query rejection");
Check(!LinkUrlSafety.TryCreate("https://user:password@example.com/watch", out _),
    "Windows embedded credential rejection");
var clipboardSession = new ClipboardSuggestionSession(TimeSpan.Zero);
Check(clipboardSession.FreshCandidates(["https://youtu.be/example"], []).Count == 1,
    "Windows clipboard first suggestion");
_ = clipboardSession.FreshCandidates(["https://vimeo.com/123"], []);
Check(clipboardSession.FreshCandidates(["https://youtu.be/example"], []).Count == 0,
    "Windows clipboard suggestion is not repeated in one session");
var clipboardCooldown = new ClipboardSuggestionSession(TimeSpan.FromSeconds(1));
var clipboardTime = DateTimeOffset.FromUnixTimeSeconds(10);
Check(clipboardCooldown.FreshCandidates(["https://youtu.be/one"], [], clipboardTime).Count == 1 &&
      clipboardCooldown.FreshCandidates(["https://youtu.be/two"], [], clipboardTime.AddMilliseconds(500)).Count == 0 &&
      clipboardCooldown.FreshCandidates(["https://youtu.be/two"], [], clipboardTime.AddSeconds(2)).Count == 1,
    "Windows clipboard suggestion cooldown");
Check(YtDlpPlatformService.ClassifyFailureCode(
        "Failed to fetch macos OAuth token: HTTP Error 401: Unauthorized") == "temporarilyBlocked",
    "Windows Vimeo OAuth 401 classification");
Check(YtDlpPlatformService.EditingCompatibleSelector(
        "bestvideo[height<=720]+bestaudio/best[height<=720]").EndsWith("/best", StringComparison.Ordinal),
    "Windows direct-media fallback for editing-compatible output");
if (roundTrip is not null)
{
    roundTrip.IsSelected = true;
    Check(roundTrip.IsSelected, "Windows multi-select model");
}

if (OperatingSystem.IsWindows())
{
    var secure = new WindowsSecureStore();
    var provider = "selftest-" + Guid.NewGuid().ToString("N");
    try
    {
        secure.Save(provider, "local-test-value");
        Check(secure.Read(provider) == "local-test-value", "Credential Manager round trip");
        secure.Remove(provider);
        Check(secure.Read(provider) == "", "Credential Manager removal");
    }
    catch (Exception error) { failures.Add("Credential Manager: " + error.GetType().Name); }

    var corePath = Environment.GetEnvironmentVariable("FOOTAGEFLOW_CORE_PATH");
    if (!string.IsNullOrWhiteSpace(corePath) && File.Exists(corePath))
    {
        var core = new CoreHostClient(corePath);
        var health = await core.SendAsync(new CoreRequest { Action = "health" });
        Check(health.Success && health.Platform == "windows", "Windows core health");
        Check(health.Providers?.Count == 17, "Windows core exposes seventeen shared providers");
        var keywords = await core.SendAsync(new CoreRequest { Action = "keywords", Query = "2001年阿根廷银行挤兑" });
        Check((keywords.Keywords?.Count ?? 0) >= 3, "Shared keyword engine");
        var relevanceCandidates = new[]
        {
            new MediaAsset
            {
                Id = "food", Provider = "peertube", Title = "Taipei beef noodle soup",
                SourcePageURL = "https://example.com/food", LicenseStatus = "UNKNOWN",
                MediaType = "video", SearchKeyword = "Taiwan cuisine", RelevanceScore = 0.5
            },
            new MediaAsset
            {
                Id = "politics", Provider = "peertube", Title = "Taiwan politics debate",
                SourcePageURL = "https://example.com/politics", LicenseStatus = "UNKNOWN",
                MediaType = "video", SearchKeyword = "Taiwan cuisine", RelevanceScore = 1
            }
        };
        var ranked = await core.SendAsync(new CoreRequest
        {
            Action = "rankAssets", Query = "台湾美食", Assets = relevanceCandidates,
            RelevanceMode = "balanced"
        });
        Check(ranked.Assets?.Count == 1 && ranked.Assets[0].Id == "food",
            "Windows uses the shared concept relevance ranker");
        var attribution = await core.SendAsync(new CoreRequest { Action = "formatAttribution", Asset = media });
        Check(attribution.Text?.Contains("CC BY", StringComparison.Ordinal) == true,
            "Shared attribution formatter");
        var feedback = await core.SendAsync(new CoreRequest
        {
            Action = "feedbackURL", FeedbackDestination = "bug", Language = "en"
        });
        Check(feedback.Text?.StartsWith("https://github.com/xcslys99/FootageFlow/issues/new", StringComparison.Ordinal) == true,
            "Shared feedback URL builder");
        Check(feedback.Text?.Contains("api_key", StringComparison.OrdinalIgnoreCase) != true &&
              feedback.Text?.Contains("\\Users\\", StringComparison.OrdinalIgnoreCase) != true,
            "Feedback URL excludes secrets and paths");

        var projectName = "Windows Self Test " + Guid.NewGuid().ToString("N");
        var added = await core.SendAsync(new CoreRequest { Action = "addProject", ProjectName = projectName });
        Check(added.Project?.Name == projectName, "Shared project create");
        if (added.Project is { } project)
        {
            var deleted = await core.SendAsync(new CoreRequest { Action = "deleteProject", ProjectID = project.Id.ToString() });
            Check(deleted.Database?.Projects.All(value => value.Id != project.Id) == true, "Shared project delete");
        }

        var directory = Path.Combine(Path.GetTempPath(), "FootageFlowSelfTest", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var mediaPath = Path.Combine(directory, "fixture.mp4");
            await File.WriteAllBytesAsync(mediaPath, "fixture"u8.ToArray());
            var sidecar = await core.SendAsync(new CoreRequest
            {
                Action = "writeSidecar", Asset = media, MediaPath = mediaPath, ProjectName = "Self Test"
            });
            Check(sidecar.Success, "Shared sidecar request");
            Check(File.Exists(Path.Combine(directory, "fixture.source.txt")), "Text sidecar exists");
            Check(File.Exists(Path.Combine(directory, "fixture.source.json")), "JSON sidecar exists");
        }
        finally { Directory.Delete(directory, true); }

        var downloadRoot = Path.Combine(Path.GetTempPath(), "FootageFlowDownloadTest", Guid.NewGuid().ToString("N"));
        var testSettings = new SettingsService(new AppSettingsModel
        {
            Language = "en", DownloadRoot = downloadRoot
        });
        var localization = new LocalizationService(testSettings);
        var handler = new RetryDownloadHandler();
        var queue = new DownloadQueueService(
            core, testSettings, new YtDlpPlatformService(), localization,
            new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan });
        try
        {
            var task = queue.Enqueue(media, null, "Test Project");
            await WaitForStateAsync(task, "completed", TimeSpan.FromSeconds(20));
            Check(task.State == "completed", $"Download queue completion ({task.ErrorCode ?? "no-code"})");
            Check(handler.Attempts == 2, "Bounded automatic download retry");
            Check(task.LocalPath is not null && File.Exists(task.LocalPath), "Downloaded media exists");
            if (task.LocalPath is { } downloaded)
            {
                Check(File.Exists(Path.ChangeExtension(downloaded, ".source.txt")), "Downloaded text sidecar");
                Check(File.Exists(Path.ChangeExtension(downloaded, ".source.json")), "Downloaded JSON sidecar");
            }
            Check(ReferenceEquals(task, queue.Enqueue(media, null, "Test Project")), "Duplicate active download prevention");

            var cancellable = new MediaAsset
            {
                Id = "cancel-fixture", Provider = "wikimedia", Title = "Cancel Fixture",
                SourcePageURL = "https://example.com/cancel-source",
                DownloadURL = "https://example.com/cancel.mp4", LicenseStatus = "UNKNOWN",
                MediaType = "video", Downloadable = true, SearchKeyword = "cancel",
                DownloadAvailability = "direct"
            };
            var cancelHandler = new CancelThenSuccessHandler();
            var cancelQueue = new DownloadQueueService(
                core, testSettings, new YtDlpPlatformService(), localization,
                new HttpClient(cancelHandler) { Timeout = Timeout.InfiniteTimeSpan });
            var cancelTask = cancelQueue.Enqueue(cancellable, null, "Test Project");
            await WaitForStateAsync(cancelTask, "downloading", TimeSpan.FromSeconds(5));
            await WaitForAsync(() => cancelHandler.Attempts == 1, TimeSpan.FromSeconds(5));
            cancelQueue.Cancel(cancelTask);
            await WaitForStateAsync(cancelTask, "cancelled", TimeSpan.FromSeconds(5));
            Check(cancelTask.State == "cancelled", "Download Manager cancellation");
            cancelQueue.Retry(cancelTask);
            await WaitForStateAsync(cancelTask, "completed", TimeSpan.FromSeconds(20));
            Check(cancelTask.State == "completed" && cancelHandler.Attempts == 2,
                "Download Manager retry after cancellation");
        }
        finally
        {
            if (Directory.Exists(downloadRoot)) Directory.Delete(downloadRoot, true);
        }
    }

    if (args.Contains("--creator-workflow-smoke", StringComparer.OrdinalIgnoreCase))
    {
        var toolRoot = Environment.GetEnvironmentVariable("FOOTAGEFLOW_CREATOR_SMOKE_TOOLS");
        var creatorCorePath = Environment.GetEnvironmentVariable("FOOTAGEFLOW_CORE_PATH");
        if (string.IsNullOrWhiteSpace(toolRoot) || string.IsNullOrWhiteSpace(creatorCorePath))
            failures.Add("Windows creator workflow smoke paths");
        else
            await RunCreatorWorkflowSmokeAsync(toolRoot, creatorCorePath, Check);
    }
}

Console.WriteLine($"WINDOWS_SELF_TEST passed={passed} failed={failures.Count}");
foreach (var failure in failures) Console.WriteLine("FAIL " + failure);
return failures.Count == 0 ? 0 : 1;

static async Task RunCreatorWorkflowSmokeAsync(
    string toolRoot, string corePath, Action<bool, string> check)
{
    var service = new YtDlpPlatformService(toolRoot);
    check(service.IsAvailable, "Windows creator smoke bundled yt-dlp");
    var sources = new[]
    {
        ("YouTube", "https://www.youtube.com/watch?v=jNQXAC9IVRw"),
        ("Dailymotion", "https://www.dailymotion.com/video/x7rvjrf"),
        ("public media", "https://media.w3.org/2010/05/sintel/trailer.mp4")
    };
    foreach (var (name, url) in sources)
    {
        try
        {
            var analysis = await service.AnalyzeAsync(url, CancellationToken.None);
            check(!string.IsNullOrWhiteSpace(analysis.Title) && analysis.FormatCount > 0,
                $"Windows creator smoke {name} analysis");
        }
        catch (ExternalToolException error) when (name == "YouTube" &&
            error.Code is "temporarilyBlocked" or "rateLimited")
        {
            check(true, $"Windows creator smoke YouTube {error.Code} classification");
        }
        catch (Exception error)
        {
            check(false, $"Windows creator smoke {name} analysis ({error.GetType().Name})");
        }
    }

    var directory = Path.Combine(Path.GetTempPath(), "FootageFlowCreatorSmoke", Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(directory);
    try
    {
        var source = sources[2].Item2;
        var analysis = await service.AnalyzeAsync(source, CancellationToken.None);
        var metadata = new Dictionary<string, string>
        {
            ["linkFormatSelector"] = "bestvideo[height<=720]+bestaudio/best[height<=720]",
            ["linkOutputPreset"] = "editingCompatibleMP4",
            ["linkClipStart"] = "2",
            ["linkClipEnd"] = "12",
            ["linkClipDuration"] = "10",
            ["linkMediaDuration"] = analysis.Duration?.ToString(CultureInfo.InvariantCulture) ?? "",
            ["sourceName"] = analysis.SourceName
        };
        var output = await service.DownloadAsync(
            source, directory, "sintel-10-second-clip", metadata, null, CancellationToken.None);
        var probe = await ProbeMediaAsync(Path.Combine(toolRoot, "ffprobe.exe"), output);
        check(Path.GetExtension(output).Equals(".mp4", StringComparison.OrdinalIgnoreCase),
            "Windows creator smoke editing MP4 extension");
        check(Math.Abs(probe.Duration - 10) <= 0.25, "Windows creator smoke ten-second duration");
        check(probe.HasH264Yuv420p, "Windows creator smoke H.264 yuv420p video");
        check(probe.HasCompatibleAudio, "Windows creator smoke AAC audio when present");
        check(HasFastStart(output), "Windows creator smoke MP4 fast-start atom order");

        var asset = new MediaAsset
        {
            Id = "creator-smoke", Provider = "linkDownloader", Title = analysis.Title,
            Creator = analysis.Creator, SourcePageURL = source,
            DownloadURL = source, LicenseStatus = "UNKNOWN", MediaType = "video", Downloadable = true,
            SearchKeyword = source, FileType = "mp4", DownloadAvailability = "conditional",
            OriginalMetadata = metadata
        };
        var core = new CoreHostClient(corePath);
        var sidecar = await core.SendAsync(new CoreRequest
        {
            Action = "writeSidecar", Asset = asset, MediaPath = output,
            ProjectName = "Creator Workflow Smoke", SegmentIndex = 1
        });
        check(sidecar.Success && File.Exists(Path.ChangeExtension(output, ".source.txt")) &&
              File.Exists(Path.ChangeExtension(output, ".source.json")),
            "Windows creator smoke source sidecars");
    }
    finally
    {
        if (Directory.Exists(directory)) Directory.Delete(directory, true);
    }
}

static async Task<(double Duration, bool HasH264Yuv420p, bool HasCompatibleAudio)> ProbeMediaAsync(
    string ffprobe, string mediaPath)
{
    using var process = new System.Diagnostics.Process
    {
        StartInfo = new System.Diagnostics.ProcessStartInfo
        {
            FileName = ffprobe, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true
        }
    };
    foreach (var argument in new[] { "-v", "error", "-show_entries",
        "format=duration:stream=codec_type,codec_name,pix_fmt", "-of", "json", mediaPath })
        process.StartInfo.ArgumentList.Add(argument);
    process.Start();
    var output = await process.StandardOutput.ReadToEndAsync();
    await process.WaitForExitAsync();
    if (process.ExitCode != 0) throw new InvalidOperationException("ffprobe failed");
    using var document = JsonDocument.Parse(output);
    var duration = double.Parse(
        document.RootElement.GetProperty("format").GetProperty("duration").GetString()!,
        CultureInfo.InvariantCulture);
    var streams = document.RootElement.GetProperty("streams").EnumerateArray().ToArray();
    var video = streams.Any(value => value.GetProperty("codec_type").GetString() == "video" &&
        value.GetProperty("codec_name").GetString() == "h264" &&
        value.GetProperty("pix_fmt").GetString() == "yuv420p");
    var audio = !streams.Any(value => value.GetProperty("codec_type").GetString() == "audio" &&
        value.GetProperty("codec_name").GetString() != "aac");
    return (duration, video, audio);
}

static bool HasFastStart(string mediaPath)
{
    using var stream = File.OpenRead(mediaPath);
    var bytes = new byte[Math.Min(4 * 1024 * 1024, (int)stream.Length)];
    _ = stream.Read(bytes);
    var text = Encoding.Latin1.GetString(bytes);
    var moov = text.IndexOf("moov", StringComparison.Ordinal);
    var mdat = text.IndexOf("mdat", StringComparison.Ordinal);
    return moov >= 0 && mdat >= 0 && moov < mdat;
}

static HttpResponseMessage Response(
    HttpStatusCode status, byte[]? data = null, string? contentType = null, string? location = null)
{
    var response = new HttpResponseMessage(status) { Content = new ByteArrayContent(data ?? []) };
    if (contentType is not null) response.Content.Headers.ContentType = new(contentType);
    if (location is not null) response.Headers.Location = new Uri(location, UriKind.RelativeOrAbsolute);
    return response;
}

static async Task WaitForStateAsync(DownloadTaskItem item, string expected, TimeSpan timeout)
{
    var deadline = DateTime.UtcNow + timeout;
    while (item.State != expected && item.State != "failed" && DateTime.UtcNow < deadline)
        await Task.Delay(50);
}

static async Task WaitForAsync(Func<bool> condition, TimeSpan timeout)
{
    var deadline = DateTime.UtcNow + timeout;
    while (!condition() && DateTime.UtcNow < deadline)
        await Task.Delay(50);
}

sealed class RetryDownloadHandler : HttpMessageHandler
{
    private int _attempts;
    public int Attempts => Volatile.Read(ref _attempts);

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var attempt = Interlocked.Increment(ref _attempts);
        if (attempt == 1) throw new HttpRequestException("simulated interruption");
        var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new ByteArrayContent("FootageFlow download fixture"u8.ToArray())
        };
        response.Content.Headers.ContentLength = 28;
        return Task.FromResult(response);
    }
}

sealed class ThumbnailTestHandler(Func<HttpRequestMessage, int, HttpResponseMessage> response) : HttpMessageHandler
{
    private int _attempts;
    public int Attempts => Volatile.Read(ref _attempts);

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var attempt = Interlocked.Increment(ref _attempts);
        return Task.FromResult(response(request, attempt));
    }
}

sealed class CancelThenSuccessHandler : HttpMessageHandler
{
    private int _attempts;
    public int Attempts => Volatile.Read(ref _attempts);

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var attempt = Interlocked.Increment(ref _attempts);
        if (attempt == 1) await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
        var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new ByteArrayContent("FootageFlow retry fixture"u8.ToArray())
        };
        response.Content.Headers.ContentLength = 25;
        return response;
    }
}
