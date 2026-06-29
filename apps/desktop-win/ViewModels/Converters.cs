using Avalonia.Data.Converters;

namespace Crisp.ViewModels;

public static class Converters
{
    public static readonly IValueConverter DropText =
        new FuncValueConverter<bool, string>(targeted => targeted ? "Drop to add" : "No videos added");
}
