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
                var prerelease = FirstWindowsPrerelease(listDoc.RootElement);
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

            bool newer;
            string shown;
            if (Channels.Current.IsPrerelease())
            {
                // Nightly reuses a fixed rolling tag ("nightly"), so the version string can't
                // order builds — parse the monotonic build number from the title (mirrors the
                // macOS `build (\d+)` rule). If either build number is unknown, don't claim an
                // update (no false positive on a mislabeled/dev build).
                var title = root.TryGetProperty("name", out var nm) ? nm.GetString() ?? "" : "";
                var theirs = ParseBuildNumber(title);
                var ours = CrispVersion.BuildNumber;
                newer = theirs > 0 && ours > 0 && theirs > ours;
                shown = theirs > 0 ? $"build {theirs}" : version;
            }
            else
            {
                newer = IsNewer(version, CrispVersion.Current);
                shown = version;
            }

            if (newer)
            {
                AvailableVersion = shown;
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
        // UseShellExecute would hand any string to the OS handler, so only ever launch a
        // real http(s) URL (defence-in-depth — the URL comes from the GitHub API response).
        if (!Uri.TryCreate(ReleaseUrl, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)) return;
        try { Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true }); }
        catch { /* best effort */ }
    }

    /// The Windows installer asset on the release, if one is published yet.
    /// The build number embedded in a nightly release title ("… build 123 …"), or 0.
    /// Mirrors the macOS updater's `build (\d+)` parse so the two channels agree on order.
    private static int ParseBuildNumber(string title)
    {
        var m = System.Text.RegularExpressions.Regex.Match(title, @"build (\d+)",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return m.Success && int.TryParse(m.Groups[1].Value, out var n) ? n : 0;
    }

    /// The newest pre-release in a /releases list that actually carries a Windows
    /// installer (.exe/.msi). The list is already newest-first. Asset-filtering
    /// matters because the macOS nightly build ships its own rolling pre-release
    /// (Crisp-Nightly.dmg only, tag `nightly`) alongside ours (`nightly-win`); we
    /// must skip it — exactly as the macOS updater skips a release lacking its DMG.
    private static JsonElement? FirstWindowsPrerelease(JsonElement releases)
    {
        if (releases.ValueKind != JsonValueKind.Array) return null;
        foreach (var r in releases.EnumerateArray())
        {
            var draft = r.TryGetProperty("draft", out var d) && d.GetBoolean();
            var pre = r.TryGetProperty("prerelease", out var p) && p.GetBoolean();
            if (!draft && pre && AssetUrl(r) is not null) return r;
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
        var token = await GithubTokenAsync();
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
    private static async Task<string?> GithubTokenAsync()
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
                // Fully async + time-bound: drain both streams (a full stderr pipe can't stall
                // the child) and bound the wait to 10s without blocking a thread.
                var stdoutTask = p.StandardOutput.ReadToEndAsync();
                var stderrTask = p.StandardError.ReadToEndAsync();
                using var cts = new System.Threading.CancellationTokenSource(10_000);
                try { await p.WaitForExitAsync(cts.Token); }
                catch (OperationCanceledException) { try { p.Kill(true); } catch { /* ignore */ } continue; }
                var token = (await stdoutTask).Trim();
                _ = await stderrTask;
                if (p.ExitCode == 0 && token.Length > 0) return token;
            }
            catch { /* try next candidate */ }
        }
        return null;
    }
}
