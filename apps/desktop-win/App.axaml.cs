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
            // The XAML tray icon is the Stable asset; swap in the channel icon + name
            // so a Nightly/Dev instance is tellable apart in the tray.
            if (TrayIcon.GetIcons(this) is { Count: > 0 } trayIcons)
            {
                trayIcons[0].Icon = WindowChrome.ChannelIcon();
                trayIcons[0].ToolTipText = Crisp.Channels.Current.DisplayName();
            }

            var vm = new MainWindowViewModel();
            var window = new MainWindow { DataContext = vm, Title = Crisp.Channels.Current.DisplayName() };
            desktop.MainWindow = window;

            // Dev: --settings / --history open the shell on that page (for screenshots),
            // skipping the first-run onboarding cover so the page is actually visible.
            if (desktop.Args?.Contains("--settings") == true)
            {
                vm.Onboarding.Complete();
                window.NavigateTo("settings");
            }
            else if (desktop.Args?.Contains("--history") == true)
            {
                vm.Onboarding.Complete();
                window.NavigateTo("history");
            }

            // "Open With" / file-association: video paths on the command line are queued
            // (both Windows and macOS pass argv).
            var files = desktop.Args?.Where(a => !a.StartsWith('-') && System.IO.File.Exists(a)).ToList();
            if (files is { Count: > 0 }) vm.AddFiles(files);
        }

        base.OnFrameworkInitializationCompleted();
    }
}