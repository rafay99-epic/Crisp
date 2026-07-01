using System.IO;
using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Crisp.Models;
using Crisp.Services;

namespace Crisp.Views;

public partial class HistoryWindow : Window
{
    public HistoryWindow()
    {
        InitializeComponent();
        WindowChrome.ApplyMica(this);
    }

    private void OnClear(object? sender, RoutedEventArgs e)
        => (DataContext as HistoryStore)?.Clear();

    private void OnReveal(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { CommandParameter: HistoryEntry entry })
            RevealInOS(entry.OutputPath);
    }

    // Reveal a file in the OS browser (mirrors MainWindowViewModel.RevealInOS).
    private static void RevealInOS(string? path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;
        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(
                    "explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                System.Diagnostics.Process.Start("open", new[] { "-R", path });
            else
                System.Diagnostics.Process.Start("xdg-open", new[] { Path.GetDirectoryName(path) ?? "." });
        }
        catch { /* best effort */ }
    }
}
