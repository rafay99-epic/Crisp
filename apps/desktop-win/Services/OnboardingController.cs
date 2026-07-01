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
public enum OnboardingStep { Welcome, Capabilities, Fidelity, HowItWorks, Model, Preferences, Automate, Done }

/// One page-indicator dot in the tour footer.
public sealed partial class OnboardingDot : ObservableObject
{
    [ObservableProperty] private bool _isCurrent;
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
    private readonly EngineSettings _settings;

    [ObservableProperty] private bool _isPresented;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Step), nameof(IsLast), nameof(ShowsBack), nameof(ContinueLabel),
        nameof(CanContinue), nameof(IsWelcome), nameof(IsCapabilities), nameof(IsFidelity),
        nameof(IsHowItWorks), nameof(IsModel), nameof(IsPreferences), nameof(IsAutomate), nameof(IsDone))]
    [NotifyCanExecuteChangedFor(nameof(ContinueCommand))]
    private int _stepIndex;

    public ObservableCollection<OnboardingDot> Dots { get; } =
        new(Steps.Select(_ => new OnboardingDot()));

    public OnboardingController(ModelStore models, EngineSettings settings)
    {
        _models = models;
        _settings = settings;
        IsPresented = !File.Exists(MarkerPath);
        Dots[0].IsCurrent = true;

        // The model gate reacts live: finishing a download (or picking a custom .bin)
        // enables Continue on the model step without any refresh action.
        _models.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(ModelStore.State) or nameof(ModelStore.IsReady)) RefreshGate();
        };
        _settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(EngineSettings.CustomModelPath)) RefreshGate();
            if (e.PropertyName == nameof(EngineSettings.SelectedModelId))
            {
                OnPropertyChanged(nameof(IsBaseSelected));
                OnPropertyChanged(nameof(IsTurboSelected));
            }
        };
    }

    // The model step's option cards. The catalog is fixed at two (matching macOS), so
    // the cards bind statically; a custom .bin is the third, browse-your-own option.
    public ModelSpec BaseSpec => ModelCatalog.Base;
    public ModelSpec TurboSpec => ModelCatalog.Turbo;
    public bool IsBaseSelected
    {
        get => _settings.SelectedModelId == ModelCatalog.Base.Id;
        set { if (value) _settings.SelectedModelId = ModelCatalog.Base.Id; }
    }
    public bool IsTurboSelected
    {
        get => _settings.SelectedModelId == ModelCatalog.Turbo.Id;
        set { if (value) _settings.SelectedModelId = ModelCatalog.Turbo.Id; }
    }

    public OnboardingStep Step => Steps[Math.Clamp(StepIndex, 0, Steps.Length - 1)];
    public bool IsLast => StepIndex == Steps.Length - 1;
    public bool ShowsBack => StepIndex > 0; // page 1 offers Skip instead
    public string ContinueLabel => IsLast ? "Get Started" : "Continue";

    // Step visibility for the view (one page shown at a time).
    public bool IsWelcome => Step == OnboardingStep.Welcome;
    public bool IsCapabilities => Step == OnboardingStep.Capabilities;
    public bool IsFidelity => Step == OnboardingStep.Fidelity;
    public bool IsHowItWorks => Step == OnboardingStep.HowItWorks;
    public bool IsModel => Step == OnboardingStep.Model;
    public bool IsPreferences => Step == OnboardingStep.Preferences;
    public bool IsAutomate => Step == OnboardingStep.Automate;
    public bool IsDone => Step == OnboardingStep.Done;

    /// A returning user (settings.json already existed) gets a "welcome back" tour —
    /// their saved configuration is preserved and the preferences step edits it in place.
    public string WelcomeTitle => _settings.HasExistingConfig ? "Welcome back to Crisp" : "Welcome to Crisp";
    public string WelcomeSubtitle => _settings.HasExistingConfig
        ? "Your saved settings are preserved — nothing has changed. Here's a quick tour of how everything works."
        : "Crisp tightens up your screen recordings and talking-head videos — automatically cutting out long pauses and filler words for clean, snappy jump-cuts, plus repeated takes when you use the Whisper speech model.";

    /// The model step is satisfied by an installed catalog model or a custom .bin.
    public bool ModelSatisfied => _models.IsReady || _settings.HasCustomModel;

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
        else StepIndex++;
    }

    [RelayCommand]
    private void Back()
    {
        if (StepIndex > 0) StepIndex--;
    }

    /// "Skip" routes through the unsatisfied mandatory step (the speech model) rather
    /// than exiting; it only finishes when the gate is clear. Same logic as macOS.
    [RelayCommand]
    private void Skip()
    {
        if (!ModelSatisfied) StepIndex = Array.IndexOf(Steps, OnboardingStep.Model);
        else Complete();
    }

    /// Re-open the tour (Settings ▸ About ▸ Welcome Tour — the Help-menu equivalent).
    public void Present()
    {
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
        IsPresented = false;
    }
}
