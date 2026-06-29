using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using System;
using System.Linq;
using Avalonia.Markup.Xaml;
using Crisp.ViewModels;
using Crisp.Views;

namespace Crisp;

public partial class App : Application
{
    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    // System-tray handlers (the menu-bar quick access).
    private void OnTrayClicked(object? sender, EventArgs e) => ShowMainWindow();
    private void OnTrayOpen(object? sender, EventArgs e) => ShowMainWindow();

    private void OnTrayQuit(object? sender, EventArgs e)
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime d) d.Shutdown();
    }

    private void ShowMainWindow()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime d && d.MainWindow is { } w)
        {
            w.Show();
            w.WindowState = WindowState.Normal;
            w.Activate();
        }
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // Dev: --settings opens the Settings window directly (for screenshots) — construct
            // EngineSettings alone, not the full VM (which would start engine/model resolution).
            if (desktop.Args?.Contains("--settings") == true)
            {
                desktop.MainWindow = new SettingsWindow { DataContext = new Crisp.Services.EngineSettings() };
                base.OnFrameworkInitializationCompleted();
                return;
            }
            // Dev: --history opens the History window (reads CRISP_DATA_DIR for screenshots).
            if (desktop.Args?.Contains("--history") == true)
            {
                desktop.MainWindow = new HistoryWindow { DataContext = new Crisp.Services.HistoryStore() };
                base.OnFrameworkInitializationCompleted();
                return;
            }
            var vm = new MainWindowViewModel();
            desktop.MainWindow = new MainWindow { DataContext = vm, Title = Crisp.Channels.Current.DisplayName() };

            // "Open With" / file-association: video paths on the command line are queued
            // (both Windows and macOS pass argv).
            var files = desktop.Args?.Where(a => !a.StartsWith('-') && System.IO.File.Exists(a)).ToList();
            if (files is { Count: > 0 }) vm.AddFiles(files);
        }

        base.OnFrameworkInitializationCompleted();
    }
}