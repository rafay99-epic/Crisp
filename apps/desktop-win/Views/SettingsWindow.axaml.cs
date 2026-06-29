using System.Linq;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Crisp.Models;
using Crisp.Services;

namespace Crisp.Views;

public partial class SettingsWindow : Window
{
    public SettingsWindow() => InitializeComponent();

    private void OnDone(object? sender, RoutedEventArgs e) => Close();

    private void OnRevealLogs(object? sender, RoutedEventArgs e)
    {
        var dir = Channels.LogsDirectory;
        try
        {
            System.IO.Directory.CreateDirectory(dir);
            if (System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.Windows))
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true });
            else if (System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.OSX))
                System.Diagnostics.Process.Start("open", new[] { dir });
            else
                System.Diagnostics.Process.Start("xdg-open", new[] { dir });
        }
        catch { /* best effort */ }
    }

    private async void OnPickWatchFolder(object? sender, RoutedEventArgs e)
    {
        try
        {
            var folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
            {
                Title = "Choose a folder to watch",
                AllowMultiple = false,
            });
            if (folders.FirstOrDefault()?.TryGetLocalPath() is { } path && DataContext is EngineSettings s)
                s.WatchFolderPath = path;
        }
        catch { /* picker cancelled / failed */ }
    }

    private void OnAddPreset(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not EngineSettings s) return;
        var box = this.FindControl<TextBox>("NewPresetName");
        var name = box?.Text?.Trim();
        if (string.IsNullOrEmpty(name)) return;
        // Capture the recipe exactly as configured in Settings — Custom means the preset's
        // cut thresholds are the literal knob values shown here.
        s.AddPreset(name, Strength.Custom);
        if (box is not null) box.Text = "";
    }

    private void OnDeletePreset(object? sender, RoutedEventArgs e)
    {
        if (DataContext is EngineSettings s && (sender as Control)?.DataContext is Preset p)
            s.DeletePreset(p.Id);
    }

    private void OnSetDefaultPreset(object? sender, RoutedEventArgs e)
    {
        if (DataContext is EngineSettings s && (sender as Control)?.DataContext is Preset p)
            s.SetDefaultPreset(s.DefaultPresetId == p.Id ? null : p.Id); // toggle
    }
}
