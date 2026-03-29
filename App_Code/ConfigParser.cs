using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

/// <summary>
/// Pure config-parsing helpers for check.ashx.
/// No HttpContext dependency — safe to unit test directly.
/// </summary>
public static class ConfigParser
{
    public class ServerDef
    {
        public string Name;
        public string Host;    // node IP — TCP connection target
        public string Site;    // public hostname — SNI and Host: header
        public int    Port;
        public string Scheme;
        public int    TimeoutMs;
    }

    // ── Top-level scalar fields ───────────────────────────────────────────────

    /// <summary>
    /// Returns the logoHosting URL, falling back to the legacy "logo" field.
    /// Returns null if neither is present.
    /// </summary>
    public static string ParseLogoHosting(string json)
    {
        var m = Regex.Match(json, "\"logoHosting\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        if (m.Success) return Unescape(m.Groups[1].Value);
        var fb = Regex.Match(json, "\"logo\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return fb.Success ? Unescape(fb.Groups[1].Value) : null;
    }

    /// <summary>
    /// Returns the logoCustomer URL, or null if not present.
    /// Does NOT fall back to "logo".
    /// </summary>
    public static string ParseLogoCustomer(string json)
    {
        var m = Regex.Match(json, "\"logoCustomer\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return m.Success ? Unescape(m.Groups[1].Value) : null;
    }

    /// <summary>Returns basePath, or empty string if absent.</summary>
    public static string ParseBasePath(string json)
    {
        var m = Regex.Match(json, "\"basePath\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return m.Success ? Unescape(m.Groups[1].Value) : "";
    }

    /// <summary>Returns autoRefreshSeconds, or 60 if absent.</summary>
    public static int ParseAutoRefreshSeconds(string json)
    {
        var m = Regex.Match(json, "\"autoRefreshSeconds\"\\s*:\\s*(\\d+)");
        return m.Success ? int.Parse(m.Groups[1].Value) : 60;
    }

    // ── Servers ───────────────────────────────────────────────────────────────

    public static ServerDef FindServer(string json, string name)
    {
        foreach (var s in ParseServers(json))
            if (string.Equals(s.Name, name, StringComparison.OrdinalIgnoreCase))
                return s;
        return null;
    }

    public static ServerDef[] ParseServers(string json)
    {
        var timeoutMs = 8000;
        var tm = Regex.Match(json, "\"timeoutMs\"\\s*:\\s*(\\d+)");
        if (tm.Success) timeoutMs = int.Parse(tm.Groups[1].Value);

        var siteMatch = Regex.Match(json, "\"site\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        var site      = siteMatch.Success ? Unescape(siteMatch.Groups[1].Value) : null;

        var arrMatch = Regex.Match(json, "\"servers\"\\s*:\\s*(\\[.*?\\])", RegexOptions.Singleline);
        if (!arrMatch.Success)
            throw new InvalidOperationException("Could not find \"servers\" array in config.json");

        var results = new List<ServerDef>();
        foreach (var obj in SplitObjects(arrMatch.Groups[1].Value))
        {
            results.Add(new ServerDef
            {
                Name      = JStr(obj, "name"),
                Host      = JStr(obj, "host"),
                Site      = site,
                Port      = JInt(obj, "port", 443),
                Scheme    = Nvl(JStr(obj, "scheme"), "https"),
                TimeoutMs = timeoutMs
            });
        }
        return results.ToArray();
    }

    // ── JSON micro-parser ─────────────────────────────────────────────────────

    public static List<string> SplitObjects(string block)
    {
        var list  = new List<string>();
        int depth = 0, start = -1;
        for (int i = 0; i < block.Length; i++)
        {
            if      (block[i] == '{') { if (depth++ == 0) start = i; }
            else if (block[i] == '}') { if (--depth == 0 && start >= 0) { list.Add(block.Substring(start, i - start + 1)); start = -1; } }
        }
        return list;
    }

    public static string JStr(string obj, string key)
    {
        var m = Regex.Match(obj, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return m.Success ? Unescape(m.Groups[1].Value) : null;
    }

    public static int JInt(string obj, string key, int def)
    {
        var m = Regex.Match(obj, "\"" + Regex.Escape(key) + "\"\\s*:\\s*(\\d+)");
        return m.Success ? int.Parse(m.Groups[1].Value) : def;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    public static string Nvl(string a, string b) => string.IsNullOrEmpty(a) ? b : a;

    private static string Unescape(string s) => Regex.Unescape(s);
}
