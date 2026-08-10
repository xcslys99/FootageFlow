using System.Diagnostics;
using System.Text;

namespace FootageFlow.Windows.Services;

public sealed class YtDlpPlatformService
{
    private readonly string _executable = Path.Combine(AppContext.BaseDirectory, "Tools", "yt-dlp.exe");
    public bool IsAvailable => File.Exists(_executable);

    public async Task<byte[]> SearchAsync(string query, int limit, CancellationToken cancellationToken)
    {
        var count = Math.Clamp(limit, 1, 12);
        var result = await RunAsync(
            ["--ignore-config", "--no-progress", "--no-warnings", "--flat-playlist",
             "--dump-single-json", "--playlist-end", count.ToString(), $"ytsearch{count}:{query}"],
            TimeSpan.FromSeconds(75), cancellationToken);
        EnsureSuccess(result);
        return Encoding.UTF8.GetBytes(result.Output);
    }

    public async Task<string> DownloadAsync(
        string sourceUrl,
        string directory,
        string fileStem,
        CancellationToken cancellationToken)
    {
        var result = await RunAsync(
            ["--ignore-config", "--no-progress", "--no-warnings", "--no-playlist",
             "--no-overwrites", "--socket-timeout", "15", "--retries", "1",
             "--fragment-retries", "1", "--format",
             "best[ext=mp4][acodec!=none][vcodec!=none][height<=720]/best[acodec!=none][vcodec!=none][height<=720]",
             "--paths", directory, "--output", $"{fileStem}.%(ext)s", "--print",
             "after_move:filepath", sourceUrl],
            TimeSpan.FromHours(1), cancellationToken);
        EnsureSuccess(result);
        var path = result.Output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).LastOrDefault()?.Trim();
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            throw new ExternalToolException("invalidResponse", "The downloaded file could not be found.");
        var root = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var candidate = Path.GetFullPath(path);
        if (!candidate.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            throw new ExternalToolException("invalidResponse", "The download path was rejected for safety.");
        return candidate;
    }

    private async Task<ToolResult> RunAsync(
        IReadOnlyList<string> arguments,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        if (!IsAvailable)
            throw new ExternalToolException("externalToolUnavailable", "YouTube support is missing. Please reinstall FootageFlow.");
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = _executable,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                WorkingDirectory = AppPaths.DataRoot
            }
        };
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        if (!process.Start())
            throw new ExternalToolException("externalToolUnavailable", "YouTube support could not be started.");
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        using var timeoutSource = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
        try { await process.WaitForExitAsync(linked.Token); }
        catch (OperationCanceledException)
        {
            TryKill(process);
            if (cancellationToken.IsCancellationRequested) throw;
            throw new ExternalToolException("timeout", "YouTube took too long to respond. Please try again later.");
        }
        return new ToolResult(process.ExitCode, await outputTask, await errorTask);
    }

    private static void EnsureSuccess(ToolResult result)
    {
        if (result.ExitCode == 0) return;
        var message = result.Error.ToLowerInvariant();
        if (message.Contains("429") || message.Contains("too many requests"))
            throw new ExternalToolException("rateLimited", "Too many requests. Please try again later.");
        if (message.Contains("video unavailable") || message.Contains("has been removed"))
            throw new ExternalToolException("videoUnavailable", "This video is no longer available.");
        if (message.Contains("not available in your country") || message.Contains("geo-restricted"))
            throw new ExternalToolException("regionalRestriction", "This video is unavailable in your region.");
        if (message.Contains("sign in") || message.Contains("login") || message.Contains("private video") ||
            message.Contains("members-only") || message.Contains("age-restricted"))
            throw new ExternalToolException("temporarilyBlocked", "This video requires access that FootageFlow does not use.");
        throw new ExternalToolException("requestFailed", "YouTube could not complete this request. Open the source page or try again later.");
    }

    private static void TryKill(Process process)
    {
        try { if (!process.HasExited) process.Kill(true); }
        catch { }
    }

    private sealed record ToolResult(int ExitCode, string Output, string Error);
}

public sealed class ExternalToolException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
