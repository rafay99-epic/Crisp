using System;
using System.Linq;
using System.Reflection;

namespace Crisp;

/// Build-time identity baked into the assembly by the packaging step
/// (`dotnet publish -p:CrispChannel=… -p:CrispVersion=… -p:CrispBuildNumber=…`),
/// read at runtime as the fallback when the matching CRISP_* env var isn't set —
/// i.e. a normally-launched *installed* app, which has no such env. The env still
/// wins so dev/test harnesses can override. This is the Windows analogue of the
/// macOS build baking CrispChannel/CrispVersion into Info.plist.
public static class BuildInfo
{
    private static readonly ILookup<string, string?> Meta =
        (Assembly.GetEntryAssembly() ?? Assembly.GetExecutingAssembly())
            .GetCustomAttributes<AssemblyMetadataAttribute>()
            .ToLookup(a => a.Key, a => a.Value);

    public static string? Get(string key) => Meta[key].FirstOrDefault();

    /// Environment variable <paramref name="envVar"/> if set, else the assembly-baked
    /// metadata under <paramref name="metaKey"/>. The single home of the "env overrides
    /// the baked value" rule that Channel and CrispVersion both resolve identity through.
    public static string? Resolve(string envVar, string metaKey) =>
        Environment.GetEnvironmentVariable(envVar) ?? Get(metaKey);
}
