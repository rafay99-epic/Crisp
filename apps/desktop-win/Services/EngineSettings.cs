using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
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
    [ObservableProperty] private string _videoQuality = "high";
    [ObservableProperty] private string _audioCodec = "aac";
    [ObservableProperty] private int _audioBitrateKbps = 192;
    [ObservableProperty] private string _outputContainer = "auto";
    [ObservableProperty] private string _colorDepth = "auto";
    [ObservableProperty] private string _frameRateMode = "auto";
    [ObservableProperty] private double _frameRateValue;
    [ObservableProperty] private string _captionsFormat = "none";
    [ObservableProperty] private string _retakeSensitivity = "aggressive";
    [ObservableProperty] private bool _backupOriginal = true;

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
        _loading = false;
    }

    protected override void OnPropertyChanged(PropertyChangedEventArgs e)
    {
        base.OnPropertyChanged(e);
        if (!_loading) Save();
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
        _config.Save();
    }

    private static string F(double d) => d.ToString("0.###", CultureInfo.InvariantCulture);

    /// The per-clean recipe (cutting + smoothing + encoding + backup + captions). The
    /// caller appends filler/retake/model flags. Cutting uses the strength preset, or
    /// the saved knobs for the Custom strength (mirrors Strength.parameters(using:)).
    public IReadOnlyList<string> RecipeArgs(Models.Strength strength)
    {
        var a = new List<string>();

        if (strength == Models.Strength.Custom)
        {
            a.Add("--pause"); a.Add(F(PauseThreshold));
            a.Add("--keep-pause"); a.Add(F(BreathingRoom));
        }
        else
        {
            var p = Models.Strengths.Of(strength);
            a.Add("--pause"); a.Add(F(p.Pause));
            a.Add("--keep-pause"); a.Add(F(p.KeepPause));
        }
        a.Add("--noise"); a.Add(F(SilenceFloorDB));
        a.Add("--min-keep"); a.Add(F(MinKeep));
        a.Add("--fade-ms"); a.Add(F(FadeMs));
        a.Add("--crossfade-ms"); a.Add(F(CrossfadeMs));
        a.Add("--snap-ms"); a.Add(F(SnapMs));

        a.Add("--video-codec"); a.Add(VideoCodec);
        if (HardwareEncoding) a.Add("--hardware");
        a.Add("--quality"); a.Add(VideoQuality);
        a.Add("--audio-codec"); a.Add(AudioCodec);
        a.Add("--audio-bitrate"); a.Add(AudioBitrateKbps.ToString(CultureInfo.InvariantCulture));
        a.Add("--container"); a.Add(OutputContainer);
        a.Add("--color-depth"); a.Add(ColorDepth);
        a.Add("--fps-mode"); a.Add(FrameRateMode);
        if (FrameRateMode == "constant" && FrameRateValue > 0)
        {
            a.Add("--fps"); a.Add(F(FrameRateValue));
        }

        if (CaptionsFormat != "none") { a.Add("--captions"); a.Add(CaptionsFormat); }

        if (BackupOriginal)
        {
            // Collect originals in a dated folder under the data home — not scattered in
            // an _originals/ folder beside each source (CLAUDE.md product philosophy #2).
            var dated = System.IO.Path.Combine(
                System.Environment.GetFolderPath(System.Environment.SpecialFolder.UserProfile),
                ".crisp", "Originals", System.DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
            a.Add("--backup-dir"); a.Add(dated);
        }
        else
        {
            a.Add("--no-backup");
        }

        return a;
    }
}
