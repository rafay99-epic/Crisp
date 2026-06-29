using System;

namespace Crisp;

/// The running app's version. CI stamps CRISP_VERSION (0.<commit count on main>, like
/// the macOS build); dev defaults low so any published release reads as newer.
public static class CrispVersion
{
    public static string Current => Environment.GetEnvironmentVariable("CRISP_VERSION") ?? "0.0";
}
