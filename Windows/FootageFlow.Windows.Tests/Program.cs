using System.Text.Json;
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
Check(WindowsPathSafety.SanitizeName("CON") == "_CON", "Windows reserved filename");
Check(!WindowsPathSafety.SanitizeName("bank:run?.mp4").Contains(':'), "Windows invalid filename characters");
Check(WindowsPathSafety.SanitizeName(new string('a', 200)).Length == 80, "Windows filename length");
Check(WindowsPathSafety.SanitizeName("阿根廷 银行").Contains("阿根廷"), "Chinese filename preservation");

var media = new MediaAsset
{
    Id = "fixture", Provider = "wikimedia", Title = "Fixture", SourcePageURL = "https://example.com/source",
    DownloadURL = "https://example.com/fixture.mp4", License = "CC BY", LicenseStatus = "ATTRIBUTION_REQUIRED",
    MediaType = "video", Downloadable = true, SearchKeyword = "fixture"
};
var roundTrip = JsonSerializer.Deserialize<MediaAsset>(JsonSerializer.Serialize(media));
Check(roundTrip?.StableId == "wikimedia:fixture", "MediaAsset JSON round trip");

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
        var health = await core.SendAsync(new CoreRequest { Action = "health", ProviderIDs = ["wikimedia"] });
        Check(health.Success && health.Platform == "windows", "Windows core health");
        var keywords = await core.SendAsync(new CoreRequest { Action = "keywords", Query = "2001年阿根廷银行挤兑" });
        Check((keywords.Keywords?.Count ?? 0) >= 3, "Shared keyword engine");

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
    }
}

Console.WriteLine($"WINDOWS_SELF_TEST passed={passed} failed={failures.Count}");
foreach (var failure in failures) Console.WriteLine("FAIL " + failure);
return failures.Count == 0 ? 0 : 1;
