using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using Crisp.Models;

namespace Crisp.Services;

/// Live, editable settings persisted to ~/.crisp/config/settings.json. Port of the
/// macOS EngineSettings: loads on construct (defaults fill missing keys), writes back
/// atomically on every change, and builds the per-clean recipe args. Unmodeled keys
/// ride through EngineConfig.Extra, so the shared file keeps everything.
public partial class EngineSettings : ObservableObject
{
    // Cutting (Custom strength)
    [ObservableProperty] private double _pauseThreshold;
    [ObservableProperty] private double _silenceFloorDB;
    [ObservableProperty] private double _breathingRoom;
    [ObservableProperty] private double _minKeep;
    // Smoothing
    [ObservableProperty] private double _fadeMs;
    [ObservableProperty] private double _crossfadeMs;
    [ObservableProperty] private double _snapMs;
    // Encoding
    [ObservableProperty] private string _videoCodec = "hevc";
    [ObservableProperty] private bool _hardwareEncoding = true;
    /// Live blurb under the Hardware Acceleration row — replaced by the engine's
    /// --probe-hardware answer shortly after launch (GPU names + what they accelerate).
    [ObservableProperty] private string _hardwareStatus =
        "Use the GPU media engine (NVENC / QSV / AMF) when available.";
    /// The raw probe answer, for the onboarding hardware step (null until the probe lands).
    [ObservableProperty] private Models.HardwareInfo? _lastHardwareInfo;
    [ObservableProperty] private string _videoQuality = "high";
    [ObservableProperty] private string _audioCodec = "aac";
    [ObservableProperty] private int _audioBitrateKbps = 192;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ForcesOwnCodecs))]
    private string _outputContainer = "auto";

    /// WebM can only hold VP9 + Opus, so the engine coerces the codec choice — the Settings
    /// UI greys out the video/audio/HW controls when WebM is selected (they don't apply).
    /// Parity with macOS OutputContainer.forcesOwnCodecs.
    public bool ForcesOwnCodecs => OutputContainer == "webm";
    [ObservableProperty] private string _colorDepth = "auto";
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsConstantFps))]
    private string _frameRateMode = "auto";
    [ObservableProperty] private double _frameRateValue;

    /// "constant" needs a target fps value; the Settings UI shows the input only then.
    public bool IsConstantFps => FrameRateMode == "constant";
    [ObservableProperty] private string _captionsFormat = "none";
    [ObservableProperty] private string _retakeSensitivity = "aggressive";
    [ObservableProperty] private bool _backupOriginal = true;
    [ObservableProperty] private int _maxParallel = 2; // clean up to N files at once

    // Speech model: a catalog id (base.en / large-v3-turbo) or a user-supplied .bin path.
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectedModel))]
    private string _selectedModelId = "base.en";

    /// Use Crisp's Wren filler model instead of whisper for filler detection. Wren has
    /// no transcript, so enabling it clears captions and the UI disables retakes +
    /// captions while it's on (macOS parity: SettingsView fillerEnabledBinding).
    [ObservableProperty] private bool _fillerModelEnabled;
    partial void OnFillerModelEnabledChanged(bool value)
    {
        if (_loading) return;
        FileLog.Info("filler-model", value ? "Wren enabled for filler detection" : "Wren disabled — back to whisper");
        if (value && CaptionsFormat != "none") CaptionsFormat = "none"; // no transcript to caption from
    }
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasCustomModel), nameof(CustomModelName))]
    private string _customModelPath = "";
    [ObservableProperty] private bool _exportToEditor; // FCPXML timeline instead of a render
    [ObservableProperty] private bool _splitTracks; // also write separate video + audio
    [ObservableProperty] private string _splitAudioFormat = "match";
    public string[] SplitAudioFormats { get; } = { "match", "wav" };
    [ObservableProperty] private bool _watchEnabled;
    [ObservableProperty] private string _watchFolderPath = "";

    // Presets: named recipes a queue row can pick; DefaultPresetId is the one new files
    // start on. Shared shape + keys with macOS, so a preset created on either round-trips.
    public ObservableCollection<Preset> Presets { get; } = new();
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DefaultPreset), nameof(DefaultPresetName))]
    private string _defaultPresetId = "";

    public Preset? DefaultPreset => PresetById(DefaultPresetId);
    public string DefaultPresetName => DefaultPreset?.Name ?? "Global recipe";
    public Preset? PresetById(string? id) =>
        string.IsNullOrEmpty(id) ? null : Presets.FirstOrDefault(p => p.Id == id);

    /// Snapshot the current global recipe into a new preset under `name`.
    public Preset AddPreset(string name, Strength strength)
    {
        var p = new Preset
        {
            Name = name,
            Strength = Strengths.RawValue(strength),
            PauseThreshold = PauseThreshold, SilenceFloorDB = SilenceFloorDB,
            BreathingRoom = BreathingRoom, MinKeep = MinKeep,
            VideoCodec = VideoCodec, HardwareEncoding = HardwareEncoding, VideoQuality = VideoQuality,
            AudioCodec = AudioCodec, AudioBitrateKbps = AudioBitrateKbps,
            OutputContainer = OutputContainer, ColorDepth = ColorDepth, BackupOriginal = BackupOriginal,
        };
        Presets.Add(p);
        Save();
        return p;
    }

    public void RenamePreset(string id, string name)
    {
        var p = PresetById(id);
        if (p is null) return;
        p.Name = name;
        Save();
    }

    public void DeletePreset(string id)
    {
        var p = PresetById(id);
        if (p is null) return;
        Presets.Remove(p);
        if (DefaultPresetId == id) DefaultPresetId = ""; // triggers Save via OnPropertyChanged
        else Save();
    }

    public void SetDefaultPreset(string? id) => DefaultPresetId = id ?? "";

    /// Digest the engine's hardware probe: update the Settings blurb and — once ever,
    /// tracked by a marker file — steer the factory-default codec to one this machine's
    /// GPU actually accelerates. Only ever hevc → h264 (never a silent upgrade the other
    /// way), only while hardware encoding is on, and never again after the first probe,
    /// so a deliberate later choice of HEVC sticks.
    public void ApplyHardwareProbe(HardwareInfo info)
    {
        LastHardwareInfo = info;
        HardwareStatus = HardwareStatusText(info);

        // When settings.json couldn't be read this session, the codec flip couldn't
        // persist — don't burn the once-ever marker on a launch that can't apply it.
        if (!_canSave) return;
        var marker = System.IO.Path.Combine(Channels.ConfigDirectory, ".gpu-defaults-applied");
        if (System.IO.File.Exists(marker)) return;
        try
        {
            System.IO.Directory.CreateDirectory(Channels.ConfigDirectory);
            System.IO.File.WriteAllText(marker, string.Join(", ", info.Gpus));
        }
        catch { return; } // can't record "done once" → skip the adjust rather than repeat it every launch

        if (HardwareEncoding && VideoCodec == "hevc" && !info.Accelerates("hevc") && info.Accelerates("h264"))
        {
            VideoCodec = "h264";
            FileLog.Info("gpu", $"default codec hevc → h264 — this GPU hardware-encodes H.264 only ({info.H264Encoder})");
        }
    }

    /// The accelerate-verdict sentence, GPU names excluded — shared by the Settings
    /// blurb and the onboarding hardware step (one system, not two).
    internal static string HardwareVerdictText(HardwareInfo info)
    {
        var (h264, hevc) = (info.H264Encoder, info.HevcEncoder);
        if (h264 is null && hevc is null)
            return "no working hardware encoder; encoding uses the CPU.";
        if (h264 is not null && hevc is not null)
            return $"hardware H.264 + HEVC via {HardwareInfo.VendorLabel(hevc)}.";
        return h264 is not null
            ? $"hardware H.264 via {HardwareInfo.VendorLabel(h264)}; HEVC encodes on the CPU."
            : $"hardware HEVC via {HardwareInfo.VendorLabel(hevc!)}; H.264 encodes on the CPU.";
    }

    private static string HardwareStatusText(HardwareInfo info)
    {
        var gpu = info.Gpus.Count > 0 ? string.Join(", ", info.Gpus) : "No GPU detected";
        return $"{gpu} — {HardwareVerdictText(info)}";
    }

    /// Explorer right-click "Clean with Crisp" — lives in the registry, not settings.json.
    public bool ExplorerIntegration
    {
        get => ShellIntegration.IsInstalled();
        set { if (value) ShellIntegration.Install(); else ShellIntegration.Uninstall(); OnPropertyChanged(); }
    }

    public IReadOnlyList<ModelSpec> ModelOptions => ModelCatalog.All;
    public ModelSpec SelectedModel
    {
        get => ModelCatalog.Spec(SelectedModelId);
        set { if (value is not null) SelectedModelId = value.Id; }
    }
    public bool HasCustomModel => !string.IsNullOrWhiteSpace(CustomModelPath) && System.IO.File.Exists(CustomModelPath);
    public string CustomModelName => HasCustomModel ? System.IO.Path.GetFileName(CustomModelPath) : "";

    /// Whether the Wren inference helper exists on this machine (Settings binds the
    /// toggle's enablement + description to this).
    public bool FillerHelperAvailable => FillerHelper.Available;
    public string WrenDescription => FillerHelperAvailable
        ? "Crisp's own filler model — much faster than Whisper. Repeated takes and captions turn off while it's on."
        : "Crisp's own filler model — coming to Windows soon (already available on macOS).";

    /// True when the user arrived with a saved settings.json (from a previous install or
    /// the macOS app on a shared home) — the tour greets them back and edits it in place.
    /// Captured before anything is written this session.
    public bool HasExistingConfig { get; }

    /// Bounded parallelism for a batch clean (1–4), so heavy ffmpeg/whisper runs don't
    /// thrash a machine. Mirrors the Mac's manualConcurrency (the full ResourceGovernor
    /// auto/ultra modes aren't ported).
    public int Concurrency => System.Math.Clamp(MaxParallel, 1, 4);

    // Choices for the Settings pickers.
    public string[] VideoCodecs { get; } = { "h264", "hevc" };
    public string[] Qualities { get; } = { "maximum", "high", "balanced", "smaller" };
    public string[] AudioCodecs { get; } = { "aac", "opus" };
    public string[] Containers { get; } = { "auto", "mp4", "mkv", "mov", "m4v", "ts", "webm" };
    public string[] ColorDepths { get; } = { "auto", "8", "10" };
    public string[] FrameRateModes { get; } = { "auto", "passthrough", "constant" };
    public string[] CaptionFormats { get; } = { "none", "srt", "vtt", "both" };
    public string[] RetakeSensitivities { get; } = { "gentle", "balanced", "aggressive" };

    private readonly EngineConfig _config;
    private readonly bool _canSave;
    private bool _loading = true;

    public EngineSettings()
    {
        HasExistingConfig = System.IO.File.Exists(EngineConfig.FilePath);
        _config = EngineConfig.Load();
        _canSave = !_config.LoadFailed; // a present-but-unreadable file must not be clobbered
        PauseThreshold = _config.PauseThreshold;
        SilenceFloorDB = _config.SilenceFloorDB;
        BreathingRoom = _config.BreathingRoom;
        MinKeep = _config.MinKeep;
        FadeMs = _config.FadeMs;
        CrossfadeMs = _config.CrossfadeMs;
        SnapMs = _config.SnapMs;
        VideoCodec = _config.VideoCodec;
        HardwareEncoding = _config.HardwareEncoding;
        VideoQuality = _config.VideoQuality;
        AudioCodec = _config.AudioCodec;
        AudioBitrateKbps = _config.AudioBitrateKbps;
        OutputContainer = _config.OutputContainer;
        ColorDepth = _config.ColorDepth;
        FrameRateMode = _config.FrameRateMode;
        FrameRateValue = _config.FrameRateValue;
        CaptionsFormat = _config.CaptionsFormat;
        RetakeSensitivity = _config.RetakeSensitivity;
        BackupOriginal = _config.BackupOriginal;
        MaxParallel = _config.ManualConcurrency;
        SelectedModelId = _config.SelectedModelId;
        FillerModelEnabled = _config.FillerModelEnabled;
        CustomModelPath = _config.CustomModelPath;
        ExportToEditor = _config.ExportToEditor;
        SplitTracks = _config.SplitTracks;
        SplitAudioFormat = _config.SplitAudioFormat;
        WatchEnabled = _config.WatchEnabled;
        WatchFolderPath = _config.WatchFolderPath;
        foreach (var p in _config.Presets) Presets.Add(p);
        DefaultPresetId = _config.DefaultPresetId;
        _loading = false;
    }

    /// Write the current state to settings.json unconditionally. Normally every
    /// property change auto-saves, but a user who accepts the defaults never changes
    /// one — finishing onboarding calls this so the chosen setup (model selection
    /// included) always exists on disk.
    public void SaveNow() => Save();

    protected override void OnPropertyChanged(PropertyChangedEventArgs e)
    {
        base.OnPropertyChanged(e);
        if (_loading) return;
        if (e.PropertyName is nameof(HardwareStatus) or nameof(LastHardwareInfo)) return; // display-only, never persisted
        if (e.PropertyName == nameof(CustomModelPath))
            FileLog.Info("model", string.IsNullOrWhiteSpace(CustomModelPath)
                ? "custom model cleared — back to the catalog model"
                : $"custom model set → {CustomModelPath}");
        Save();
    }

    private void Save()
    {
        if (!_canSave) return;
        _config.PauseThreshold = PauseThreshold;
        _config.SilenceFloorDB = SilenceFloorDB;
        _config.BreathingRoom = BreathingRoom;
        _config.MinKeep = MinKeep;
        _config.FadeMs = FadeMs;
        _config.CrossfadeMs = CrossfadeMs;
        _config.SnapMs = SnapMs;
        _config.VideoCodec = VideoCodec;
        _config.HardwareEncoding = HardwareEncoding;
        _config.VideoQuality = VideoQuality;
        _config.AudioCodec = AudioCodec;
        _config.AudioBitrateKbps = AudioBitrateKbps;
        _config.OutputContainer = OutputContainer;
        _config.ColorDepth = ColorDepth;
        _config.FrameRateMode = FrameRateMode;
        _config.FrameRateValue = FrameRateValue;
        _config.CaptionsFormat = CaptionsFormat;
        _config.RetakeSensitivity = RetakeSensitivity;
        _config.BackupOriginal = BackupOriginal;
        _config.ManualConcurrency = MaxParallel;
        _config.SelectedModelId = SelectedModelId;
        _config.FillerModelEnabled = FillerModelEnabled;
        _config.CustomModelPath = CustomModelPath;
        _config.ExportToEditor = ExportToEditor;
        _config.SplitTracks = SplitTracks;
        _config.SplitAudioFormat = SplitAudioFormat;
        _config.WatchEnabled = WatchEnabled;
        _config.WatchFolderPath = WatchFolderPath;
        _config.Presets = Presets.ToList();
        _config.DefaultPresetId = DefaultPresetId;
        _config.Save();
    }

    private static string F(double d) => d.ToString("0.###", CultureInfo.InvariantCulture);

    /// The per-clean recipe (cutting + smoothing + encoding + backup + captions). The
    /// caller appends filler/retake/model flags. Cutting uses the strength preset, or
    /// the saved knobs for the Custom strength (mirrors Strength.parameters(using:)).
    ///
    /// When `preset` is non-null the cut + encode + container + colour-depth + backup
    /// knobs come from the preset (a named per-row recipe); smoothing, fps, captions,
    /// split and editor-handoff stay global output modes.
    public IReadOnlyList<string> RecipeArgs(Models.Strength strength, Models.Preset? preset = null)
    {
        var a = new List<string>();
        var eff = preset is null ? strength : Models.Strengths.Parse(preset.Strength);

        if (eff == Models.Strength.Custom)
        {
            a.Add("--pause"); a.Add(F(preset?.PauseThreshold ?? PauseThreshold));
            a.Add("--keep-pause"); a.Add(F(preset?.BreathingRoom ?? BreathingRoom));
        }
        else
        {
            var p = Models.Strengths.Of(eff);
            a.Add("--pause"); a.Add(F(p.Pause));
            a.Add("--keep-pause"); a.Add(F(p.KeepPause));
        }
        a.Add("--noise"); a.Add(F(preset?.SilenceFloorDB ?? SilenceFloorDB));
        a.Add("--min-keep"); a.Add(F(preset?.MinKeep ?? MinKeep));
        a.Add("--fade-ms"); a.Add(F(FadeMs));
        a.Add("--crossfade-ms"); a.Add(F(CrossfadeMs));
        a.Add("--snap-ms"); a.Add(F(SnapMs));

        a.Add("--video-codec"); a.Add(preset?.VideoCodec ?? VideoCodec);
        if (preset?.HardwareEncoding ?? HardwareEncoding) a.Add("--hardware");
        a.Add("--quality"); a.Add(preset?.VideoQuality ?? VideoQuality);
        a.Add("--audio-codec"); a.Add(preset?.AudioCodec ?? AudioCodec);
        a.Add("--audio-bitrate"); a.Add((preset?.AudioBitrateKbps ?? AudioBitrateKbps).ToString(CultureInfo.InvariantCulture));
        a.Add("--container"); a.Add(preset?.OutputContainer ?? OutputContainer);
        a.Add("--color-depth"); a.Add(preset?.ColorDepth ?? ColorDepth);
        a.Add("--fps-mode"); a.Add(FrameRateMode);
        if (FrameRateMode == "constant" && FrameRateValue > 0)
        {
            a.Add("--fps"); a.Add(F(FrameRateValue));
        }

        if (CaptionsFormat != "none") { a.Add("--captions"); a.Add(CaptionsFormat); }
        if (ExportToEditor) { a.Add("--export-timeline"); a.Add("fcpxml"); } // editor handoff, no render
        if (SplitTracks) { a.Add("--split"); a.Add("--split-audio"); a.Add(SplitAudioFormat); }

        if (preset?.BackupOriginal ?? BackupOriginal)
        {
            // Collect originals in a dated folder under the data home — not scattered in
            // an _originals/ folder beside each source (CLAUDE.md product philosophy #2).
            var dated = System.IO.Path.Combine(
                Crisp.Channels.OriginalsDirectory,
                System.DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
            a.Add("--backup-dir"); a.Add(dated);
        }
        else
        {
            a.Add("--no-backup");
        }

        return a;
    }
}
