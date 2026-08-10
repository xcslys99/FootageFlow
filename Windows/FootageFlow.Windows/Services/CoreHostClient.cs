using System.Diagnostics;
using System.Text.Json;
using FootageFlow.Windows.Models;

namespace FootageFlow.Windows.Services;

public sealed class CoreHostClient
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };

    private readonly string _executable;

    public CoreHostClient(string? executable = null)
    {
        _executable = executable ?? new[]
        {
            Path.Combine(AppContext.BaseDirectory, "Core", "FootageFlowCore.exe"),
            Path.Combine(AppContext.BaseDirectory, "FootageFlowCore.exe")
        }.FirstOrDefault(File.Exists) ?? Path.Combine(AppContext.BaseDirectory, "Core", "FootageFlowCore.exe");
    }

    public async Task<CoreResponse> SendAsync(
        CoreRequest request,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_executable))
            throw new CoreHostException("coreUnavailable", "The FootageFlow search core is missing. Please reinstall FootageFlow.");

        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = _executable,
                ArgumentList = { "--core-request" },
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                WorkingDirectory = AppContext.BaseDirectory
            },
            EnableRaisingEvents = true
        };
        if (!process.Start()) throw new CoreHostException("coreUnavailable", "Unable to start the FootageFlow search core.");

        var input = JsonSerializer.Serialize(request, JsonOptions);
        await process.StandardInput.WriteAsync(input.AsMemory(), cancellationToken);
        process.StandardInput.Close();
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);

        using var timeoutSource = new CancellationTokenSource(timeout ?? TimeSpan.FromSeconds(45));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
        try
        {
            await process.WaitForExitAsync(linked.Token);
        }
        catch (OperationCanceledException)
        {
            TryKill(process);
            if (cancellationToken.IsCancellationRequested) throw;
            throw new CoreHostException("timeout", "The provider took too long to respond. Please try again.");
        }

        var output = await outputTask;
        _ = await errorTask; // Deliberately not surfaced because provider stderr can contain request details.
        CoreResponse? response;
        try { response = JsonSerializer.Deserialize<CoreResponse>(output, JsonOptions); }
        catch (JsonException) { response = null; }
        if (response is null)
            throw new CoreHostException("invalidResponse", "The search provider returned an unreadable response.");
        return response;
    }

    private static void TryKill(Process process)
    {
        try { if (!process.HasExited) process.Kill(true); }
        catch { }
    }
}

public sealed class CoreHostException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
