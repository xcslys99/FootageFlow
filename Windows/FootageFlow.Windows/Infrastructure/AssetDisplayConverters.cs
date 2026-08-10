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
        return status switch
        {
            "SAFE" => values.ElementAtOrDefault(2) as string ?? "Clearly licensed",
            "ATTRIBUTION_REQUIRED" => values.ElementAtOrDefault(3) as string ?? "Attribution required",
            "PUBLIC_DOMAIN" => values.ElementAtOrDefault(4) as string ?? "Public Domain",
            "RESTRICTED" => values.ElementAtOrDefault(5) as string ?? "Restricted",
            _ => values.ElementAtOrDefault(6) as string ?? "License unknown"
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
            "nasa" => "NASA",
            "libraryOfCongress" => "Library of Congress",
            "nationalArchives" => "National Archives",
            "europeana" => "Europeana",
            "peertube" => "PeerTube / SepiaSearch",
            "videvo" => "Videvo",
            "videezy" => "Videezy",
            "mixkit" => "Mixkit",
            "coverr" => "Coverr",
            "vimeo" => "Vimeo",
            "linkDownloader" => "Link Downloader",
            var other => other ?? ""
        };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
