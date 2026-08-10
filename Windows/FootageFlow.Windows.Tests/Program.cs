using System.Text.Json;
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
Check(new AppSettingsModel().EnabledProviders.Count == 15, "Fifteen providers enabled by default");
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
    }
    localization.SetLanguage("ru");
    var reopened = new SettingsService(settingsFile: settingsPath);
    Check(reopened.Current.Language == "ru", "Windows language persistence");
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
var linkItem = new LinkDownloadItem("https://vimeo.com/123")
{
    Analysis = new LinkAnalysisResult
    {
        Id = "vimeo:123", OriginalURL = "https://vimeo.com/123", SourceName = "Vimeo",
        Title = "Fixture", ProgressiveHeights = [1080, 720], HasAudio = true,
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
Check(linkItem.DownloadIdentity == "vimeo:123:audioOnly:subs:en",
    "Windows link quality-specific download identity");
Check(LinkUrlSafety.TryCreate("https://www.youtube.com/watch?v=fixture", out _),
    "Windows public link validation");
Check(!LinkUrlSafety.TryCreate("http://127.0.0.1/private", out _),
    "Windows private address rejection");
Check(!LinkUrlSafety.TryCreate("https://example.com/watch?access_token=secret", out _),
    "Windows sensitive query rejection");
Check(!LinkUrlSafety.TryCreate("https://user:password@example.com/watch", out _),
    "Windows embedded credential rejection");
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
        Check(health.Providers?.Count == 15, "Windows core exposes fifteen shared providers");
        var keywords = await core.SendAsync(new CoreRequest { Action = "keywords", Query = "2001年阿根廷银行挤兑" });
        Check((keywords.Keywords?.Count ?? 0) >= 3, "Shared keyword engine");
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
}

Console.WriteLine($"WINDOWS_SELF_TEST passed={passed} failed={failures.Count}");
foreach (var failure in failures) Console.WriteLine("FAIL " + failure);
return failures.Count == 0 ? 0 : 1;

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
