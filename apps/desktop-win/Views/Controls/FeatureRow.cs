using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;

namespace Crisp.Views.Controls;

/// <summary>
/// A card explaining one capability in the first-run tour: a leading accent
/// Fluent icon beside a title and a wrapping description (the Windows take on
/// the macOS onboarding featureRow). Templated in Theme/Styles.axaml.
/// </summary>
public class FeatureRow : TemplatedControl
{
    public static readonly StyledProperty<string?> HeaderProperty =
        AvaloniaProperty.Register<FeatureRow, string?>(nameof(Header));

    public static readonly StyledProperty<string?> DescriptionProperty =
        AvaloniaProperty.Register<FeatureRow, string?>(nameof(Description));

    public static readonly StyledProperty<string?> GlyphProperty =
        AvaloniaProperty.Register<FeatureRow, string?>(nameof(Glyph));

    /// <summary>Feature title (primary text).</summary>
    public string? Header
    {
        get => GetValue(HeaderProperty);
        set => SetValue(HeaderProperty, value);
    }

    /// <summary>Wrapping explanation under the title.</summary>
    public string? Description
    {
        get => GetValue(DescriptionProperty);
        set => SetValue(DescriptionProperty, value);
    }

    /// <summary>Leading Segoe Fluent Icons glyph.</summary>
    public string? Glyph
    {
        get => GetValue(GlyphProperty);
        set => SetValue(GlyphProperty, value);
    }

    protected override Type StyleKeyOverride => typeof(FeatureRow);
}
