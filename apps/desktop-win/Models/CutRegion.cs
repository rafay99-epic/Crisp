using CommunityToolkit.Mvvm.ComponentModel;

namespace Crisp.Models;

/// One pause the clean proposes to remove, shown as a toggleable row in the review
/// editor. `Remove` defaults true (cut it); unchecking keeps that pause in the output.
public partial class CutRegion : ObservableObject
{
    public double Start { get; init; }
    public double End { get; init; }
    public double Length => End - Start;

    [ObservableProperty] private bool _remove = true;

    public string TimeLabel =>
        $"{Formatting.Duration(Start)} – {Formatting.Duration(End)}  ({Formatting.Duration(Length)})";
}
