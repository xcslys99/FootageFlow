namespace FootageFlow.Windows.Services;

public static class WindowsPathSafety
{
    public static string UniquePath(string directory, string preferredName)
    {
        var safe = SanitizeName(Path.GetFileNameWithoutExtension(preferredName));
        var extension = Path.GetExtension(preferredName);
        if (string.IsNullOrWhiteSpace(extension)) extension = ".mp4";
        var candidate = Path.Combine(directory, safe + extension);
        for (var index = 2; File.Exists(candidate) || File.Exists(candidate + ".part"); index++)
            candidate = Path.Combine(directory, $"{safe}_{index}{extension}");
        return candidate;
    }

    public static string SanitizeName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars().Concat(['<', '>', ':', '"', '/', '\\', '|', '?', '*']).ToHashSet();
        var clean = new string(value.Select(character => invalid.Contains(character) ? '_' : character).ToArray()).Trim(' ', '.');
        if (string.IsNullOrWhiteSpace(clean)) clean = "Media";
        var stem = clean.Split('.')[0].ToUpperInvariant();
        string[] reserved = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"];
        if (reserved.Contains(stem)) clean = "_" + clean;
        return clean.Length > 80 ? clean[..80] : clean;
    }
}
