using System;
using System.Diagnostics;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;

namespace Crisp.Services;

public enum UpdaterState { Idle, Checking, UpToDate, Available, Failed }

/// Channel-aware GitHub-release updater — the Windows counterpart of macOS
/// Services/Updates/Updater.swift. Authenticates to the private repo via `gh auth
/// token` (same as the Mac); checks the latest (pre)release, compares versions, and
/// surfaces an "update available" banner. Installing the .msi/.exe is a packaging
/// follow-up — for now "Download" opens the release page.
public partial class Updater : ObservableObject
{
    private const string Repository = "rafay99-epic/Crisp";
    private static readonly HttpClient Http = new();

    [ObservableProperty] private UpdaterState _state = UpdaterState.Idle;
    [ObservableProperty] private string _availableVersion = "";
    [ObservableProperty] private string _releaseUrl = "";
    [ObservableProperty] private string _notes = "";
    [ObservableProperty] private string _message = "";

    public bool IsAvailable => State == UpdaterState.Available;

    partial void OnStateChanged(UpdaterState value) => OnPropertyChanged(nameof(IsAvailable));

    public async Task CheckAsync()
    {
        if (State == UpdaterState.Checking) return;
        // Dev builds have no updater — rebuild to change them (mirrors macOS Channel.dev).
        if (!Channels.Current.UpdatesEnabled()) { State = UpdaterState.UpToDate; return; }
        State = UpdaterState.Checking;
        try
        {
            // Stable tracks the latest full release; Nightly tracks the newest pre-release.
            // 404-with-no-token means the private repo isn't visible.
            JsonElement root;
            if (Channels.Current.IsPrerelease())
            {
                var listJson = await GetAsync($"https://api.github.com/repos/{Repository}/releases?per_page=20");
                if (listJson is null) { State = UpdaterState.UpToDate; return; }
                using var listDoc = JsonDocument.Parse(listJson);
                var prerelease = FirstPrerelease(listDoc.RootElement);
                if (prerelease is null) { State = UpdaterState.UpToDate; return; }
                root = prerelease.Value.Clone(); // survive listDoc disposal
            }
            else
            {
                var json = await GetAsync($"https://api.github.com/repos/{Repository}/releases/latest");
                if (json is null) { State = UpdaterState.UpToDate; return; }
                using var doc = JsonDocument.Parse(json);
                root = doc.RootElement.Clone();
            }

            var tag = root.GetProperty("tag_name").GetString() ?? "";
            var version = tag.StartsWith('v') ? tag[1..] : tag;
            ReleaseUrl = AssetUrl(root) ?? (root.TryGetProperty("html_url", out var h) ? h.GetString() ?? "" : "");
            Notes = (root.TryGetProperty("body", out var b) ? b.GetString() : null)?.Trim() ?? "";

            if (IsNewer(version, CrispVersion.Current))
            {
                AvailableVersion = version;
                State = UpdaterState.Available;
            }
            else
            {
                State = UpdaterState.UpToDate;
            }
        }
        catch (Exception ex)
        {
            Message = ex.Message;
            State = UpdaterState.Failed;
        }
    }

    /// v1: open the installer / release page in the browser. Silent .msi/.exe install
    /// arrives with the packaging iteration.
    public void OpenDownload()
    {
        if (string.IsNullOrEmpty(ReleaseUrl)) return;
        try { Process.Start(new ProcessStartInfo(ReleaseUrl) { UseShellExecute = true }); }
        catch { /* best effort */ }
    }

    /// The Windows installer asset on the release, if one is published yet.
    /// The newest pre-release in a /releases list (nightly feed), skipping drafts and
    /// full releases. The list is already newest-first.
    private static JsonElement? FirstPrerelease(JsonElement releases)
    {
        if (releases.ValueKind != JsonValueKind.Array) return null;
        foreach (var r in releases.EnumerateArray())
        {
            var draft = r.TryGetProperty("draft", out var d) && d.GetBoolean();
            var pre = r.TryGetProperty("prerelease", out var p) && p.GetBoolean();
            if (!draft && pre) return r;
        }
        return null;
    }

    private static string? AssetUrl(JsonElement release)
    {
        if (!release.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array)
            return null;
        foreach (var a in assets.EnumerateArray())
        {
            var name = a.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
            if (name.EndsWith(".msi", StringComparison.OrdinalIgnoreCase)
                || name.EndsWith(".msix", StringComparison.OrdinalIgnoreCase)
                || name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                return a.TryGetProperty("browser_download_url", out var u) ? u.GetString() : null;
        }
        return null;
    }

    private static async Task<string?> GetAsync(string url)
    {
        var token = GithubToken();
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        req.Headers.UserAgent.ParseAdd("Crisp-Windows");
        if (token is not null) req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        using var resp = await Http.SendAsync(req);
        if (resp.StatusCode == System.Net.HttpStatusCode.OK)
            return await resp.Content.ReadAsStringAsync();
        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound && token is null)
            throw new Exception("Can't see the private repository. Install GitHub CLI and run \"gh auth login\".");
        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound)
            return null; // no releases yet
        throw new Exception($"GitHub returned HTTP {(int)resp.StatusCode}.");
    }

    /// Numeric, component-wise version compare (port of macOS isVersion(_:newerThan:)).
    public static bool IsNewer(string candidate, string current)
    {
        static int[] Parts(string v) => v.Split('.')
            .Select(s => int.TryParse(new string(s.TakeWhile(char.IsDigit).ToArray()), out var n) ? n : 0)
            .ToArray();
        int[] a = Parts(candidate), b = Parts(current);
        for (var i = 0; i < Math.Max(a.Length, b.Length); i++)
        {
            int lhs = i < a.Length ? a[i] : 0, rhs = i < b.Length ? b[i] : 0;
            if (lhs != rhs) return lhs > rhs;
        }
        return false;
    }

    /// `gh auth token` for the private repo (same as the Mac). Returns null if gh
    /// isn't installed/authed — the check then degrades to anonymous (public releases).
    private static string? GithubToken()
    {
        foreach (var gh in new[] { "gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh" })
        {
            try
            {
                using var p = Process.Start(new ProcessStartInfo(gh, "auth token")
                {
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                });
                if (p is null) continue;
                // Drain both streams async (so a full stderr pipe can't stall the child) and
                // actually enforce the 10s bound — ReadToEnd() alone ignores WaitForExit's timeout.
                var stdoutTask = p.StandardOutput.ReadToEndAsync();
                var stderrTask = p.StandardError.ReadToEndAsync();
                if (!p.WaitForExit(10_000)) { try { p.Kill(true); } catch { /* ignore */ } continue; }
                var token = stdoutTask.GetAwaiter().GetResult().Trim();
                _ = stderrTask.GetAwaiter().GetResult();
                if (p.ExitCode == 0 && token.Length > 0) return token;
            }
            catch { /* try next candidate */ }
        }
        return null;
    }
}
