using System;
using System.Diagnostics;
using System.Net;
using System.Text.RegularExpressions;

/// <summary>
/// HTTP health-check probe logic for check.ashx.
/// No HttpContext dependency — safe to unit test directly.
/// .NET 4.0 compatible — synchronous HttpWebRequest only.
/// </summary>
public static class HttpProbe
{
    /// <summary>Public result returned to callers.</summary>
    public class Result
    {
        public bool   Ok;
        public bool   NetworkError;
        public int    StatusCode;   // HTTP status code; 0 when NetworkError=true
        public string ErrorCode;   // "timeout" / "unreachable" / "error"; null when NetworkError=false
        public long   Ms;
    }

    /// <summary>Internal result that also carries the Location header for redirect following.</summary>
    private class RawResult
    {
        public bool   NetworkError;
        public int    StatusCode;
        public string ErrorCode;
        public long   Ms;
        public string Location;
    }

    // ── Public entry point ────────────────────────────────────────────────────

    /// <param name="url">Full URL to probe — hostname should be the node IP or node DNS name
    ///   so the TCP connection goes directly to that server, bypassing load balancers.</param>
    /// <param name="timeoutMs">Per-request timeout in milliseconds.</param>
    /// <param name="hostHeader">
    ///   Optional value to set as the HTTP Host header, overriding the URL hostname.
    ///   Use this to send the public site hostname for IIS virtual-host routing / SNI
    ///   when the URL contains a node IP. Pass null to use the URL hostname as-is.
    /// </param>
    /// <param name="port">Reserved for future use; pass 0.</param>
    public static Result Probe(string url, int timeoutMs, string hostHeader, int port)
    {
        var r = DoRequest(url, "HEAD", timeoutMs, hostHeader, port);

        // Some servers reject HEAD — fall back to GET
        if (!r.NetworkError && (r.StatusCode == 405 || r.StatusCode == 501))
            r = DoRequest(url, "GET", timeoutMs, hostHeader, port);

        // Follow a single redirect (301/302) — IIS often redirects /app -> /app/
        if (!r.NetworkError && (r.StatusCode == 301 || r.StatusCode == 302) && r.Location != null)
        {
            var r2 = DoRequest(r.Location, "GET", timeoutMs, hostHeader, port);
            if (!r2.NetworkError) return ToResult(r2);
        }

        return ToResult(r);
    }

    // ── HTTP request ──────────────────────────────────────────────────────────

    private static RawResult DoRequest(string url, string method, int timeoutMs, string hostHeader, int port)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            // TLS 1.2 — .NET 4.0 defaults to SSL3/TLS1.0
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072
                                                 | (SecurityProtocolType)768;

            // Accept internal CA / self-signed certs on infrastructure nodes
            ServicePointManager.ServerCertificateValidationCallback =
                delegate(object s, System.Security.Cryptography.X509Certificates.X509Certificate c,
                         System.Security.Cryptography.X509Certificates.X509Chain ch,
                         System.Net.Security.SslPolicyErrors e) { return true; };

            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Method            = method;
            req.Timeout           = timeoutMs;
            req.AllowAutoRedirect = false;

            // Override the Host header so IIS routes to the correct virtual site
            // when the URL contains a node IP rather than the public hostname.
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

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Result ToResult(RawResult r)
    {
        if (r.NetworkError)
            return new Result { Ok = false, NetworkError = true, ErrorCode = r.ErrorCode, Ms = r.Ms };

        // 401/403 = app is up but requires authentication — treat as reachable
        var ok = (r.StatusCode >= 200 && r.StatusCode < 400)
              || r.StatusCode == 401
              || r.StatusCode == 403;

        return new Result { Ok = ok, NetworkError = false, StatusCode = r.StatusCode, Ms = r.Ms };
    }
}
