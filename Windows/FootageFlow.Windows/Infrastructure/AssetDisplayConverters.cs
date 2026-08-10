using System.Globalization;
using System.Windows.Data;

namespace FootageFlow.Windows.Infrastructure;

public sealed class LicenseDisplayConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        var license = values.ElementAtOrDefault(0) as string;
        if (!string.IsNullOrWhiteSpace(license)) return license;
        var status = values.ElementAtOrDefault(1) as string ?? "UNKNOWN";
        var chinese = (values.ElementAtOrDefault(2) as string)?.Contains("简体中文", StringComparison.Ordinal) == true;
        return (status, chinese) switch
        {
            ("SAFE", false) => "Clearly licensed",
            ("SAFE", true) => "明确可用",
            ("ATTRIBUTION_REQUIRED", false) => "Attribution required",
            ("ATTRIBUTION_REQUIRED", true) => "需要署名",
            ("PUBLIC_DOMAIN", _) => "Public Domain",
            ("RESTRICTED", false) => "Restricted",
            ("RESTRICTED", true) => "受限制",
            (_, false) => "License unknown",
            _ => "授权未知"
        };
    }

    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class ProviderNameConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        (value as string) switch
        {
            "pexels" => "Pexels",
            "pixabay" => "Pixabay",
            "wikimedia" => "Wikimedia Commons",
            "internetArchive" => "Internet Archive",
            "youtube" => "YouTube",
            var other => other ?? ""
        };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
