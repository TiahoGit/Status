<%@ WebHandler Language="C#" Class="StatusCheck" %>

using System;
using System.IO;
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

        var site   = server.Site;
        var target = scheme + "://" + site + portSfx + path;

        ctx.Response.Write(FormatResult(HttpProbe.Probe(target, server.TimeoutMs, server.Host, port)));
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

        var basePath     = ConfigParser.ParseBasePath(configJson);
        var autoSecs     = ConfigParser.ParseAutoRefreshSeconds(configJson).ToString();
        var version      = ConfigParser.ParseVersion(ReadVersionFile(ctx));
        var logoHosting  = ConfigParser.ParseLogoHosting(configJson);
        var logoCustomer = ConfigParser.ParseLogoCustomer(configJson);

        var sb = new StringBuilder();
        sb.Append("{");
        sb.Append("\"basePath\":"           + JS(basePath) + ",");
        sb.Append("\"autoRefreshSeconds\":" + autoSecs     + ",");
        if (version      != null) sb.Append("\"version\":"      + JS(version)      + ",");
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
            var appObjects = ConfigParser.SplitObjects(appsMatch.Groups[1].Value);
            sb.Append("\"applications\":[");
            for (int i = 0; i < appObjects.Count; i++)
            {
                if (i > 0) sb.Append(",");
                var path  = ConfigParser.JStr(appObjects[i], "path");
                var label = ConfigParser.JStr(appObjects[i], "label");
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
                    var result  = FormatResult(HttpProbe.Probe(url, 5000, s.Host, port));
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

    // ── Probe result serialisation ────────────────────────────────────────────

    private static string FormatResult(HttpProbe.Result r)
    {
        if (r.NetworkError)
            return "{\"ok\":false" +
                   ",\"status\":" + JS(r.ErrorCode) +
                   ",\"ms\":"     + r.Ms + "}";

        return "{\"ok\":"     + (r.Ok ? "true" : "false") +
               ",\"status\":" + r.StatusCode +
               ",\"ms\":"     + r.Ms + "}";
    }

    // ── Config ────────────────────────────────────────────────────────────────

    private static string ReadConfig(HttpContext ctx)
    {
        return File.ReadAllText(ResolveConfigPath(ctx));
    }

    /// <summary>
    /// Reads version.json from the application directory.
    /// Returns null (without throwing) if the file is absent — version display is optional.
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
