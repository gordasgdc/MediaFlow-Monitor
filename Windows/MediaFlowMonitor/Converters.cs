using System;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using MediaFlowMonitor.SystemMetrics;
using MediaFlowMonitor.Overlay;

namespace MediaFlowMonitor;

/// MetricLevel -> Brush (Ok/Warning/Critical), citite din tema curentă
/// (DynamicResource) — comutarea de temă schimbă automat culorile.
public sealed class MetricLevelToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var key = value switch
        {
            MetricLevel.Critical => "CriticalBrush",
            MetricLevel.Warning => "WarningBrush",
            _ => "OkBrush",
        };
        return System.Windows.Application.Current.TryFindResource(key) ?? System.Windows.Media.Brushes.Gray;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class NullableBoolToHealthTextConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value switch { true => "Healthy", false => "Failing", _ => "Necunoscut" };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        (value is bool b && b) ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is Visibility v && v == Visibility.Visible;
}

/// RunningAction curent == parametrul (numele enum-ului, ex. "PurgeCache")
/// -> Visibility.Visible — folosit pentru spinner-ul de pe fiecare buton.
public sealed class RunningActionEqualsConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not RunningAction current || parameter is not string paramStr) return Visibility.Collapsed;
        return Enum.TryParse<RunningAction>(paramStr, out var target) && current == target
            ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class ActionLogLevelToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value switch
        {
            ActionLogLevel.Success => System.Windows.Media.Brushes.LimeGreen,
            ActionLogLevel.Error => System.Windows.Media.Brushes.IndianRed,
            ActionLogLevel.Exec => System.Windows.Media.Brushes.DeepSkyBlue,
            _ => System.Windows.Media.Brushes.LightGray,
        };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class RunningActionToStatusBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is RunningAction a && a != RunningAction.None ? System.Windows.Media.Brushes.Goldenrod : System.Windows.Media.Brushes.MediumSeaGreen;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// Text de buton dependent de starea curentă — parametru format
/// "TargetAction|TextIdle|TextRunning", ex. "PurgeCache|Purge Cache|Purging…".
public sealed class ActionButtonTextConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not RunningAction current || parameter is not string paramStr) return "";
        var parts = paramStr.Split('|');
        if (parts.Length != 3 || !Enum.TryParse<RunningAction>(parts[0], out var target)) return "";
        return current == target ? parts[2] : parts[1];
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// LogFilter curent == parametrul (numele enum-ului) -> fundal evidențiat
/// pentru chip-ul de filtru activ ("All"/"Errors"/"Warnings"/"RenderEvents").
public sealed class LogFilterToBackgroundConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not LogFilter current || parameter is not string paramStr) return System.Windows.Media.Brushes.Transparent;
        return Enum.TryParse<LogFilter>(paramStr, out var target) && current == target
            ? new SolidColorBrush(Color.FromArgb(60, 120, 160, 255))
            : new SolidColorBrush(Color.FromArgb(25, 128, 128, 128));
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// Pause/Resume Auto-scroll — glifă text pentru buton (⏸ / ▶).
public sealed class BoolToPauseGlyphConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? "▶" : "⏸";

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// Formatare "HH:mm:ss [ERR] text" pentru linia de log — combină Date+Text+Level
/// într-un singur MultiBinding, echivalentul textului monospațiat de pe Mac.
public sealed class LogLineFormatConverter : IMultiValueConverter
{
    private static readonly string[] Keywords = { "GPU Full", "GPU Memory Full", "Cache Drop", "Timeout", "crashed", "dropped" };

    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        if (values is not [DateTime date, string text, MetricLevel level]) return "";
        var tag = level == MetricLevel.Critical ? "ERR" : level == MetricLevel.Warning ? "WARN" : "OK";
        return $"{date:HH:mm:ss} [{tag}] {text}";
    }

    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();

    /// True dacă textul conține un cuvânt cheie critic — folosit pentru bold.
    public static bool ContainsKeyword(string text) =>
        Keywords.Any(k => text.Contains(k, StringComparison.OrdinalIgnoreCase));
}

/// Bold dacă textul conține un cuvânt cheie de atenționat (GPU Full, Cache
/// Drop, Timeout etc.) — highlight vizual, echivalentul bold-ului din Mac.
public sealed class TextContainsKeywordToBoldConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is string s && LogLineFormatConverter.ContainsKeyword(s) ? FontWeights.Bold : FontWeights.Normal;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class RunningActionToBoolInverseConverter : IValueConverter
{
    // Folosit pentru IsEnabled — butoanele se dezactivează CÂT TIMP rulează ceva.
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is RunningAction action && action == RunningAction.None;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
