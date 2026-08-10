using System.Text.RegularExpressions;

namespace FootageFlow.Windows.Services;

public sealed partial class LocalizationService
{
    private readonly SettingsService _settings;
    private readonly Dictionary<string, string> _english;
    private Dictionary<string, string> _current;

    public event EventHandler? LanguageChanged;
    public string Language => _settings.Current.Language;

    public LocalizationService(SettingsService settings)
    {
        _settings = settings;
        _english = Load("en");
        _current = Load(Language);
    }

    public string Text(string key)
    {
        if (_current.TryGetValue(key, out var value)) return value;
        return _english.TryGetValue(key, out value) ? value : key;
    }

    public void SetLanguage(string language)
    {
        if (language is not ("en" or "zh-Hans")) language = "en";
        if (_settings.Current.Language == language) return;
        _settings.Current.Language = language;
        _settings.Save();
        _current = Load(language);
        LanguageChanged?.Invoke(this, EventArgs.Empty);
    }

    private static Dictionary<string, string> Load(string language)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Resources", $"{language}.lproj", "Localizable.strings");
        if (!File.Exists(path)) return [];
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (Match match in StringsLine().Matches(File.ReadAllText(path)))
            result[Unescape(match.Groups[1].Value)] = Unescape(match.Groups[2].Value);
        return result;
    }

    private static string Unescape(string value) => value
        .Replace("\\n", "\n", StringComparison.Ordinal)
        .Replace("\\\"", "\"", StringComparison.Ordinal)
        .Replace("\\\\", "\\", StringComparison.Ordinal);

    [GeneratedRegex("^\\s*\"((?:\\\\.|[^\"])*)\"\\s*=\\s*\"((?:\\\\.|[^\"])*)\"\\s*;", RegexOptions.Multiline)]
    private static partial Regex StringsLine();
}
