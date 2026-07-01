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

        // Headless watch-folder check: drop a file in, confirm it's detected.
        //   dotnet run -- --watch-test <a-video>
        if (args.Length >= 2 && args[0] == "--watch-test")
            return RunWatchTest(args[1]);

        // Headless savings-estimate check.
        //   dotnet run -- --estimate-test <a-video>
        if (args.Length >= 2 && args[0] == "--estimate-test")
            return RunEstimateTest(args[1]).GetAwaiter().GetResult();

        // Headless preset round-trip + recipe-override check (uses a throwaway config dir).
        //   dotnet run -- --preset-test
        if (args.Length >= 1 && args[0] == "--preset-test")
            return RunPresetTest();

        // Headless channel-identity check (data-dir isolation + badges).
        //   dotnet run -- --channel-test
        if (args.Length >= 1 && args[0] == "--channel-test")
            return RunChannelTest();

        // Headless review keep-list math check (the --keep-file inverse).
        //   dotnet run -- --review-test
        if (args.Length >= 1 && args[0] == "--review-test")
            return RunReviewTest();

        // Headless onboarding-flow check (first-run gate, skip routing, persistence).
        //   dotnet run -- --onboarding-test
        if (args.Length >= 1 && args[0] == "--onboarding-test")
            return RunOnboardingTest();

        // Headless editor-detection probe (lists installed editors).
        //   dotnet run -- --editor-test
        if (args.Length >= 1 && args[0] == "--editor-test")
        {
            var editors = Crisp.Services.EditorDetector.Installed();
            foreach (var ed in editors) Console.WriteLine($"  found: {ed.Name} → {ed.LaunchPath}");
            Console.WriteLine($"editor-test: {editors.Count} editor(s) detected");
            return 0;
        }

        // Headless shell-integration probe (no-op off Windows).
        //   dotnet run -- --shell-test
        if (args.Length >= 1 && args[0] == "--shell-test")
        {
            Console.WriteLine($"explorer integration: installed={Crisp.Services.ShellIntegration.IsInstalled()} (false expected off Windows)");
            return 0;
        }

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        return 0;
    }

    private static async Task<int> RunQueueTest(string[] args)
    {
        var vm = new Crisp.ViewModels.MainWindowViewModel();
        if (args.Contains("--fillers")) vm.RemoveFillers = true;
        if (args.Contains("--retakes")) vm.RemoveRetakes = true;
        if (args.Contains("--export")) vm.Settings.ExportToEditor = true;
        if (args.Contains("--split")) { vm.Settings.SplitTracks = true; vm.Settings.SplitAudioFormat = "wav"; }
        if (args.Contains("--backup")) vm.Settings.BackupOriginal = true;
        var videos = args.Where(a => !a.StartsWith("--")).ToArray();
        vm.AddFiles(videos);
        Console.WriteLine($"toggles: fillers={vm.RemoveFillers} retakes={vm.RemoveRetakes} needsModel={vm.NeedsModel}");
        Console.WriteLine($"queued {vm.Queue.Count} file(s); pending={vm.PendingCount}; concurrency={vm.Settings.Concurrency}");
        string? notified = null;
        vm.BatchCompleted += s => notified = s;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        await vm.CleanAllCommand.ExecuteAsync(null);
        Console.WriteLine($"notification: {notified ?? "(none)"}");
        sw.Stop();
        Console.WriteLine($"batch wall time: {sw.Elapsed.TotalSeconds:F1}s");
        var ok = true;
        foreach (var item in vm.Queue)
        {
            Console.WriteLine($"  {item.Status,-9} {item.FileName}  hasBackup={item.HasBackup}  backup={item.BackupPath}  cuts=[{item.CutsSummary}]  err={item.Error}");
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
        // A genuinely-unmodeled key (e.g. a macOS-only setting) must ride through
        // JsonExtensionData so the shared settings.json never loses the Mac app's keys.
        cfg.Extra["someMacOnlyKey"] = JsonDocument.Parse("true").RootElement.Clone();
        cfg.Save();
        var back = Crisp.Models.EngineConfig.Load();
        var ok = back.VideoCodec == "h264" && back.Extra.ContainsKey("someMacOnlyKey");
        Console.WriteLine($"round-trip: codec={back.VideoCodec} extraPreserved={back.Extra.ContainsKey("someMacOnlyKey")} -> {(ok ? "OK" : "FAIL")}");
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
        Console.WriteLine($"check: state={u.State} available={u.AvailableVersion} url={u.ReleaseUrl} notesLen={u.Notes.Length} msg={u.Message}");
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

    private static async Task<int> RunEstimateTest(string video)
    {
        var vm = new Crisp.ViewModels.MainWindowViewModel();
        vm.AddFiles(new[] { video });
        await vm.EstimateCommand.ExecuteAsync(null);
        Console.WriteLine($"estimate: {vm.EstimateText}");
        return vm.EstimateText.Contains("saved") ? 0 : 1;
    }

    private static int RunWatchTest(string sampleVideo)
    {
        var tmp = Path.Combine(Path.GetTempPath(), "crisp-watch-test");
        try { if (Directory.Exists(tmp)) Directory.Delete(tmp, true); } catch { }
        Directory.CreateDirectory(tmp);
        var detected = new TaskCompletionSource<string>();
        using var watch = new Crisp.Services.WatchFolder(p => detected.TrySetResult(p));
        watch.Start(tmp);
        // A cleaned output dropped in the watched folder must be IGNORED (no infinite
        // re-clean cascade); a real input must be detected.
        File.Copy(sampleVideo, Path.Combine(tmp, "already_cleaned.mp4"));
        File.Copy(sampleVideo, Path.Combine(tmp, "incoming.mp4"));
        var got = detected.Task.Wait(TimeSpan.FromSeconds(20));
        var path = got ? detected.Task.Result : "(none)";
        // Pass only if a real input was detected AND the _cleaned file was never reported.
        var ok = got && path.EndsWith("incoming.mp4") && !path.Contains("_cleaned");
        Console.WriteLine($"watch: detected={got} path={path} -> {(ok ? "OK" : "FAIL")}");
        try { Directory.Delete(tmp, true); } catch { }
        return ok ? 0 : 1;
    }

    private static int RunPresetTest()
    {
        // Point the config at a temp dir so the user's real settings.json is untouched.
        var dir = Path.Combine(Path.GetTempPath(), "crisp-preset-test");
        try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch { }
        Directory.CreateDirectory(dir);
        Environment.SetEnvironmentVariable("CRISP_CONFIG_DIR", dir);

        var ok = true;
        void Check(bool c, string what) { Console.WriteLine($"  [{(c ? "ok" : "FAIL")}] {what}"); ok &= c; }

        // Create a preset that differs from the global recipe, then reload from disk.
        var s1 = new Crisp.Services.EngineSettings { VideoCodec = "h264", AudioCodec = "opus", OutputContainer = "mkv" };
        var p = s1.AddPreset("Tiny", Crisp.Models.Strength.Gentle);
        s1.SetDefaultPreset(p.Id);

        var s2 = new Crisp.Services.EngineSettings(); // re-read settings.json
        Check(s2.Presets.Count == 1 && s2.Presets[0].Name == "Tiny", "preset persisted + reloaded");
        Check(s2.DefaultPresetId == p.Id, "default preset id persisted");
        Check(s2.Presets[0].VideoCodec == "h264" && s2.Presets[0].OutputContainer == "mkv", "preset captured global recipe");
        Check(s2.Presets[0].Strength == "Gentle", "preset strength rawValue matches macOS");

        // The preset overrides the recipe knobs; a Gentle preset implies --pause 0.8.
        var recipe = string.Join(" ", s2.RecipeArgs(Crisp.Models.Strength.Aggressive, s2.Presets[0]));
        Check(recipe.Contains("--video-codec h264"), "recipe uses preset video codec");
        Check(recipe.Contains("--container mkv"), "recipe uses preset container");
        Check(recipe.Contains("--pause 0.8"), "recipe uses preset (Gentle) pause threshold");

        s2.DeletePreset(p.Id);
        var s3 = new Crisp.Services.EngineSettings();
        Check(s3.Presets.Count == 0 && string.IsNullOrEmpty(s3.DefaultPresetId), "delete clears preset + default");

        try { Directory.Delete(dir, true); } catch { }
        Console.WriteLine($"preset-test: {(ok ? "PASS" : "FAIL")}");
        return ok ? 0 : 1;
    }

    private static int RunChannelTest()
    {
        var ok = true;
        void Check(bool c, string what) { Console.WriteLine($"  [{(c ? "ok" : "FAIL")}] {what}"); ok &= c; }

        Check(Crisp.Channel.Stable.DisplayName() == "Crisp"
              && Crisp.Channel.Nightly.DisplayName() == "Crisp Nightly"
              && Crisp.Channel.Dev.DisplayName() == "Crisp Dev", "display names");
        Check(Crisp.Channel.Stable.Badge() is null
              && Crisp.Channel.Nightly.Badge() == "NIGHTLY"
              && Crisp.Channel.Dev.Badge() == "DEV", "badges");
        Check(Crisp.Channel.Stable.DataDirSuffix() == ".crisp"
              && Crisp.Channel.Nightly.DataDirSuffix() == ".crisp-nightly"
              && Crisp.Channel.Dev.DataDirSuffix() == ".crisp-dev", "data dir suffixes are distinct (side-by-side installs)");
        Check(!Crisp.Channel.Dev.UpdatesEnabled()
              && Crisp.Channel.Stable.UpdatesEnabled()
              && Crisp.Channel.Nightly.UpdatesEnabled(), "dev has no updater");
        Check(Crisp.Channel.Nightly.IsPrerelease() && !Crisp.Channel.Stable.IsPrerelease(), "nightly is a prerelease channel");
        Check(Crisp.Channel.Dev.AssetName() is null && Crisp.Channel.Stable.AssetName() is not null, "dev publishes no installer");

        var tmp = Path.Combine(Path.GetTempPath(), "crisp-chan");
        Environment.SetEnvironmentVariable("CRISP_DATA_DIR", tmp);
        Check(Crisp.Channels.DataDirectory == tmp, "CRISP_DATA_DIR overrides the data home");
        Check(Crisp.Channels.ConfigDirectory == Path.Combine(tmp, "config"), "config/models/logs derive from the data home");
        Environment.SetEnvironmentVariable("CRISP_DATA_DIR", null);

        Console.WriteLine($"channel-test: {(ok ? "PASS" : "FAIL")}");
        return ok ? 0 : 1;
    }

    private static int RunReviewTest()
    {
        var ok = true;
        void Check(bool c, string what) { Console.WriteLine($"  [{(c ? "ok" : "FAIL")}] {what}"); ok &= c; }

        // duration 10; remove [2,3] and [6,7]; a disabled cut at [8,9] stays in the output.
        var regions = new[]
        {
            new Crisp.Models.CutRegion { Start = 2, End = 3, Remove = true },
            new Crisp.Models.CutRegion { Start = 6, End = 7, Remove = true },
            new Crisp.Models.CutRegion { Start = 8, End = 9, Remove = false },
        };
        var keeps = Crisp.Services.ReviewPlan.KeepSegments(10, regions);
        Check(keeps.Count == 3, "3 keep segments");
        Check(keeps[0][0] == 0 && keeps[0][1] == 2, "keep 0..2");
        Check(keeps[1][0] == 3 && keeps[1][1] == 6, "keep 3..6");
        Check(keeps[2][0] == 7 && keeps[2][1] == 10, "keep 7..10 (disabled cut kept)");

        // Overlapping removals merge into one gap.
        var overlap = new[]
        {
            new Crisp.Models.CutRegion { Start = 1, End = 4, Remove = true },
            new Crisp.Models.CutRegion { Start = 3, End = 5, Remove = true },
        };
        var k2 = Crisp.Services.ReviewPlan.KeepSegments(8, overlap);
        Check(k2.Count == 2 && k2[0][1] == 1 && k2[1][0] == 5, "overlapping cuts merge (keep 0..1, 5..8)");

        var f = Crisp.Services.ReviewPlan.WriteKeepFile(10, regions);
        var content = System.IO.File.ReadAllText(f);
        System.IO.File.Delete(f);
        Check(content.Contains("\"keep\""), "keep-file has the keep key");

        Console.WriteLine($"review-test: {(ok ? "PASS" : "FAIL")}");
        return ok ? 0 : 1;
    }

    private static int RunOnboardingTest()
    {
        // Isolated data home so the user's real marker/settings/models are untouched.
        var tmp = Path.Combine(Path.GetTempPath(), "crisp-onboarding-test");
        try { if (Directory.Exists(tmp)) Directory.Delete(tmp, true); } catch { }
        Directory.CreateDirectory(tmp);
        Environment.SetEnvironmentVariable("CRISP_DATA_DIR", tmp);
        Environment.SetEnvironmentVariable("CRISP_CONFIG_DIR", Path.Combine(tmp, "config"));
        Environment.SetEnvironmentVariable("CRISP_MODELS_DIR", Path.Combine(tmp, "models"));

        var ok = true;
        void Check(bool c, string what) { Console.WriteLine($"  [{(c ? "ok" : "FAIL")}] {what}"); ok &= c; }

        var settings = new Crisp.Services.EngineSettings();
        var models = new Crisp.Services.ModelStore();
        var filler = new Crisp.Services.ModelStore(Crisp.Models.FillerModelCatalog.Wren, fetchSidecar: false, logLabel: "filler-model");
        var tour = new Crisp.Services.OnboardingController(models, filler, settings, fillerAvailable: true);

        Check(tour.IsPresented, "first run presents the tour");
        Check(tour.Step == Crisp.Services.OnboardingStep.Welcome && !tour.ShowsBack, "starts on Welcome with Skip");
        Check(!settings.HasExistingConfig, "fresh data home reads as a new user");

        // Skip must route to the unsatisfied model step, never exit past the gate.
        tour.SkipCommand.Execute(null);
        Check(tour.Step == Crisp.Services.OnboardingStep.Model, "skip routes to the model step");
        Check(!tour.CanContinue && tour.IsPresented, "model step gates Continue while nothing is installed");
        tour.ContinueCommand.Execute(null);
        Check(tour.Step == Crisp.Services.OnboardingStep.Model, "gated Continue doesn't advance");

        // Wren, Crisp's custom model: pinned to the same HF repo + hash as macOS.
        var wren = Crisp.Models.FillerModelCatalog.Wren;
        Check(wren.Url.Contains("rafay99-epic/crisp-models") && wren.Url.Contains("v0.0.10"), "Wren pinned to the macOS catalog URL");
        Check(wren.ApproxSizeText == "514 KB", "sub-MB sizes render as KB");
        Check(wren.SidecarFileName == "Wren.config.json" && wren.SidecarUrl.EndsWith("v0.0.10/Wren.config.json"), "sidecar config derives from the model URL");

        // Selecting Wren flips the shared fillerModelEnabled key and re-points the gate
        // at the Wren install (not yet ready → still gated).
        tour.IsWrenSelected = true;
        Check(settings.FillerModelEnabled && tour.IsWrenSelected && !tour.IsBaseSelected, "picking Wren enables the filler model");
        Check(!tour.ModelSatisfied, "Wren selected but not installed → gate stays closed");
        settings.CaptionsFormat = "srt";
        settings.FillerModelEnabled = false; settings.FillerModelEnabled = true;
        Check(settings.CaptionsFormat == "none", "enabling Wren clears captions (no transcript)");

        // Back to whisper: a custom .bin satisfies the gate (works on every channel —
        // the data home is per-channel, so each keeps its own choice).
        tour.IsBaseSelected = true;
        Check(!settings.FillerModelEnabled, "picking a whisper model turns Wren off");
        var custom = Path.Combine(tmp, "my-model.bin");
        File.WriteAllText(custom, "x");
        settings.CustomModelPath = custom;
        Check(tour.ModelSatisfied && tour.CanContinue, "a custom model satisfies the gate");

        // Walk to the end; the last Continue completes, writes the marker, and
        // persists the whole chosen setup to settings.json (even all-defaults).
        settings.VideoQuality = "maximum"; // a preferences-step knob, set mid-tour
        while (!tour.IsLast) tour.ContinueCommand.Execute(null);
        Check(tour.ContinueLabel == "Get Started", "last step relabels Continue");
        tour.ContinueCommand.Execute(null);
        Check(!tour.IsPresented, "finishing dismisses the tour");
        Check(File.Exists(Crisp.Models.EngineConfig.FilePath), "finishing writes settings.json");
        var saved = Crisp.Models.EngineConfig.Load();
        Check(saved.SelectedModelId == settings.SelectedModelId && saved.CustomModelPath == custom,
            "settings.json captures the chosen model setup");

        // Onboarding and the Settings page share one config file: what the tour set is
        // exactly what a fresh EngineSettings (= the Settings page after a relaunch) reads.
        var settingsPage = new Crisp.Services.EngineSettings();
        Check(settingsPage.VideoQuality == "maximum"
              && settingsPage.SelectedModelId == settings.SelectedModelId
              && settingsPage.CustomModelPath == custom
              && settingsPage.HasExistingConfig,
            "Settings page reads back exactly what onboarding wrote (shared config)");

        var again = new Crisp.Services.OnboardingController(models, filler, settings, fillerAvailable: true);
        Check(!again.IsPresented, "the marker persists — no re-present on next launch");
        again.Present();
        Check(again.IsPresented && again.Step == Crisp.Services.OnboardingStep.Welcome, "re-openable from Settings");

        // Model selection helpers drive the shared settings key.
        again.IsTurboSelected = true;
        Check(settings.SelectedModelId == "large-v3-turbo", "picking Turbo persists the catalog id");
        again.IsBaseSelected = true;
        Check(settings.SelectedModelId == "base.en", "picking Base persists the catalog id");

        Environment.SetEnvironmentVariable("CRISP_DATA_DIR", null);
        Environment.SetEnvironmentVariable("CRISP_CONFIG_DIR", null);
        Environment.SetEnvironmentVariable("CRISP_MODELS_DIR", null);
        try { Directory.Delete(tmp, true); } catch { }
        Console.WriteLine($"onboarding-test: {(ok ? "PASS" : "FAIL")}");
        return ok ? 0 : 1;
    }

    // Avalonia configuration, don't remove; also used by visual designer.
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
#if DEBUG
            .WithDeveloperTools()
#endif
            .LogToTrace();
}
