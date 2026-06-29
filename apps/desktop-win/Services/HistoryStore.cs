using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using Crisp.Models;

namespace Crisp.Services;

/// Past cleans, persisted as JSON-lines in ~/.crisp/history.jsonl (append-only; one
/// object per line) — the Windows port of macOS HistoryStore/HistoryModel.
public partial class HistoryStore : ObservableObject
{
    public ObservableCollection<HistoryEntry> Entries { get; } = new();
    public bool IsEmpty => Entries.Count == 0;

    private static string FilePath => Path.Combine(Channels.DataDirectory, "history.jsonl");

    private static readonly JsonSerializerOptions Opts = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public HistoryStore() => Reload();

    public void Reload()
    {
        Entries.Clear();
        try
        {
            if (!File.Exists(FilePath)) { OnPropertyChanged(nameof(IsEmpty)); return; }
            foreach (var line in File.ReadAllLines(FilePath))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try
                {
                    var e = JsonSerializer.Deserialize<HistoryEntry>(line, Opts);
                    if (e is not null) Entries.Insert(0, e); // newest first
                }
                catch (JsonException) { /* skip a bad line */ }
            }
        }
        catch (IOException) { /* unreadable → empty list */ }
        OnPropertyChanged(nameof(IsEmpty));
    }

    public void Record(HistoryEntry entry)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.AppendAllText(FilePath, JsonSerializer.Serialize(entry, Opts) + "\n");
            Entries.Insert(0, entry);
            OnPropertyChanged(nameof(IsEmpty));
        }
        catch (IOException) { /* best effort — a failed history write never blocks a clean */ }
    }

    public void Clear()
    {
        try { File.Delete(FilePath); } catch (IOException) { /* best effort */ }
        Entries.Clear();
        OnPropertyChanged(nameof(IsEmpty));
    }
}
