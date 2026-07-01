using Avalonia.Controls;
using Avalonia.Media;

namespace Crisp;

/// <summary>
/// Gives a <see cref="Window"/> the Windows 11 Mica backdrop. Mica only renders
/// when the client area is extended into the window decorations, so we extend and
/// keep the *system-drawn* caption buttons (WindowDecorations.Full) — they stay
/// natively clickable while DWM tints the whole window, caption included, with the
/// desktop-wallpaper Mica material (the Settings / Photos look). Views reserve the
/// top <see cref="TitleBarHeight"/> px so their content clears the caption strip.
///
/// (A fully app-drawn title bar via WindowDecorations.None was tried, but Avalonia
/// 12 leaves that extended strip as a dead OS-caption zone that swallows clicks
/// from controls placed in it — so we let the system own the caption.)
/// </summary>
public static class WindowChrome
{
    /// <summary>Height of the native caption strip content must sit below.</summary>
    public const double TitleBarHeight = 34;

    public static void ApplyMica(Window w)
    {
        w.Background = Brushes.Transparent;
        w.TransparencyLevelHint = new[] { WindowTransparencyLevel.Mica, WindowTransparencyLevel.AcrylicBlur };
        w.ExtendClientAreaToDecorationsHint = true;
        w.ExtendClientAreaTitleBarHeightHint = -1;
        w.WindowDecorations = WindowDecorations.Full;
    }
}
