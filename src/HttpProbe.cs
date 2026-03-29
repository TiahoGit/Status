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

    /// <param name="url">Full URL to probe (hostname used for SNI / Host: header).</param>
    /// <param name="timeoutMs">Per-request timeout in milliseconds.</param>
    /// <param name="nodeIp">
    ///   Optional IP address to pin the TCP connection to, bypassing DNS.
    ///   Pass null to use normal DNS resolution (required for .NET 5+ and tests).
    /// </param>
    /// <param name="port">TCP port — used only when nodeIp is set.</param>
    public static Result Probe(string url, int timeoutMs, string nodeIp, int port)
    {
        var r = DoRequest(url, "HEAD", timeoutMs, nodeIp, port);

        // Some servers reject HEAD — fall back to GET
        if (!r.NetworkError && (r.StatusCode == 405 || r.StatusCode == 501))
            r = DoRequest(url, "GET", timeoutMs, nodeIp, port);

        // Follow a single redirect (301/302) — IIS often redirects /app -> /app/
        if (!r.NetworkError && (r.StatusCode == 301 || r.StatusCode == 302) && r.Location != null)
        {
            var r2 = DoRequest(r.Location, "GET", timeoutMs, nodeIp, port);
            if (!r2.NetworkError) return ToResult(r2);
        }

        return ToResult(r);
    }

    // ── HTTP request ──────────────────────────────────────────────────────────

    private static RawResult DoRequest(string url, string method, int timeoutMs, string nodeIp, int port)
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

            // Pin TCP connection to the node IP — SNI hostname comes from the URL so
            // the TLS handshake and Host: header both use the public hostname correctly.
            // BindIPEndPointDelegate is .NET Framework only; skipped on .NET 5+.
            if (!string.IsNullOrEmpty(nodeIp))
            {
                IPAddress ip;
                if (IPAddress.TryParse(nodeIp, out ip))
                {
                    try
                    {
                        var endpoint = new IPEndPoint(ip, port);
                        req.ServicePoint.BindIPEndPointDelegate =
                            delegate(ServicePoint sp, IPEndPoint rem, int retryCount)
                            {
                                return endpoint;
                            };
                    }
                    catch (PlatformNotSupportedException) { /* .NET 5+ — skip */ }
                }
            }

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
