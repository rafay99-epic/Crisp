using System.Linq;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Crisp.ViewModels;

namespace Crisp.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private async void OnBrowse(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Choose a video",
            AllowMultiple = false,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("Video") { Patterns = new[] { "*.mp4", "*.mov", "*.mkv", "*.m4v" } },
            },
        });

        if (files.FirstOrDefault()?.TryGetLocalPath() is { } path && DataContext is MainWindowViewModel vm)
            vm.VideoPath = path;
    }
}
