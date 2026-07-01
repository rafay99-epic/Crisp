using System.Linq;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Crisp.ViewModels;

namespace Crisp.Views.Pages;

public partial class HomePage : UserControl
{
    private MainWindowViewModel? Vm => DataContext as MainWindowViewModel;
    private Window? Owner => TopLevel.GetTopLevel(this) as Window;

    public HomePage()
    {
        InitializeComponent();
    }

    private void OnWhatsNew(object? sender, RoutedEventArgs e)
    {
        if (Vm is { } vm && Owner is { } owner)
            new WhatsNewWindow { DataContext = vm.Updater }.ShowDialog(owner);
    }

    private async void OnRestore(object? sender, RoutedEventArgs e)
    {
        // async void: guard the whole body so a picker failure can't crash the app.
        try
        {
            if (Vm is not { } vm || Owner is not { } owner
                || (sender as Control)?.DataContext is not Models.QueueItem item) return;
            var folders = await owner.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
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
            if (Vm is not { } vm || Owner is not { } owner
                || (sender as Control)?.DataContext is not Models.QueueItem item) return;
            var review = vm.CreateReview(item);
            var win = new ReviewWindow { DataContext = review };
            _ = review.LoadAsync(); // analyze in the background; the window shows "Analyzing…"
            var applied = await win.ShowDialog<bool>(owner);
            if (applied) await vm.ApplyReviewAndCleanAsync(item, review);
        }
        catch { /* review/clean failure is surfaced on the row; never crash the window */ }
    }

    private async void OnBrowse(object? sender, RoutedEventArgs e)
    {
        // async void: any exception here would crash the app, so swallow picker failures.
        try
        {
            if (Owner is not { } owner) return;
            var files = await owner.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
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
