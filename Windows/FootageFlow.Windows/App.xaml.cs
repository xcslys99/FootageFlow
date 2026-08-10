using System.Windows;

namespace FootageFlow.Windows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += (_, args) =>
        {
            MessageBox.Show(
                "FootageFlow encountered an unexpected problem. Please reopen the app. No API key was written to the log.",
                "FootageFlow", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };
        base.OnStartup(e);
    }
}
