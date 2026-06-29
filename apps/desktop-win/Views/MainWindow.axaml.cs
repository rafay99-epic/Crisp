using System.Linq;
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
        var paths = e.DataTransfer.TryGetFiles()?
            .Select(f => f.TryGetLocalPath())
            .Where(p => p is not null)
            .Select(p => p!);
        if (paths is not null) vm.AddFiles(paths);
    }

    private void OnSettings(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm) return;
        // Shares the live EngineSettings instance — edits persist immediately.
        new SettingsWindow { DataContext = vm.Settings }.ShowDialog(this);
    }

    private async void OnBrowse(object? sender, RoutedEventArgs e)
    {
        // async void: any exception here would crash the app, so swallow picker failures.
        try
        {
            var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Choose videos",
                AllowMultiple = true,
                FileTypeFilter = new[]
                {
                    new FilePickerFileType("Video") { Patterns = new[] { "*.mp4", "*.mov", "*.mkv", "*.m4v", "*.webm" } },
                },
            });
            var paths = files.Select(f => f.TryGetLocalPath()).Where(p => p is not null).Select(p => p!).ToList();
            if (paths.Count > 0 && Vm is { } vm) vm.AddFiles(paths);
        }
        catch { /* picker cancelled / failed — nothing to add */ }
    }
}
