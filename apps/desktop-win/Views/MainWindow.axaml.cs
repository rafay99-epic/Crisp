using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Crisp.ViewModels;

namespace Crisp.Views;

public partial class MainWindow : Window
{
    private MainWindowViewModel? Vm => DataContext as MainWindowViewModel;

    public MainWindow()
    {
        InitializeComponent();

        // Window-wide drag-drop (matches the Mac app, which accepts a drop anywhere).
        DragDrop.SetAllowDrop(this, true);
        AddHandler(DragDrop.DragEnterEvent, OnDragOver);
        AddHandler(DragDrop.DragOverEvent, OnDragOver);
        AddHandler(DragDrop.DragLeaveEvent, (_, _) => { if (Vm is { } vm) vm.IsDropTargeted = false; });
        AddHandler(DragDrop.DropEvent, OnDrop);
    }

    private void OnDragOver(object? sender, DragEventArgs e)
    {
        var ok = e.DataTransfer.Contains(DataFormat.File);
        e.DragEffects = ok ? DragDropEffects.Copy : DragDropEffects.None;
        if (Vm is { } vm) vm.IsDropTargeted = ok;
    }

    private void OnDrop(object? sender, DragEventArgs e)
    {
        if (Vm is not { } vm) return;
        vm.IsDropTargeted = false;
        var path = e.DataTransfer.TryGetFile()?.TryGetLocalPath();
        if (path is not null) vm.SetFile(path);
    }

    private async void OnBrowse(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Choose a video",
            AllowMultiple = false,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("Video") { Patterns = new[] { "*.mp4", "*.mov", "*.mkv", "*.m4v", "*.webm" } },
            },
        });
        if (files.FirstOrDefault()?.TryGetLocalPath() is { } path && Vm is { } vm)
            vm.SetFile(path);
    }

    private void OnReveal(object? sender, RoutedEventArgs e)
    {
        var path = Vm?.OutputPath;
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;

        // Reveal the output in the OS file browser. ponytail: per-OS one-liners,
        // no library — Windows uses the shipped path, macOS/Linux for dev.
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
        else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            Process.Start("open", new[] { "-R", path });
        else
            Process.Start("xdg-open", new[] { Path.GetDirectoryName(path) ?? "." });
    }
}
