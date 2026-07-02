using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Crisp.Models;

namespace Crisp.Services;

/// The pages of the first-run tour, in order. Windows counterpart of the macOS
/// OnboardingView.Step (minus the Apple-only licensing step, which ships dark there).
public enum OnboardingStep { Welcome, Capabilities, Fidelity, Hardware, HowItWorks, Model, Preferences, Automate, Done }

/// One page-indicator dot in the tour footer.
public sealed partial class OnboardingDot : ObservableObject
{
    [ObservableProperty] private bool _isCurrent;
    [ObservableProperty] private bool _isShown = true;
}

/// First-run tour (port of the macOS OnboardingController + OnboardingView flow logic).
/// Owns the whole window on first launch until finished once; a marker file in the data
/// home records that, so it never reappears (per channel, like the Mac's per-bundle-id
/// UserDefaults). Derived from disk at construction. The speech-model step is a hard
/// gate: the tour can't be completed until a catalog model is installed or a custom
/// .bin is set — "Skip" routes there instead of exiting, exactly like macOS.
public partial class OnboardingController : ObservableObject
{
    private static string MarkerPath => Path.Combine(Channels.DataDirectory, ".onboarded");

    public static readonly OnboardingStep[] Steps = Enum.GetValues<OnboardingStep>();

    private readonly ModelStore _models;
    private readonly ModelStore _filler;
    private readonly EngineSettings _settings;
    private readonly bool _fillerAvailable;

    [ObservableProperty] private bool _isPresented;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Step), nameof(IsLast), nameof(ShowsBack), nameof(ContinueLabel),
        nameof(CanContinue), nameof(IsWelcome), nameof(IsCapabilities), nameof(IsFidelity),
        nameof(IsHardware), nameof(IsHowItWorks), nameof(IsModel), nameof(IsPreferences), nameof(IsAutomate), nameof(IsDone))]
    [NotifyCanExecuteChangedFor(nameof(ContinueCommand))]
    private int _stepIndex;

    public ObservableCollection<OnboardingDot> Dots { get; } =
        new(Steps.Select(_ => new OnboardingDot()));

    public OnboardingController(ModelStore models, ModelStore fillerModel, EngineSettings settings, bool fillerAvailable)
    {
        _models = models;
        _filler = fillerModel;
        _settings = settings;
        _fillerAvailable = fillerAvailable;
        IsPresented = !File.Exists(MarkerPath);
        Dots[0].IsCurrent = true;
        Dots[Array.IndexOf(Steps, OnboardingStep.Hardware)].IsShown = ShowsHardwareStep; // false pre-probe
        if (IsPresented) FileLog.Info("onboarding", "first run — presenting the tour");

        // The model gate reacts live: finishing a download (whisper or Wren) enables
        // Continue on the model step without any refresh action.
        _models.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(ModelStore.State) or nameof(ModelStore.IsReady)) RefreshGate();
        };
        _filler.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(ModelStore.State) or nameof(ModelStore.IsReady)) RefreshGate();
        };
        _settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(EngineSettings.CustomModelPath)
                or nameof(EngineSettings.FillerModelEnabled)) RefreshGate();
            if (e.PropertyName is nameof(EngineSettings.SelectedModelId)
                or nameof(EngineSettings.FillerModelEnabled))
                RefreshSelection();
            if (e.PropertyName == nameof(EngineSettings.LastHardwareInfo))
            {
                OnPropertyChanged(nameof(ShowsHardwareStep));
                OnPropertyChanged(nameof(GpuNames));
                OnPropertyChanged(nameof(GpuVerdict));
                Dots[Array.IndexOf(Steps, OnboardingStep.Hardware)].IsShown = ShowsHardwareStep;
            }
        };
    }

    // The model step's option cards: the two whisper models plus Wren, Crisp's own
    // filler model (selecting it flips the shared fillerModelEnabled key — same
    // semantics as the macOS Settings toggle).
    public ModelSpec BaseSpec => ModelCatalog.Base;
    public ModelSpec TurboSpec => ModelCatalog.Turbo;
    public ModelSpec WrenSpec => FillerModelCatalog.Wren;
    /// Wren needs the crisp-filler inference helper; until Windows bundles one the
    /// card shows as "coming soon" and can't be picked.
    public bool WrenAvailable => _fillerAvailable;
    public bool IsBaseSelected
    {
        get => !_settings.FillerModelEnabled && _settings.SelectedModelId == ModelCatalog.Base.Id;
        set { if (value) { _settings.FillerModelEnabled = false; _settings.SelectedModelId = ModelCatalog.Base.Id; RefreshSelection(); } }
    }
    public bool IsTurboSelected
    {
        get => !_settings.FillerModelEnabled && _settings.SelectedModelId == ModelCatalog.Turbo.Id;
        set { if (value) { _settings.FillerModelEnabled = false; _settings.SelectedModelId = ModelCatalog.Turbo.Id; RefreshSelection(); } }
    }
    public bool IsWrenSelected
    {
        get => _settings.FillerModelEnabled;
        set { if (value && _fillerAvailable) { _settings.FillerModelEnabled = true; RefreshSelection(); } }
    }

    private void RefreshSelection()
    {
        OnPropertyChanged(nameof(IsBaseSelected));
        OnPropertyChanged(nameof(IsTurboSelected));
        OnPropertyChanged(nameof(IsWrenSelected));
    }

    public OnboardingStep Step => Steps[Math.Clamp(StepIndex, 0, Steps.Length - 1)];
    public bool IsLast => StepIndex == Steps.Length - 1;
    public bool ShowsBack => StepIndex > 0; // page 1 offers Skip instead
    public string ContinueLabel => IsLast ? "Get Started" : "Continue";

    // Step visibility for the view (one page shown at a time).
    public bool IsWelcome => Step == OnboardingStep.Welcome;
    public bool IsCapabilities => Step == OnboardingStep.Capabilities;
    public bool IsFidelity => Step == OnboardingStep.Fidelity;
    public bool IsHardware => Step == OnboardingStep.Hardware;
    public bool IsHowItWorks => Step == OnboardingStep.HowItWorks;
    public bool IsModel => Step == OnboardingStep.Model;
    public bool IsPreferences => Step == OnboardingStep.Preferences;
    public bool IsAutomate => Step == OnboardingStep.Automate;
    public bool IsDone => Step == OnboardingStep.Done;

    /// Shown only when the launch-time probe reported at least one real GPU by the
    /// time the user navigates here; otherwise the step (and its dot) is skipped.
    public bool ShowsHardwareStep => _settings.LastHardwareInfo is { Gpus.Count: > 0 };
    public string GpuNames => string.Join(", ", _settings.LastHardwareInfo?.Gpus ?? []);
    public string GpuVerdict
    {
        get
        {
            var info = _settings.LastHardwareInfo;
            if (info is null) return "";
            var text = EngineSettings.HardwareVerdictText(info);
            return text.Length > 0 ? char.ToUpperInvariant(text[0]) + text[1..] : text;
        }
    }

    /// A returning user (settings.json already existed) gets a "welcome back" tour —
    /// their saved configuration is preserved and the preferences step edits it in place.
    public string WelcomeTitle => _settings.HasExistingConfig ? "Welcome back to Crisp" : "Welcome to Crisp";
    public string WelcomeSubtitle => _settings.HasExistingConfig
        ? "Your saved settings are preserved — nothing has changed. Here's a quick tour of how everything works."
        : "Crisp tightens up your screen recordings and talking-head videos — automatically cutting out long pauses and filler words for clean, snappy jump-cuts, plus repeated takes when you use the Whisper speech model.";

    /// The model step is satisfied by whichever engine the user picked: Wren once its
    /// model is installed, else an installed whisper model or a custom .bin.
    public bool ModelSatisfied => _settings.FillerModelEnabled && _fillerAvailable
        ? _filler.IsReady
        : _models.IsReady || _settings.HasCustomModel;

    /// Mandatory gate: everything advances freely except the model step.
    public bool CanContinue => Step != OnboardingStep.Model || ModelSatisfied;

    private void RefreshGate()
    {
        OnPropertyChanged(nameof(ModelSatisfied));
        OnPropertyChanged(nameof(CanContinue));
        ContinueCommand.NotifyCanExecuteChanged();
    }

    partial void OnStepIndexChanged(int value)
    {
        for (var i = 0; i < Dots.Count; i++) Dots[i].IsCurrent = i == value;
    }

    [RelayCommand(CanExecute = nameof(CanContinue))]
    private void Continue()
    {
        if (!CanContinue) return; // ICommand.Execute doesn't check CanExecute itself
        if (IsLast) Complete();
        else
        {
            StepIndex++;
            if (Step == OnboardingStep.Hardware && !ShowsHardwareStep) StepIndex++;
        }
    }

    [RelayCommand]
    private void Back()
    {
        if (StepIndex > 0) StepIndex--;
        if (Step == OnboardingStep.Hardware && !ShowsHardwareStep && StepIndex > 0) StepIndex--;
    }

    /// "Skip" routes through the unsatisfied mandatory step (the speech model) rather
    /// than exiting; it only finishes when the gate is clear. Same logic as macOS.
    [RelayCommand]
    private void Skip()
    {
        if (!ModelSatisfied)
        {
            FileLog.Info("onboarding", "skip → routed to the model step (gate unsatisfied)");
            StepIndex = Array.IndexOf(Steps, OnboardingStep.Model);
        }
        else
        {
            FileLog.Info("onboarding", "skipped (gate already satisfied)");
            Complete();
        }
    }

    /// Re-open the tour (Settings ▸ About ▸ Welcome Tour — the Help-menu equivalent).
    public void Present()
    {
        FileLog.Info("onboarding", "re-opened from Settings");
        StepIndex = 0;
        IsPresented = true;
    }

    public void Complete()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(MarkerPath)!);
            File.WriteAllText(MarkerPath, DateTime.UtcNow.ToString("o"));
        }
        catch (IOException) { /* best effort — worst case it shows once more */ }
        if (IsPresented)
        {
            // Persist the whole chosen setup even if the user accepted every default —
            // auto-save only fires on changes, so force one write now.
            _settings.SaveNow();
            var model = _settings.FillerModelEnabled ? "wren"
                : _settings.HasCustomModel ? "custom" : _settings.SelectedModelId;
            FileLog.Info("onboarding", $"completed (model: {model}) — settings persisted");
        }
        IsPresented = false;
    }
}
