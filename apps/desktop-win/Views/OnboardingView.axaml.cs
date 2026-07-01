using System.Linq;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Crisp.ViewModels;

namespace Crisp.Views;

public partial class OnboardingView : UserControl
{
    private MainWindowViewModel? Vm => DataContext as MainWindowViewModel;

    public OnboardingView()
    {
        InitializeComponent();
    }

    private async void OnPickWatchFolder(object? sender, RoutedEventArgs e)
    {
        try
        {
            if (TopLevel.GetTopLevel(this) is not { } top || Vm is not { } vm) return;
            var folders = await top.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
            {
                Title = "Choose a folder to watch",
                AllowMultiple = false,
            });
            if (folders.FirstOrDefault()?.TryGetLocalPath() is { } path)
                vm.Settings.WatchFolderPath = path;
        }
        catch { /* picker cancelled / failed */ }
    }
}
