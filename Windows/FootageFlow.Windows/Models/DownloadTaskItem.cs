using FootageFlow.Windows.Infrastructure;

namespace FootageFlow.Windows.Models;

public sealed class DownloadTaskItem(MediaAsset asset, Guid? projectId, string projectName) : ObservableObject
{
    private string _status = "Queued";
    private string _state = "waiting";
    private double _progress;
    private string _speed = "";
    private string? _localPath;
    private string? _errorMessage;

    public Guid Id { get; } = Guid.NewGuid();
    public MediaAsset Asset { get; } = asset;
    public Guid? ProjectId { get; } = projectId;
    public string ProjectName { get; } = projectName;
    public CancellationTokenSource Cancellation { get; private set; } = new();
    public string Status { get => _status; set => Set(ref _status, value); }
    public string State { get => _state; set => Set(ref _state, value); }
    public double Progress { get => _progress; set => Set(ref _progress, value); }
    public string Speed { get => _speed; set => Set(ref _speed, value); }
    public string? LocalPath { get => _localPath; set => Set(ref _localPath, value); }
    public string? ErrorMessage { get => _errorMessage; set => Set(ref _errorMessage, value); }
    public bool CanCancel => State is "waiting" or "downloading";
    public bool CanRetry => State is "failed" or "cancelled";

    public void ResetCancellation()
    {
        Cancellation.Dispose();
        Cancellation = new CancellationTokenSource();
    }
}
