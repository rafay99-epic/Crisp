using Avalonia.Controls;
using Avalonia.Interactivity;
using Crisp.Services;

namespace Crisp.Views;

public partial class WhatsNewWindow : Window
{
    public WhatsNewWindow()
    {
        InitializeComponent();
        WindowChrome.ApplyMica(this);
    }

    private void OnDownload(object? sender, RoutedEventArgs e)
    {
        (DataContext as Updater)?.OpenDownload();
        Close();
    }

    private void OnClose(object? sender, RoutedEventArgs e) => Close();
}
