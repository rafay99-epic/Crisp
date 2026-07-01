using System.Linq;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Crisp.Models;
using Crisp.Services;

namespace Crisp.Views.Pages;

public partial class SettingsPage : UserControl
{
    public SettingsPage()
    {
        InitializeComponent();
        AboutRow.Header = $"{Channels.Current.DisplayName()} {CrispVersion.Current}";
    }

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
            if (TopLevel.GetTopLevel(this) is not { } top) return;
            var folders = await top.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
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
