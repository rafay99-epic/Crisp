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

    /// <summary>Select a navigation pane entry ("home" / "history" / "settings").</summary>
    public void NavigateTo(string page)
    {
        var item = page switch
        {
            "history" => NavHistory,
            "settings" => NavSettings,
            _ => NavHome,
        };
        item.IsChecked = true;
    }

    private void OnNavChanged(object? sender, RoutedEventArgs e)
    {
        // Pages exist before InitializeComponent finishes wiring names on first fire.
        if (PageHome is null || PageHistory is null || PageSettings is null) return;
        PageHome.IsVisible = NavHome.IsChecked == true;
        PageHistory.IsVisible = NavHistory.IsChecked == true;
        PageSettings.IsVisible = NavSettings.IsChecked == true;
        // History is written by the engine as cleans finish; re-read it on entry.
        if (PageHistory.IsVisible) Vm?.History.Reload();
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
        if (paths is not null)
        {
            vm.AddFiles(paths);
            NavigateTo("home"); // dropped files land in the queue — show it
        }
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
}
