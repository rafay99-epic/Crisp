using System;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;

namespace Crisp.Services;

/// First-run welcome gate (port of the macOS OnboardingController). Presents until the
/// user finishes it once; a marker file in the data home records that, so it never
/// reappears. Derived from disk at construction, like the Mac.
public partial class OnboardingController : ObservableObject
{
    private static string MarkerPath => Path.Combine(Channels.DataDirectory, ".onboarded");

    [ObservableProperty] private bool _isPresented;

    public OnboardingController() => IsPresented = !File.Exists(MarkerPath);

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
