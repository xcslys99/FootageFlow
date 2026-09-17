using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Threading;
using FootageFlow.Windows;
using FootageFlow.Windows.Models;
using FootageFlow.Windows.ViewModels;

// Runs in a real STA WPF window on the Windows CI desktop, without contacting a media provider.
// Live Provider and installer checks remain separate CI steps.
var exitCode = 1;
var thread = new Thread(() => exitCode = RunAcceptance(args)) { IsBackground = true };
thread.SetApartmentState(ApartmentState.STA);
thread.Start();
if (!thread.Join(TimeSpan.FromSeconds(45)))
{
    Console.WriteLine("WINDOWS_DUPLICATE_UI timeout waiting for the WPF desktop");
    return 1;
}
return exitCode;

static int RunAcceptance(string[] args)
{
var screenshot = args.Length > 0 ? Path.GetFullPath(args[0]) :
    Path.Combine(Path.GetTempPath(), "FootageFlow-duplicate-review-ui.png");
var checks = 0;
var failures = new List<string>();
void Check(bool condition, string name)
{
    if (condition) checks++;
    else failures.Add(name);
}

Application? application = null;
MainWindow? window = null;
try
{
    application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
    window = new MainWindow();
    var vm = (MainViewModel)window.DataContext;
    vm.CurrentPage = "search";
    var known = new MediaAsset
    {
        Provider = "wikimedia", Id = "accept-known", Title = "Apollo 11 archival film",
        SourcePageURL = "https://commons.wikimedia.org/wiki/File:Apollo_11.webm",
        License = "CC BY 4.0", LicenseStatus = "ATTRIBUTION_REQUIRED",
        MediaType = "video", Duration = 42, Width = 1920, Height = 1080
    };
    var unknown = new MediaAsset
    {
        Provider = "internetArchive", Id = "accept-unknown", Title = "Apollo 11 alternate film",
        SourcePageURL = "https://archive.org/details/apollo-11-alternate",
        LicenseStatus = "UNKNOWN", MediaType = "video", Duration = 42,
        Width = 1280, Height = 720
    };
    vm.Results.Add(known);
    vm.Results.Add(unknown);
    var group = new SearchDuplicateDisplayItem
    {
        Id = "accept-group", Recommended = known,
        Header = "Likely same footage · 2 versions",
        RecommendedLabel = "Recommended version", Expanded = false
    };
    group.OtherVersions.Add(unknown);
    vm.SearchDuplicateItems.Add(group);
    vm.ShowAllDuplicateResults = true;
    vm.ShowAllDuplicateResults = false;
    window.Show();
    window.Activate();
    window.UpdateLayout();

    var grouped = Descendants<ItemsControl>(window).FirstOrDefault(value =>
        ReferenceEquals(value.ItemsSource, vm.SearchDuplicateItems));
    var flat = Descendants<ItemsControl>(window).FirstOrDefault(value =>
        ReferenceEquals(value.ItemsSource, vm.ResultsView));
    Check(grouped?.Visibility == Visibility.Visible && flat?.Visibility == Visibility.Collapsed,
        "Grouped view displays while original flat results remain available");
    var sourceExpander = Descendants<Expander>(window).FirstOrDefault(value =>
        value.Header?.ToString() == vm.SourceFilterTitle);
    Check(sourceExpander is { IsExpanded: false } && sourceExpander.FocusVisualStyle is not null,
        "Source list starts collapsed to leave room for search-result cards");
    var disclosure = Descendants<ToggleButton>(window).FirstOrDefault(value =>
        AutomationProperties.GetName(value) == group.Header);
    Check(disclosure is not null && disclosure.IsTabStop && disclosure.FocusVisualStyle is not null,
        "Group disclosure is keyboard focusable with a visible focus style");
    if (disclosure is not null)
    {
        var peer = new ToggleButtonAutomationPeer(disclosure);
        var pattern = peer.GetPattern(PatternInterface.Toggle) as IToggleProvider;
        Check(peer.GetName() == group.Header && pattern?.ToggleState == ToggleState.Off,
            "Narrator sees localized group name and collapsed state");
        disclosure.Focus();
        Check(ReferenceEquals(Keyboard.FocusedElement, disclosure),
            "Keyboard focus reaches the group disclosure");
        pattern?.Toggle();
        window.UpdateLayout();
        Check(group.Expanded && pattern?.ToggleState == ToggleState.On,
            "UI Automation expands the group and announces expanded state");
    }
    var alternatives = Descendants<ItemsControl>(window).FirstOrDefault(value =>
        ReferenceEquals(value.ItemsSource, group.OtherVersions));
    Check(alternatives?.Visibility == Visibility.Visible,
        "Expanded group reveals its other original media card");
    Check(known.LicenseStatus == "ATTRIBUTION_REQUIRED" && unknown.LicenseStatus == "UNKNOWN",
        "Known rights never overwrite the alternative source unknown rights");
    bool RendersAsset(MediaAsset asset) =>
        Descendants<ContentPresenter>(window).Any(value => ReferenceEquals(value.Content, asset)) ||
        Descendants<ContentControl>(window).Any(value => ReferenceEquals(value.Content, asset));
    Check(RendersAsset(known) && RendersAsset(unknown),
        "Both versions render as original media cards");

    var allResults = Descendants<CheckBox>(window).FirstOrDefault(value =>
        value.Content?.ToString() == "All Results");
    Check(allResults is not null && AutomationProperties.GetName(allResults) == "All Results",
        "All Results control has a readable automation name");
    if (allResults is not null) allResults.IsChecked = true;
    window.UpdateLayout();
    Check(vm.ShowAllDuplicateResults && flat?.Visibility == Visibility.Visible &&
          grouped?.Visibility == Visibility.Collapsed && vm.Results.Count == 2,
        "All Results restores both original results without deletion");

    // Capture the grouped state from the actual WPF visual tree for visual review.
    if (allResults is not null) allResults.IsChecked = false;
    window.UpdateLayout();
    var bitmap = new RenderTargetBitmap(
        Math.Max(1, (int)window.ActualWidth), Math.Max(1, (int)window.ActualHeight),
        96, 96, PixelFormats.Pbgra32);
    bitmap.Render(window);
    var encoder = new PngBitmapEncoder();
    encoder.Frames.Add(BitmapFrame.Create(bitmap));
    Directory.CreateDirectory(Path.GetDirectoryName(screenshot)!);
    using (var stream = File.Create(screenshot)) encoder.Save(stream);
    Check(new FileInfo(screenshot).Length > 10_000,
        "Actual WPF grouped-result screenshot rendered");
}
catch (Exception error)
{
    failures.Add($"Native WPF acceptance error: {error.GetType().Name}: {error.Message}");
}
finally
{
    window?.Close();
    application?.Shutdown();
}

Console.WriteLine($"WINDOWS_DUPLICATE_UI passed={checks} failed={failures.Count} screenshot={screenshot}");
foreach (var failure in failures) Console.WriteLine($"FAIL {failure}");
return failures.Count == 0 ? 0 : 1;
}

static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
{
    for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
    {
        var child = VisualTreeHelper.GetChild(root, index);
        if (child is T found) yield return found;
        foreach (var nested in Descendants<T>(child)) yield return nested;
    }
}
