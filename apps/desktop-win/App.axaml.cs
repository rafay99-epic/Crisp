using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Data.Core;
using Avalonia.Data.Core.Plugins;
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

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            var vm = new MainWindowViewModel();
            desktop.MainWindow = new MainWindow { DataContext = vm };

            // "Open With" / file-association: a video path passed on the command line
            // opens straight into the Ready state (both Windows and macOS pass argv).
            var file = desktop.Args?.FirstOrDefault(a => !a.StartsWith('-'));
            if (file is not null && System.IO.File.Exists(file)) vm.SetFile(file);
        }

        base.OnFrameworkInitializationCompleted();
    }
}