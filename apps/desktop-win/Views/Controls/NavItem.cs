using System;
using Avalonia;
using Avalonia.Controls;

namespace Crisp.Views.Controls;

/// <summary>
/// One entry in the left navigation pane: a Segoe Fluent Icons glyph + label,
/// with the WinUI NavigationViewItem visuals (subtle hover fill, and an accent
/// selection pill on the left edge when checked). It's a RadioButton so the
/// pane gets exclusive selection for free — including across the footer item.
/// Templated in Theme/Styles.axaml.
/// </summary>
public class NavItem : RadioButton
{
    public static readonly StyledProperty<string?> GlyphProperty =
        AvaloniaProperty.Register<NavItem, string?>(nameof(Glyph));

    /// <summary>Leading Segoe Fluent Icons glyph (e.g. "&#xE80F;").</summary>
    public string? Glyph
    {
        get => GetValue(GlyphProperty);
        set => SetValue(GlyphProperty, value);
    }

    protected override Type StyleKeyOverride => typeof(NavItem);
}
