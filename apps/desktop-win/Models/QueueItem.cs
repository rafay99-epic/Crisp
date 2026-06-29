using System;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;

namespace Crisp.Models;

public enum QueueStatus { Waiting, Running, Done, Failed, Cancelled }

/// One video in the clean queue. Port of CrispCore/Models/QueueItem.swift — an
/// observable row whose status/progress/result update in place as the engine drives it.
public partial class QueueItem : ObservableObject
{
    public string Path { get; }
    public string FileName { get; }

    public QueueItem(string path)
    {
        Path = path;
        FileName = System.IO.Path.GetFileName(path);
    }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsWaiting), nameof(IsRunning), nameof(IsDone), nameof(IsFailed))]
    private QueueStatus _status = QueueStatus.Waiting;

    [ObservableProperty] private double _progress;   // 0…1, this file alone
    [ObservableProperty] private string _stage = ""; // "Rendering video… 45%"
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(KeptFraction))]
    private double _origSeconds;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(KeptFraction), nameof(SavedText))]
    private double _savedSeconds;
    [ObservableProperty] private string _cutsSummary = "";
    [ObservableProperty] private string? _outputPath;
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ErrorText))]
    private string? _error;

    public bool IsWaiting => Status == QueueStatus.Waiting;
    public bool IsRunning => Status == QueueStatus.Running;
    public bool IsDone => Status == QueueStatus.Done;
    public bool IsFailed => Status is QueueStatus.Failed or QueueStatus.Cancelled;

    /// 0…1 of the original duration that survived — drives the honest "cut" bar.
    public double KeptFraction => OrigSeconds > 0
        ? Math.Clamp((OrigSeconds - SavedSeconds) / OrigSeconds, 0, 1) : 0;

    public string SavedText => Formatting.Duration(SavedSeconds);
    public string ErrorText => Error ?? "Couldn't be cleaned";
}
