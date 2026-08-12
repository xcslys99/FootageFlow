namespace FootageFlow.Windows.Models;

/// <summary>
/// Suppresses repeated clipboard prompts during the current app session.
/// It retains normalized public media URLs only, never raw clipboard text.
/// </summary>
public sealed class ClipboardSuggestionSession(TimeSpan? cooldown = null)
{
    private readonly HashSet<string> _seen = new(StringComparer.OrdinalIgnoreCase);
    private readonly TimeSpan _cooldown = cooldown ?? TimeSpan.FromMilliseconds(750);
    private DateTimeOffset? _lastCheckAt;

    public IReadOnlyList<string> FreshCandidates(
        IEnumerable<string> candidates,
        IEnumerable<string> existing,
        DateTimeOffset? now = null)
    {
        var checkedAt = now ?? DateTimeOffset.UtcNow;
        if (_lastCheckAt is { } last && checkedAt - last < _cooldown) return [];
        _lastCheckAt = checkedAt;
        var existingSet = existing.ToHashSet(StringComparer.OrdinalIgnoreCase);
        return candidates.Where(value => !existingSet.Contains(value) && _seen.Add(value)).ToArray();
    }
}
