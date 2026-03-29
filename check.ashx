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
/// .NET 4.0 compatible — synchronous IHttpHandler, HttpWebRequest only.
/// No HttpClient, no async/await, no expression-bodied members.
///
/// GET check.ashx?server=SERVER-1&path=/App1
///   -> { "status": 200, "ms": 45, "url": "https://..." }
///   -> { "status": "timeout", "ms": 8001, "url": "..." }
///   -> { "status": "unreachable", "ms": 12, "detail": "...", "url": "..." }
///
/// GET check.ashx?debug=1
///   -> full diagnostic JSON — config path, parsed servers, connectivity tests
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

        string configJson;
        ServerDef server;
        try
        {
            configJson = ReadConfig(ctx);
            server     = FindServer(configJson, serverName);
        }
        catch (Exception ex)
        {
            ctx.Response.StatusCode = 500;
            ctx.Response.Write(Err("config error: " + ex.Message, ex.ToString()));
            return;
        }

        if (server == null)
        {
            ctx.Response.StatusCode = 403;
            ctx.Response.Write(Err("server '" + serverName + "' not found in config.json"));
            return;
        }

        var scheme  = Nvl(server.Scheme, "https");
        var port    = server.Port > 0 ? server.Port : 443;
        var portSfx = ((port == 443 && scheme == "https") || (port == 80 && scheme == "http"))
                      ? "" : ":" + port;
        var path    = appPath.StartsWith("/") ? appPath : "/" + appPath;
        path        = Regex.Replace(path, "/+", "/");

        // URL uses the site hostname (from "site" in config) for correct SNI + Host: header.
        // TCP connection is pinned to the node IP (from "host" in config), bypassing DNS.
        var site    = server.Site;
        var target  = scheme + "://" + site + portSfx + path;
        var timeout = server.TimeoutMs > 0 ? server.TimeoutMs : 8000;

        ctx.Response.Write(Probe(target, timeout, server.Host, port));
    }

    // ── HTTP probe — synchronous HttpWebRequest ───────────────────────────────

    private static string Probe(string url, int timeoutMs, string nodeIp, int port)
    {
        var r = DoRequest(url, "HEAD", timeoutMs, nodeIp, port);
        if (!r.NetworkError && (r.StatusCode == 405 || r.StatusCode == 501))
            r = DoRequest(url, "GET", timeoutMs, nodeIp, port);
        // Follow a single redirect (301/302) — IIS often redirects /app -> /app/
        if (!r.NetworkError && (r.StatusCode == 301 || r.StatusCode == 302) && r.Location != null)
        {
            var r2 = DoRequest(r.Location, "GET", timeoutMs, nodeIp, port);
            if (!r2.NetworkError) return FormatResult(r2, url);
        }
        return FormatResult(r, url);
    }

    private static string FormatResult(ProbeResult r, string url)
    {
        if (r.NetworkError)
            return "{\"ok\":false" +
                   ",\"status\":"  + JS(r.ErrorCode) +
                   ",\"ms\":"      + r.Ms +
                   ",\"detail\":"  + JS(r.Detail) +
                   ",\"url\":"     + JS(url) + "}";

        // 401/403 = app is up but requires authentication — treat as reachable
        // 2xx/3xx = healthy, 4xx (excl 401/403) / 5xx = application error
        var ok = (r.StatusCode >= 200 && r.StatusCode < 400)
              || r.StatusCode == 401
              || r.StatusCode == 403;

        return "{\"ok\":"     + (ok ? "true" : "false") +
               ",\"status\":" + r.StatusCode +
               ",\"ms\":"     + r.Ms +
               ",\"url\":"    + JS(url) + "}";
    }

    private class ProbeResult
    {
        public bool   NetworkError;
        public int    StatusCode;
        public string ErrorCode;
        public string Detail;
        public long   Ms;
        public string Location;
    }

    private static ProbeResult DoRequest(string url, string method, int timeoutMs, string nodeIp, int port)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            // TLS 1.2 — .NET 4.0 defaults to SSL3/TLS1.0
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072
                                                 | (SecurityProtocolType)768;
            // Accept internal CA / self-signed certs
            ServicePointManager.ServerCertificateValidationCallback =
                delegate(object s, System.Security.Cryptography.X509Certificates.X509Certificate c,
                         System.Security.Cryptography.X509Certificates.X509Chain ch,
                         System.Net.Security.SslPolicyErrors e) { return true; };

            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Method            = method;
            req.Timeout           = timeoutMs;
            req.AllowAutoRedirect = false;

            // Pin TCP connection to the node IP — SNI hostname comes from the URL
            // so TLS handshake and Host: header both use the public hostname correctly.
            // This lets us bypass DNS and hit each node directly without ARR or DNS entries.
            if (!string.IsNullOrEmpty(nodeIp))
            {
                IPAddress ip;
                if (IPAddress.TryParse(nodeIp, out ip))
                {
                    var endpoint = new IPEndPoint(ip, port);
                    req.ServicePoint.BindIPEndPointDelegate =
                        delegate(ServicePoint sp, IPEndPoint rem, int retryCount)
                        {
                            return endpoint;
                        };
                }
            }

            using (var resp = (HttpWebResponse)req.GetResponse())
            {
                sw.Stop();
                return new ProbeResult
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
                return new ProbeResult { NetworkError = false, StatusCode = code, Location = location, Ms = sw.ElapsedMilliseconds };
            }
            var errCode = ex.Status == WebExceptionStatus.Timeout ? "timeout" : "unreachable";
            return new ProbeResult { NetworkError = true, ErrorCode = errCode, Detail = ex.Message, Ms = sw.ElapsedMilliseconds };
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ProbeResult { NetworkError = true, ErrorCode = "error", Detail = ex.Message, Ms = sw.ElapsedMilliseconds };
        }
    }

    // ── Safe config endpoint — browser-facing, no internal details ───────────
    private void HandleAppsConfig(HttpContext ctx)
    {
        string configJson;
        ServerDef[] servers;
        try
        {
            configJson = ReadConfig(ctx);
            servers    = ParseServers(configJson);
        }
        catch (Exception ex)
        {
            ctx.Response.StatusCode = 500;
            ctx.Response.Write(Err("config error: " + ex.Message));
            return;
        }

        // Extract basePath, autoRefreshSeconds and logo from raw config
        var basePathMatch = Regex.Match(configJson, "\"basePath\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        var basePath      = basePathMatch.Success ? basePathMatch.Groups[1].Value : "";

        var autoMatch = Regex.Match(configJson, "\"autoRefreshSeconds\"\\s*:\\s*(\\d+)");
        var autoSecs  = autoMatch.Success ? autoMatch.Groups[1].Value : "60";

        var logoHostingMatch = Regex.Match(configJson, "\"logoHosting\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        var logoFallbackMatch = Regex.Match(configJson, "\"logo\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        var logoHosting  = logoHostingMatch.Success  ? logoHostingMatch.Groups[1].Value  :
                           logoFallbackMatch.Success ? logoFallbackMatch.Groups[1].Value : null;

        var logoCustomerMatch = Regex.Match(configJson, "\"logoCustomer\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        var logoCustomer = logoCustomerMatch.Success ? logoCustomerMatch.Groups[1].Value : null;

        var sb = new StringBuilder();
        sb.Append("{");
        sb.Append("\"basePath\":"          + JS(basePath) + ",");
        sb.Append("\"autoRefreshSeconds\":" + autoSecs    + ",");
        if (logoHosting  != null) sb.Append("\"logoHosting\":"  + JS(logoHosting)  + ",");
        if (logoCustomer != null) sb.Append("\"logoCustomer\":" + JS(logoCustomer) + ",");

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
            var appObjects = SplitObjects(appsMatch.Groups[1].Value);
            sb.Append("\"applications\":[");
            for (int i = 0; i < appObjects.Count; i++)
            {
                if (i > 0) sb.Append(",");
                var path  = JStr(appObjects[i], "path");
                var label = JStr(appObjects[i], "label");
                sb.Append("{\"path\":"  + JS(path) +
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
        sb.Append("\"dotnetVersion\":"       + JS(Environment.Version.ToString()) + ",");
        sb.Append("\"physicalAppPath\":"      + JS(ctx.Request.PhysicalApplicationPath) + ",");
        sb.Append("\"handlerPhysicalPath\":"  + JS(ctx.Request.PhysicalPath) + ",");

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
                var servers = ParseServers(configJson);
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
                    var scheme  = Nvl(s.Scheme, "https");
                    var port    = s.Port > 0 ? s.Port : 443;
                    var portSfx = ((port == 443 && scheme == "https") || (port == 80 && scheme == "http")) ? "" : ":" + port;
                    var url     = scheme + "://" + s.Host + portSfx + "/";
                    var result  = Probe(url, 5000, s.Host, port);
                    sb.Append("{\"server\":" + JS(s.Name) + ",\"url\":" + JS(url) + ",\"result\":" + result + "}");
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

    // ── Config ────────────────────────────────────────────────────────────────

    private static string ReadConfig(HttpContext ctx)
    {
        return File.ReadAllText(ResolveConfigPath(ctx));
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

    // ── Minimal regex JSON parser ─────────────────────────────────────────────

    private class ServerDef
    {
        public string Name;
        public string Host;   // node IP — TCP connection target
        public string Site;   // public hostname — used for SNI and Host: header
        public int    Port;
        public string Scheme;
        public int    TimeoutMs;
    }

    private static ServerDef FindServer(string json, string name)
    {
        var all = ParseServers(json);
        foreach (var s in all)
            if (string.Equals(s.Name, name, StringComparison.OrdinalIgnoreCase))
                return s;
        return null;
    }

    private static ServerDef[] ParseServers(string json)
    {
        var timeoutMs = 8000;
        var tm = Regex.Match(json, "\"timeoutMs\"\\s*:\\s*(\\d+)");
        if (tm.Success) timeoutMs = int.Parse(tm.Groups[1].Value);

        // Extract top-level "site" value
        var siteMatch = Regex.Match(json, "\"site\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        var site = siteMatch.Success ? siteMatch.Groups[1].Value : null;

        var arrMatch = Regex.Match(json, "\"servers\"\\s*:\\s*(\\[.*?\\])", RegexOptions.Singleline);
        if (!arrMatch.Success)
            throw new InvalidOperationException("Could not find \"servers\" array in config.json");

        var block   = arrMatch.Groups[1].Value;
        var objects = SplitObjects(block);
        var results = new List<ServerDef>();

        foreach (var obj in objects)
        {
            results.Add(new ServerDef
            {
                Name      = JStr(obj, "name"),
                Host      = JStr(obj, "host"),  // IP
                Site      = site,               // public hostname from top-level "site"
                Port      = JInt(obj, "port", 443),
                Scheme    = Nvl(JStr(obj, "scheme"), "https"),
                TimeoutMs = timeoutMs
            });
        }
        return results.ToArray();
    }

    private static List<string> SplitObjects(string block)
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

    private static string JStr(string obj, string key)
    {
        var m = Regex.Match(obj, "\"" + key + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return m.Success ? Regex.Unescape(m.Groups[1].Value) : null;
    }

    private static int JInt(string obj, string key, int def)
    {
        var m = Regex.Match(obj, "\"" + key + "\"\\s*:\\s*(\\d+)");
        return m.Success ? int.Parse(m.Groups[1].Value) : def;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static string Nvl(string a, string b)
    {
        return string.IsNullOrEmpty(a) ? b : a;
    }

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
