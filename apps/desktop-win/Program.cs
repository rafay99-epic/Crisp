using Avalonia;
using System;
using System.Threading;
using System.Threading.Tasks;
using Crisp.Models;
using Crisp.Services;

namespace Crisp;

sealed class Program
{
    // Initialization code. Don't use any Avalonia, third-party APIs or any
    // SynchronizationContext-reliant code before AppMain is called: things aren't initialized
    // yet and stuff might break.
    [STAThread]
    public static int Main(string[] args)
    {
        // Headless smoke test of the engine pipe (no GUI). Doubles as a CI check:
        //   dotnet run -- --headless <video> [--engine <clean_video.py>]
        if (args.Length >= 2 && args[0] == "--headless")
            return RunHeadless(args).GetAwaiter().GetResult();

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        return 0;
    }

    private static async Task<int> RunHeadless(string[] args)
    {
        var video = args[1];
        var engineIdx = Array.IndexOf(args, "--engine");
        var script = engineIdx >= 0 && engineIdx + 1 < args.Length
            ? args[engineIdx + 1]
            : Environment.GetEnvironmentVariable("CRISP_ENGINE_SCRIPT") ?? "clean_video.py";

        var engine = new CrispEngine { ScriptPath = script };
        var progress = new Progress<EngineEvent>(ev =>
        {
            var detail = ev.Event switch
            {
                "progress" => $"{(ev.Fraction ?? 0) * 100,5:F1}%  {ev.Label}",
                "log" => ev.Message,
                _ => ev.Raw,
            };
            Console.WriteLine($"[{ev.Event}] {detail}");
        });

        var code = await engine.RunAsync(
            video, new[] { "--no-fillers", "--no-retakes", "--no-backup" },
            progress, CancellationToken.None);
        Console.WriteLine($"engine exit code: {code}");
        return code;
    }

    // Avalonia configuration, don't remove; also used by visual designer.
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
#if DEBUG
            .WithDeveloperTools()
#endif
            .WithInterFont()
            .LogToTrace();
}
