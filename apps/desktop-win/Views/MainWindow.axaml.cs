using System;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Controls.Notifications;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using Crisp.ViewModels;

namespace Crisp.Views;

public partial class MainWindow : Window
{
    private MainWindowViewModel? Vm => DataContext as MainWindowViewModel;
    private MainWindowViewModel? _subscribedVm;
    private WindowNotificationManager? _notifications;

    public MainWindow()
    {
        InitializeComponent();
        WindowChrome.ApplyMica(this);

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

    protected override void OnDataContextChanged(EventArgs e)
    {
        // Detach from the previous view model, not the new one, so a rebind can't leave a
        // stale BatchCompleted subscription behind (duplicate toasts / a leaked window).
        if (_subscribedVm is not null) _subscribedVm.BatchCompleted -= OnBatchCompleted;
        base.OnDataContextChanged(e);
        _subscribedVm = DataContext as MainWindowViewModel;
        if (_subscribedVm is not null) _subscribedVm.BatchCompleted += OnBatchCompleted;
    }

    private void OnBatchCompleted(string summary) => Dispatcher.UIThread.Post(() =>
    {
        _notifications ??= new WindowNotificationManager(this) { Position = NotificationPosition.BottomRight, MaxItems = 3 };
        _notifications.Show(new Notification("Crisp", summary, NotificationType.Success));
    });

    private void OnSettings(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm) return;
        // Shares the live EngineSettings instance — edits persist immediately.
        new SettingsWindow { DataContext = vm.Settings }.ShowDialog(this);
    }

    private void OnWhatsNew(object? sender, RoutedEventArgs e)
    {
        if (Vm is { } vm) new WhatsNewWindow { DataContext = vm.Updater }.ShowDialog(this);
    }

    private void OnHistory(object? sender, RoutedEventArgs e)
    {
        if (Vm is not { } vm) return;
        vm.History.Reload();
        new HistoryWindow { DataContext = vm.History }.ShowDialog(this);
    }

    private async void OnRestore(object? sender, RoutedEventArgs e)
    {
        // async void: guard the whole body so a picker failure can't crash the app.
        try
        {
            if (Vm is not { } vm || (sender as Control)?.DataContext is not Models.QueueItem item) return;
            var folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
            {
                Title = "Restore the original to…",
                AllowMultiple = false,
            });
            if (folders.FirstOrDefault()?.TryGetLocalPath() is { } dir) vm.RestoreOriginal(item, dir);
        }
        catch { /* picker cancelled / copy failed — nothing to do */ }
    }

    private async void OnReview(object? sender, RoutedEventArgs e)
    {
        // async void: an unhandled exception here would crash the app, so guard the whole body.
        try
        {
            if (Vm is not { } vm || (sender as Control)?.DataContext is not Models.QueueItem item) return;
            var review = vm.CreateReview(item);
            var win = new ReviewWindow { DataContext = review };
            _ = review.LoadAsync(); // analyze in the background; the window shows "Analyzing…"
            var applied = await win.ShowDialog<bool>(this);
            if (applied) await vm.ApplyReviewAndCleanAsync(item, review);
        }
        catch { /* review/clean failure is surfaced on the row; never crash the window */ }
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
                    new FilePickerFileType("Video") { Patterns = Crisp.VideoTypes.Extensions.Select(x => "*" + x).ToList() },
                },
            });
            var paths = files.Select(f => f.TryGetLocalPath()).Where(p => p is not null).Select(p => p!).ToList();
            if (paths.Count > 0 && Vm is { } vm) vm.AddFiles(paths);
        }
        catch { /* picker cancelled / failed — nothing to add */ }
    }
}
