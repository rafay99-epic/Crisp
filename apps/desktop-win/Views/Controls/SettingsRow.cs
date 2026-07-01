using System;
using Avalonia;
using Avalonia.Controls;

namespace Crisp.Views.Controls;

/// <summary>
/// A single Windows 11 "settings card" row: an optional leading Fluent icon, a
/// title with an optional description underneath, and a right-aligned control
/// (the <see cref="ContentControl.Content"/>). Grouped inside a
/// <c>Border.settingsGroup</c> with divider lines between rows — the pattern the
/// Windows 11 Settings app uses everywhere. Templated in Theme/Styles.axaml.
/// </summary>
public class SettingsRow : ContentControl
{
    public static readonly StyledProperty<string?> HeaderProperty =
        AvaloniaProperty.Register<SettingsRow, string?>(nameof(Header));

    public static readonly StyledProperty<string?> DescriptionProperty =
        AvaloniaProperty.Register<SettingsRow, string?>(nameof(Description));

    public static readonly StyledProperty<string?> GlyphProperty =
        AvaloniaProperty.Register<SettingsRow, string?>(nameof(Glyph));

    /// <summary>Row title (left, primary text).</summary>
    public string? Header
    {
        get => GetValue(HeaderProperty);
        set => SetValue(HeaderProperty, value);
    }

    /// <summary>Optional secondary line under the title.</summary>
    public string? Description
    {
        get => GetValue(DescriptionProperty);
        set => SetValue(DescriptionProperty, value);
    }

    /// <summary>Optional leading Segoe Fluent Icons glyph (e.g. "").</summary>
    public string? Glyph
    {
        get => GetValue(GlyphProperty);
        set => SetValue(GlyphProperty, value);
    }

    protected override Type StyleKeyOverride => typeof(SettingsRow);
}
