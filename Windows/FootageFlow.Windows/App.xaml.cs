using System.Windows;
using FootageFlow.Windows.Models;
using FootageFlow.Windows.Services;

namespace FootageFlow.Windows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Contains("--health-check", StringComparer.OrdinalIgnoreCase))
        {
            var exitCode = RunInstalledHealthCheck();
            Shutdown(exitCode);
            return;
        }
        DispatcherUnhandledException += (_, args) =>
        {
            MessageBox.Show(
                "FootageFlow encountered an unexpected problem. Please reopen the app. No API key was written to the log.",
                "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };
        try
        {
            MainWindow = new MainWindow();
            MainWindow.Show();
        }
        catch (Exception error)
        {
            WriteStartupFailure(error);
            Shutdown(1);
        }
    }

    private static int RunInstalledHealthCheck()
    {
        try
        {
            var response = new CoreHostClient().SendAsync(new CoreRequest
            {
                Action = "health", ProviderIDs = ["wikimedia", "internetArchive"], Language = "en"
            }).GetAwaiter().GetResult();
            return response.Success && response.Platform == "windows" ? 0 : 1;
        }
        catch { return 1; }
    }

    private static void WriteStartupFailure(Exception error)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.LogDirectory);
            var report = $"{DateTimeOffset.UtcNow:O} | {error.GetType().FullName}{Environment.NewLine}{error}{Environment.NewLine}";
            File.AppendAllText(Path.Combine(AppPaths.LogDirectory, "startup.log"), report);
        }
        catch { }
    }
}
