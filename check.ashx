<%@ WebHandler Language="C#" Class="StatusCheck" %>

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;

/// <summary>
/// Server-side health check proxy for the Application Status page.
/// Self-contained — all helper classes (ConfigParser, HttpProbe) are inlined
/// below so this file deploys without any App_Code dependency.
/// .NET 4.0 compatible — synchronous IHttpHandler, HttpWebRequest only.
///
/// GET check.ashx?action=apps
///   -> sanitised config JSON (server names, app paths, logos, version)
///
/// GET check.ashx?server=SERVER-1&path=/App1
///   -> { "ok": true,  "status": 200,         "ms": 45  }
///   -> { "ok": false, "status": "timeout",    "ms": 8001 }
///   -> { "ok": false, "status": "unreachable","ms": 12  }
///
/// GET check.ashx?debug=1  (localhost only)
///   -> full diagnostic JSON
/// </summary>
public class StatusCheck : IHttpHandler
{
    public bool IsReusable { get { return true; } }

    public void ProcessRequest(HttpContext ctx)
    {
        ctx.Response.ContentType = "application/json";
        ctx.Response.Cache.SetNoStore();

        // Debug endpoint — only accessible from the server itself (localhost)
        if (ctx.Request.QueryString["debug"] != null)
        {
            if (!ctx.Request.IsLocal)
            {
                ctx.Response.StatusCode = 403;
                ctx.Response.Write(Err("debug endpoint is only accessible from the server"));
                return;
            }
            HandleDebug(ctx);
            return;
        }

        if ((ctx.Request.QueryString["action"] ?? "") == "apps")
        {
            HandleAppsConfig(ctx);
            return;
        }

        var serverName = (ctx.Request.QueryString["server"] ?? "").Trim();
        var appPath    = (ctx.Request.QueryString["path"]   ?? "").Trim();

        if (serverName == "" || appPath == "")
        {
            ctx.Response.StatusCode = 400;
            ctx.Response.Write(Err("server and path query parameters are required"));
            return;
        }

        if (appPath.Contains(".."))
        {
            ctx.Response.StatusCode = 400;
            ctx.Response.Write(Err("invalid path"));
            return;
        }

        string configJson;
        ConfigParser.ServerDef server;
        try
        {
            configJson = ReadConfig(ctx);
            server     = ConfigParser.FindServer(configJson, serverName);
        }
        catch (Exception ex)
        {
            ctx.Response.StatusCode = 500;
            ctx.Response.Write(Err("config error: " + ex.Message));
            return;
        }

        if (server == null)
        {
            ctx.Response.StatusCode = 403;
            ctx.Response.Write(Err("server '" + serverName + "' not found in config.json"));
            return;
        }

        var scheme  = ConfigParser.Nvl(server.Scheme, "https");
        var port    = server.Port > 0 ? server.Port : 443;
        var portSfx = ((port == 443 && scheme == "https") || (port == 80 && scheme == "http"))
                      ? "" : ":" + port;
        var path    = appPath.StartsWith("/") ? appPath : "/" + appPath;
        path        = Regex.Replace(path, "/+", "/");

        // Use the node host (IP or DNS name) in the URL so the TCP connection goes directly
        // to that server, bypassing DNS/ARR load balancing.  The public site hostname is
        // passed as the Host header so IIS routes to the correct virtual site.
        var nodeHost = !string.IsNullOrEmpty(server.Host) ? server.Host : server.Site;
        var target   = scheme + "://" + nodeHost + portSfx + path;

        ctx.Response.Write(FormatResult(HttpProbe.Probe(target, server.TimeoutMs, server.Site, port)));
    }

    // ── Safe config endpoint — browser-facing, no internal details ───────────

    private void HandleAppsConfig(HttpContext ctx)
    {
        string configJson;
        ConfigParser.ServerDef[] servers;
        try
        {
            configJson = ReadConfig(ctx);
            servers    = ConfigParser.ParseServers(configJson);
        }
        catch (Exception ex)
        {
            ctx.Response.StatusCode = 500;
            ctx.Response.Write(Err("config error: " + ex.Message));
            return;
        }

        var basePath = ConfigParser.ParseBasePath(configJson);
        var autoSecs = ConfigParser.ParseAutoRefreshSeconds(configJson).ToString();
        var version  = ConfigParser.ParseVersion(ReadVersionFile(ctx));
        var hosting  = ConfigParser.ParseBranding(configJson, "hosting");
        var customer = ConfigParser.ParseBranding(configJson, "customer");

        var sb = new StringBuilder();
        sb.Append("{");
        sb.Append("\"basePath\":"           + JS(basePath) + ",");
        sb.Append("\"autoRefreshSeconds\":" + autoSecs     + ",");
        if (version  != null) sb.Append("\"version\":" + JS(version) + ",");
        if (hosting  != null)
        {
            var parts = new List<string>();
            if (hosting.Name    != null) parts.Add("\"name\":"    + JS(hosting.Name));
            if (hosting.Logo    != null) parts.Add("\"logo\":"    + JS(hosting.Logo));
            if (hosting.Website != null) parts.Add("\"website\":" + JS(hosting.Website));
            sb.Append("\"hosting\":{" + string.Join(",", parts) + "},");
        }
        if (customer != null)
        {
            var parts = new List<string>();
            if (customer.Name    != null) parts.Add("\"name\":"    + JS(customer.Name));
            if (customer.Logo    != null) parts.Add("\"logo\":"    + JS(customer.Logo));
            if (customer.Website != null) parts.Add("\"website\":" + JS(customer.Website));
            sb.Append("\"customer\":{" + string.Join(",", parts) + "},");
        }

        // Server names only — no IPs, no hostnames
        sb.Append("\"servers\":[");
        for (int i = 0; i < servers.Length; i++)
        {
            if (i > 0) sb.Append(",");
            sb.Append("{\"name\":" + JS(servers[i].Name) + "}");
        }
        sb.Append("],");

        // Applications — path and label only
        var appsMatch = Regex.Match(configJson, "\"applications\"\\s*:\\s*(\\[.*?\\])",
            RegexOptions.Singleline);
        if (appsMatch.Success)
        {
            var appObjects = ConfigParser.SplitObjects(appsMatch.Groups[1].Value);
            sb.Append("\"applications\":[");
            for (int i = 0; i < appObjects.Count; i++)
            {
                if (i > 0) sb.Append(",");
                var p     = ConfigParser.JStr(appObjects[i], "path");
                var label = ConfigParser.JStr(appObjects[i], "label");
                sb.Append("{\"path\":"  + JS(p) +
                          ",\"label\":" + JS(label) + "}");
            }
            sb.Append("]");
        }
        else
        {
            sb.Append("\"applications\":[]");
        }

        sb.Append("}");
        ctx.Response.Write(sb.ToString());
    }

    // ── Debug handler ─────────────────────────────────────────────────────────

    private void HandleDebug(HttpContext ctx)
    {
        var sb = new StringBuilder();
        sb.Append("{");
        sb.Append("\"dotnetVersion\":"      + JS(Environment.Version.ToString()) + ",");
        sb.Append("\"physicalAppPath\":"     + JS(ctx.Request.PhysicalApplicationPath) + ",");
        sb.Append("\"handlerPhysicalPath\":" + JS(ctx.Request.PhysicalPath) + ",");

        string configPath = null;
        try
        {
            configPath = ResolveConfigPath(ctx);
            sb.Append("\"configPath\":"   + JS(configPath) + ",");
            sb.Append("\"configExists\":" + (File.Exists(configPath) ? "true" : "false") + ",");
        }
        catch (Exception ex)
        {
            sb.Append("\"configPathError\":" + JS(ex.Message) + ",");
        }

        string configJson = null;
        if (configPath != null && File.Exists(configPath))
        {
            try
            {
                configJson = File.ReadAllText(configPath);
                sb.Append("\"configRaw\":" + JS(configJson) + ",");
            }
            catch (Exception ex)
            {
                sb.Append("\"configReadError\":" + JS(ex.Message) + ",");
            }
        }

        if (configJson != null)
        {
            try
            {
                var servers = ConfigParser.ParseServers(configJson);
                sb.Append("\"parsedServers\":[");
                for (int i = 0; i < servers.Length; i++)
                {
                    if (i > 0) sb.Append(",");
                    sb.Append("{\"name\":"   + JS(servers[i].Name)   +
                              ",\"host\":"   + JS(servers[i].Host)   +
                              ",\"site\":"   + JS(servers[i].Site)   +
                              ",\"port\":"   + servers[i].Port       +
                              ",\"scheme\":" + JS(servers[i].Scheme) + "}");
                }
                sb.Append("],");

                sb.Append("\"connectivityTests\":[");
                for (int i = 0; i < servers.Length; i++)
                {
                    if (i > 0) sb.Append(",");
                    var s       = servers[i];
                    var scheme  = ConfigParser.Nvl(s.Scheme, "https");
                    var port    = s.Port > 0 ? s.Port : 443;
                    var portSfx = ((port == 443 && scheme == "https") || (port == 80 && scheme == "http")) ? "" : ":" + port;
                    var url     = scheme + "://" + s.Host + portSfx + "/";
                    sb.Append("{\"server\":" + JS(s.Name) + ",\"url\":" + JS(url) +
                              ",\"result\":"  + FormatResult(HttpProbe.Probe(url, 5000, s.Site, port)) + "}");
                }
                sb.Append("]");
            }
            catch (Exception ex)
            {
                sb.Append("\"parseError\":" + JS(ex.Message));
            }
        }
        else
        {
            sb.Append("\"parsedServers\":null,\"connectivityTests\":null");
        }

        sb.Append("}");
        ctx.Response.Write(sb.ToString());
    }

    // ── Probe result serialisation ────────────────────────────────────────────

    private static string FormatResult(HttpProbe.Result r)
    {
        if (r.NetworkError)
            return "{\"ok\":false"        +
                   ",\"status\":"  + JS(r.ErrorCode) +
                   ",\"ms\":"      + r.Ms + "}";

        return "{\"ok\":"     + (r.Ok ? "true" : "false") +
               ",\"status\":" + r.StatusCode +
               ",\"ms\":"     + r.Ms + "}";
    }

    // ── Config / version file reading ─────────────────────────────────────────

    private static string ReadConfig(HttpContext ctx)
    {
        return File.ReadAllText(ResolveConfigPath(ctx));
    }

    /// <summary>
    /// Reads version.json from the application directory.
    /// Returns null without throwing if the file is absent — version is optional.
    /// </summary>
    private static string ReadVersionFile(HttpContext ctx)
    {
        try
        {
            var dir  = Path.GetDirectoryName(ctx.Request.PhysicalPath);
            var path = Path.Combine(dir, "version.json");
            if (File.Exists(path)) return File.ReadAllText(path);

            var path2 = Path.Combine(ctx.Request.PhysicalApplicationPath.TrimEnd('\\'), "version.json");
            if (File.Exists(path2)) return File.ReadAllText(path2);
        }
        catch { /* version is optional — never fail the response over it */ }
        return null;
    }

    private static string ResolveConfigPath(HttpContext ctx)
    {
        var dir  = Path.GetDirectoryName(ctx.Request.PhysicalPath);
        var path = Path.Combine(dir, "config.json");
        if (File.Exists(path)) return path;

        var path2 = Path.Combine(ctx.Request.PhysicalApplicationPath.TrimEnd('\\'), "config.json");
        if (File.Exists(path2)) return path2;

        throw new FileNotFoundException(
            "config.json not found. Tried: [" + path + "] and [" + path2 + "]");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static string JS(string s)
    {
        if (s == null) return "null";
        return "\"" + s.Replace("\\", "\\\\")
                        .Replace("\"", "\\\"")
                        .Replace("\r", "\\r")
                        .Replace("\n", "\\n")
                        .Replace("\t", "\\t") + "\"";
    }

    private static string Err(string msg, string detail)
    {
        return "{\"error\":" + JS(msg) + ",\"detail\":" + JS(detail) + "}";
    }

    private static string Err(string msg)
    {
        return "{\"error\":" + JS(msg) + "}";
    }
}

// ── ConfigParser ──────────────────────────────────────────────────────────────
// Inlined here so check.ashx deploys as a single file with no App_Code dependency.
// The canonical source lives in src/ConfigParser.cs and is used by the test project.

public static class ConfigParser
{
    public class ServerDef
    {
        public string Name;
        public string Host;      // node IP — TCP connection target
        public string Site;      // public hostname — SNI and Host: header
        public int    Port;
        public string Scheme;
        public int    TimeoutMs;
    }

    public class BrandingDef
    {
        public string Name;
        public string Logo;
        public string Website;
    }

    // ── Top-level scalar fields ───────────────────────────────────────────────

    public static string ParseVersion(string json)
    {
        if (json == null) return null;
        var m = Regex.Match(json, "\"version\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return m.Success ? Unescape(m.Groups[1].Value) : null;
    }

    public static string ParseLogoHosting(string json)
    {
        var m = Regex.Match(json, "\"logoHosting\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        if (m.Success) return Unescape(m.Groups[1].Value);
        var fb = Regex.Match(json, "\"logo\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return fb.Success ? Unescape(fb.Groups[1].Value) : null;
    }

    public static string ParseLogoCustomer(string json)
    {
        var m = Regex.Match(json, "\"logoCustomer\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return m.Success ? Unescape(m.Groups[1].Value) : null;
    }

    public static string ParseBasePath(string json)
    {
        var m = Regex.Match(json, "\"basePath\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return m.Success ? Unescape(m.Groups[1].Value) : "";
    }

    public static int ParseAutoRefreshSeconds(string json)
    {
        var m = Regex.Match(json, "\"autoRefreshSeconds\"\\s*:\\s*(\\d+)");
        return m.Success ? int.Parse(m.Groups[1].Value) : 60;
    }

    // ── Branding ──────────────────────────────────────────────────────────────

    public static BrandingDef ParseBranding(string json, string key)
    {
        var nested  = ExtractObject(json, key);
        var name    = nested != null ? JStr(nested, "name")    : null;
        var logo    = nested != null ? JStr(nested, "logo")    : null;
        var website = nested != null ? JStr(nested, "website") : null;

        if (logo == null)
        {
            if (key == "hosting")  logo = ParseLogoHosting(json);
            if (key == "customer") logo = ParseLogoCustomer(json);
        }

        if (name == null && logo == null && website == null) return null;
        return new BrandingDef { Name = name, Logo = logo, Website = website };
    }

    private static string ExtractObject(string json, string key)
    {
        var m = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\\{");
        if (!m.Success) return null;
        int start = m.Index + m.Length - 1;
        int depth = 0;
        for (int i = start; i < json.Length; i++)
        {
            if      (json[i] == '{') depth++;
            else if (json[i] == '}') { if (--depth == 0) return json.Substring(start, i - start + 1); }
        }
        return null;
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

    public static string Nvl(string a, string b) { return string.IsNullOrEmpty(a) ? b : a; }

    private static string Unescape(string s) { return Regex.Unescape(s); }
}

// ── HttpProbe ─────────────────────────────────────────────────────────────────
// Inlined here so check.ashx deploys as a single file with no App_Code dependency.
// The canonical source lives in src/HttpProbe.cs and is used by the test project.

public static class HttpProbe
{
    public class Result
    {
        public bool   Ok;
        public bool   NetworkError;
        public int    StatusCode;
        public string ErrorCode;
        public long   Ms;
    }

    private class RawResult
    {
        public bool   NetworkError;
        public int    StatusCode;
        public string ErrorCode;
        public long   Ms;
        public string Location;
    }

    public static Result Probe(string url, int timeoutMs, string hostHeader, int port)
    {
        var r = DoRequest(url, "HEAD", timeoutMs, hostHeader, port);
        if (!r.NetworkError && (r.StatusCode == 405 || r.StatusCode == 501))
            r = DoRequest(url, "GET", timeoutMs, hostHeader, port);
        if (!r.NetworkError && (r.StatusCode == 301 || r.StatusCode == 302) && r.Location != null)
        {
            var r2 = DoRequest(r.Location, "GET", timeoutMs, hostHeader, port);
            if (!r2.NetworkError) return ToResult(r2);
        }
        return ToResult(r);
    }

    private static RawResult DoRequest(string url, string method, int timeoutMs, string hostHeader, int port)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072
                                                 | (SecurityProtocolType)768;
            ServicePointManager.ServerCertificateValidationCallback =
                delegate(object s, System.Security.Cryptography.X509Certificates.X509Certificate c,
                         System.Security.Cryptography.X509Certificates.X509Chain ch,
                         System.Net.Security.SslPolicyErrors e) { return true; };

            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Method            = method;
            req.Timeout           = timeoutMs;
            req.AllowAutoRedirect = false;

            if (!string.IsNullOrEmpty(hostHeader))
                req.Host = hostHeader;

            using (var resp = (HttpWebResponse)req.GetResponse())
            {
                sw.Stop();
                return new RawResult
                {
                    NetworkError = false,
                    StatusCode   = (int)resp.StatusCode,
                    Location     = resp.Headers["Location"],
                    Ms           = sw.ElapsedMilliseconds
                };
            }
        }
        catch (WebException ex)
        {
            sw.Stop();
            if (ex.Response != null)
            {
                var code     = (int)((HttpWebResponse)ex.Response).StatusCode;
                var location = ((HttpWebResponse)ex.Response).Headers["Location"];
                return new RawResult { NetworkError = false, StatusCode = code, Location = location, Ms = sw.ElapsedMilliseconds };
            }
            var errCode = ex.Status == WebExceptionStatus.Timeout ? "timeout" : "unreachable";
            return new RawResult { NetworkError = true, ErrorCode = errCode, Ms = sw.ElapsedMilliseconds };
        }
        catch (Exception)
        {
            sw.Stop();
            return new RawResult { NetworkError = true, ErrorCode = "error", Ms = sw.ElapsedMilliseconds };
        }
    }

    private static Result ToResult(RawResult r)
    {
        if (r.NetworkError)
            return new Result { Ok = false, NetworkError = true, ErrorCode = r.ErrorCode, Ms = r.Ms };
        var ok = (r.StatusCode >= 200 && r.StatusCode < 400)
              || r.StatusCode == 401
              || r.StatusCode == 403;
        return new Result { Ok = ok, NetworkError = false, StatusCode = r.StatusCode, Ms = r.Ms };
    }
}
