using Avalonia;
using System;
using System.IO;
using System.Linq;
using System.Text.Json;
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

        // Headless model check: derive state from disk, download if absent.
        //   dotnet run -- --model-test
        if (args.Length >= 1 && args[0] == "--model-test")
            return RunModelTest().GetAwaiter().GetResult();

        // Headless queue batch: drive the real ViewModel through a multi-file clean.
        //   dotnet run -- --queue-test <video1> <video2> …
        if (args.Length >= 2 && args[0] == "--queue-test")
            return RunQueueTest(args[1..]).GetAwaiter().GetResult();

        // Headless settings check: load config, build recipe args, round-trip a save.
        //   dotnet run -- --settings-test
        if (args.Length >= 1 && args[0] == "--settings-test")
            return RunSettingsTest();

        // Headless updater check: version-compare + a real GitHub release query.
        //   dotnet run -- --update-test
        if (args.Length >= 1 && args[0] == "--update-test")
            return RunUpdateTest();

        // Headless history check: record → reload → verify (in a temp data dir).
        //   dotnet run -- --history-test
        if (args.Length >= 1 && args[0] == "--history-test")
            return RunHistoryTest();

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        return 0;
    }

    private static async Task<int> RunQueueTest(string[] args)
    {
        var vm = new Crisp.ViewModels.MainWindowViewModel();
        if (args.Contains("--fillers")) vm.RemoveFillers = true;
        if (args.Contains("--retakes")) vm.RemoveRetakes = true;
        if (args.Contains("--export")) vm.Settings.ExportToEditor = true;
        var videos = args.Where(a => !a.StartsWith("--")).ToArray();
        vm.AddFiles(videos);
        Console.WriteLine($"toggles: fillers={vm.RemoveFillers} retakes={vm.RemoveRetakes} needsModel={vm.NeedsModel}");
        Console.WriteLine($"queued {vm.Queue.Count} file(s); pending={vm.PendingCount}; concurrency={vm.Settings.Concurrency}");
        var sw = System.Diagnostics.Stopwatch.StartNew();
        await vm.CleanAllCommand.ExecuteAsync(null);
        sw.Stop();
        Console.WriteLine($"batch wall time: {sw.Elapsed.TotalSeconds:F1}s");
        var ok = true;
        foreach (var item in vm.Queue)
        {
            Console.WriteLine($"  {item.Status,-9} {item.FileName}  editor={item.IsEditorExport}  out={item.OutputPath}  cuts=[{item.CutsSummary}]  err={item.Error}");
            ok &= item.Status == Crisp.Models.QueueStatus.Done;
        }
        Console.WriteLine($"summary: {vm.SummaryText}");
        return ok ? 0 : 1;
    }

    private static async Task<int> RunHeadless(string[] args)
    {
        var video = args[1];
        if (video.StartsWith('-') || !File.Exists(video))
        {
            Console.Error.WriteLine("usage: --headless <video> [--engine <clean_video.py>]");
            return 2;
        }
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

    private static async Task<int> RunModelTest()
    {
        Console.WriteLine("catalog: " + string.Join(", ",
            Crisp.Models.ModelCatalog.All.Select(m => $"{m.Id} ({m.ApproxSizeText})")));
        var store = new Crisp.Services.ModelStore();
        Console.WriteLine($"models dir: {store.ModelsDir}");
        await store.RefreshAsync();
        Console.WriteLine($"base:  spec={store.Spec.Id} size={store.SizeText} state={store.State} ready={store.IsReady}");

        await store.UseAsync("large-v3-turbo"); // switch to the big model (likely Absent)
        Console.WriteLine($"turbo: spec={store.Spec.Id} size={store.SizeText} state={store.State}");
        var ok = store.Spec.Id == "large-v3-turbo" && store.SizeText == "574 MB";
        Console.WriteLine($"switch -> {(ok ? "OK" : "FAIL")}");
        return ok ? 0 : 1;
    }

    private static int RunSettingsTest()
    {
        // 1) Read the real config (proves the Mac settings.json schema loads).
        var s = new Crisp.Services.EngineSettings();
        Console.WriteLine($"loaded: codec={s.VideoCodec} hw={s.HardwareEncoding} quality={s.VideoQuality} " +
                          $"container={s.OutputContainer} backup={s.BackupOriginal} pause={s.PauseThreshold}");
        Console.WriteLine("recipe(Aggressive): " + string.Join(' ', s.RecipeArgs(Crisp.Models.Strength.Aggressive)));
        Console.WriteLine("recipe(Custom):     " + string.Join(' ', s.RecipeArgs(Crisp.Models.Strength.Custom)));

        // 2) Round-trip a save in a temp config dir (don't touch the real file).
        var tmp = Path.Combine(Path.GetTempPath(), "crisp-settings-test");
        Directory.CreateDirectory(tmp);
        Environment.SetEnvironmentVariable("CRISP_CONFIG_DIR", tmp);
        try { File.Delete(Crisp.Models.EngineConfig.FilePath); } catch { }
        var cfg = Crisp.Models.EngineConfig.Load();
        cfg.VideoCodec = "h264";
        cfg.Extra["presets"] = JsonDocument.Parse("[]").RootElement.Clone();
        cfg.Save();
        var back = Crisp.Models.EngineConfig.Load();
        var ok = back.VideoCodec == "h264" && back.Extra.ContainsKey("presets");
        Console.WriteLine($"round-trip: codec={back.VideoCodec} extraPreserved={back.Extra.ContainsKey("presets")} -> {(ok ? "OK" : "FAIL")}");
        return ok ? 0 : 1;
    }

    private static int RunUpdateTest()
    {
        Console.WriteLine($"current version: {CrispVersion.Current}");
        // Version-compare sanity (the 0.9 vs 0.10 case catches a naive string compare).
        Console.WriteLine($"IsNewer(0.15,0.14)={Updater.IsNewer("0.15", "0.14")} " +
                          $"IsNewer(0.14,0.14)={Updater.IsNewer("0.14", "0.14")} " +
                          $"IsNewer(0.9,0.10)={Updater.IsNewer("0.9", "0.10")}");
        var u = new Updater();
        u.CheckAsync().GetAwaiter().GetResult();
        Console.WriteLine($"check: state={u.State} available={u.AvailableVersion} url={u.ReleaseUrl} msg={u.Message}");
        var compareOk = Updater.IsNewer("0.15", "0.14") && !Updater.IsNewer("0.14", "0.14") && !Updater.IsNewer("0.9", "0.10");
        return compareOk && u.State is UpdaterState.Available or UpdaterState.UpToDate ? 0 : 1;
    }

    private static int RunHistoryTest()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "crisp-history-test");
        Directory.CreateDirectory(tmp);
        Environment.SetEnvironmentVariable("CRISP_DATA_DIR", tmp);
        try { File.Delete(Path.Combine(tmp, "history.jsonl")); } catch { }

        var store = new Crisp.Services.HistoryStore();
        store.Record(new Crisp.Models.HistoryEntry { Date = new DateTime(2026, 6, 29, 10, 0, 0, DateTimeKind.Utc), InputPath = "/a/first.mp4", OutputPath = "/a/first_cleaned.mp4", SavedSeconds = 12, Pauses = 3 });
        store.Record(new Crisp.Models.HistoryEntry { Date = new DateTime(2026, 6, 29, 11, 0, 0, DateTimeKind.Utc), InputPath = "/a/second.mp4", OutputPath = "/a/second_cleaned.mp4", SavedSeconds = 90, Fillers = 4, Retakes = 1 });

        var reloaded = new Crisp.Services.HistoryStore(); // reads the file fresh
        var ok = reloaded.Entries.Count == 2 && reloaded.Entries[0].InputName == "second.mp4"; // newest first
        Console.WriteLine($"history: persisted={reloaded.Entries.Count} newestFirst={reloaded.Entries[0].InputName} saved0={reloaded.Entries[0].SavedText} cuts0=[{reloaded.Entries[0].CutsText}] -> {(ok ? "OK" : "FAIL")}");
        return ok ? 0 : 1;
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
