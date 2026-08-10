using System.Text.RegularExpressions;

namespace FootageFlow.Windows.Services;

public sealed record LanguageOption(string Code, string DisplayName);

public sealed partial class LocalizationService
{
    public static IReadOnlyList<LanguageOption> SupportedLanguages { get; } =
    [
        new("en", "English"),
        new("zh-Hans", "简体中文"),
        new("zh-Hant", "繁體中文"),
        new("es", "Español"),
        new("pt-BR", "Português (Brasil)"),
        new("ja", "日本語"),
        new("ko", "한국어"),
        new("de", "Deutsch"),
        new("fr", "Français"),
        new("ru", "Русский")
    ];

    private readonly SettingsService _settings;
    private readonly Dictionary<string, string> _english;
    private Dictionary<string, string> _current;

    public event EventHandler? LanguageChanged;
    public string Language => Normalize(_settings.Current.Language);
    public string DisplayName => SupportedLanguages.First(value => value.Code == Language).DisplayName;

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

    public string Text(string key, params object[] arguments)
    {
        var value = Text(key);
        foreach (var argument in arguments)
        {
            var integer = value.IndexOf("%d", StringComparison.Ordinal);
            var text = value.IndexOf("%@", StringComparison.Ordinal);
            var index = integer < 0 ? text : text < 0 ? integer : Math.Min(integer, text);
            if (index < 0) break;
            value = string.Concat(value.AsSpan(0, index), argument?.ToString(), value.AsSpan(index + 2));
        }
        return value;
    }

    public void SetLanguage(string language)
    {
        language = Normalize(language);
        if (_settings.Current.Language == language) return;
        _settings.Current.Language = language;
        _settings.Save();
        _current = Load(language);
        LanguageChanged?.Invoke(this, EventArgs.Empty);
    }

    private static string Normalize(string language) =>
        SupportedLanguages.Any(value => value.Code == language) ? language : "en";

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
