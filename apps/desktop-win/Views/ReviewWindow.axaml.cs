using Avalonia.Controls;
using Avalonia.Interactivity;

namespace Crisp.Views;

public partial class ReviewWindow : Window
{
    public ReviewWindow()
    {
        InitializeComponent();
        WindowChrome.ApplyMica(this);
    }

    private void OnCancel(object? sender, RoutedEventArgs e) => Close(false);
    private void OnApply(object? sender, RoutedEventArgs e) => Close(true);
}
