using NUnit.Framework;
using System;
using System.Net;
using System.Threading;

[TestFixture]
public class HttpProbeTests
{
    // ── Local test HTTP server ────────────────────────────────────────────────

    /// <summary>
    /// Minimal HttpListener-based server for testing.
    /// The handler is called once per request on a background thread.
    /// </summary>
    private sealed class TestServer : IDisposable
    {
        private readonly HttpListener          _listener;
        private readonly Thread                _thread;
        private readonly Action<HttpListenerContext> _handler;

        public string BaseUrl { get; }

        public TestServer(Action<HttpListenerContext> handler)
        {
            _handler = handler;
            BaseUrl  = $"http://localhost:{GetFreePort()}/";
            _listener = new HttpListener();
            _listener.Prefixes.Add(BaseUrl);
            _listener.Start();
            _thread = new Thread(Serve) { IsBackground = true };
            _thread.Start();
        }

        private void Serve()
        {
            while (_listener.IsListening)
            {
                try
                {
                    var ctx = _listener.GetContext();
                    _handler(ctx);
                    try { ctx.Response.Close(); } catch { /* already closed */ }
                }
                catch { break; }
            }
        }

        public void Dispose()
        {
            _listener.Stop();
            _listener.Close();
        }

        private static int GetFreePort()
        {
            var l = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
            l.Start();
            var port = ((IPEndPoint)l.LocalEndpoint).Port;
            l.Stop();
            return port;
        }
    }

    // ── Status code classification ────────────────────────────────────────────

    [Test]
    public void Probe_200_IsOk()
    {
        using var s = new TestServer(ctx => ctx.Response.StatusCode = 200);
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,           Is.True);
        Assert.That(r.NetworkError, Is.False);
        Assert.That(r.StatusCode,   Is.EqualTo(200));
    }

    [Test]
    public void Probe_401_IsOkAuthGated()
    {
        using var s = new TestServer(ctx => ctx.Response.StatusCode = 401);
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,         Is.True);
        Assert.That(r.StatusCode, Is.EqualTo(401));
    }

    [Test]
    public void Probe_403_IsOkAuthGated()
    {
        using var s = new TestServer(ctx => ctx.Response.StatusCode = 403);
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,         Is.True);
        Assert.That(r.StatusCode, Is.EqualTo(403));
    }

    [Test]
    public void Probe_404_IsNotOk()
    {
        using var s = new TestServer(ctx => ctx.Response.StatusCode = 404);
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,         Is.False);
        Assert.That(r.StatusCode, Is.EqualTo(404));
    }

    [Test]
    public void Probe_500_IsNotOk()
    {
        using var s = new TestServer(ctx => ctx.Response.StatusCode = 500);
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,         Is.False);
        Assert.That(r.StatusCode, Is.EqualTo(500));
    }

    // ── HEAD → GET fallback ───────────────────────────────────────────────────

    [Test]
    public void Probe_405OnHead_RetriesWithGet_AndSucceeds()
    {
        using var s = new TestServer(ctx =>
        {
            ctx.Response.StatusCode = ctx.Request.HttpMethod == "HEAD" ? 405 : 200;
        });
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,         Is.True);
        Assert.That(r.StatusCode, Is.EqualTo(200));
    }

    [Test]
    public void Probe_501OnHead_RetriesWithGet_AndSucceeds()
    {
        using var s = new TestServer(ctx =>
        {
            ctx.Response.StatusCode = ctx.Request.HttpMethod == "HEAD" ? 501 : 200;
        });
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,         Is.True);
        Assert.That(r.StatusCode, Is.EqualTo(200));
    }

    [Test]
    public void Probe_405OnHead_RetriesWithGet_AndReportsGetStatusCode()
    {
        using var s = new TestServer(ctx =>
        {
            ctx.Response.StatusCode = ctx.Request.HttpMethod == "HEAD" ? 405 : 404;
        });
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,         Is.False);
        Assert.That(r.StatusCode, Is.EqualTo(404));
    }

    // ── Redirect following ────────────────────────────────────────────────────

    [Test]
    public void Probe_301_FollowsRedirectToFinalStatus()
    {
        string redirectTarget = null;

        using var dest   = new TestServer(ctx => ctx.Response.StatusCode = 200);
        redirectTarget   = dest.BaseUrl;

        using var origin = new TestServer(ctx =>
        {
            ctx.Response.StatusCode       = 301;
            ctx.Response.Headers["Location"] = redirectTarget;
        });

        var r = HttpProbe.Probe(origin.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,         Is.True);
        Assert.That(r.StatusCode, Is.EqualTo(200));
    }

    [Test]
    public void Probe_302_FollowsRedirectToFinalStatus()
    {
        string redirectTarget = null;

        using var dest   = new TestServer(ctx => ctx.Response.StatusCode = 200);
        redirectTarget   = dest.BaseUrl;

        using var origin = new TestServer(ctx =>
        {
            ctx.Response.StatusCode          = 302;
            ctx.Response.Headers["Location"] = redirectTarget;
        });

        var r = HttpProbe.Probe(origin.BaseUrl, 5000, null, 0);
        Assert.That(r.Ok,         Is.True);
        Assert.That(r.StatusCode, Is.EqualTo(200));
    }

    [Test]
    public void Probe_301WithNoLocation_ReturnsRedirectStatus()
    {
        using var s = new TestServer(ctx => ctx.Response.StatusCode = 301);
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        // No Location header — treated as a successful (reachable) 3xx response
        Assert.That(r.Ok,         Is.True);
        Assert.That(r.StatusCode, Is.EqualTo(301));
    }

    // ── Network errors ────────────────────────────────────────────────────────

    [Test]
    public void Probe_Unreachable_ReturnsNetworkError()
    {
        // Use a port that is guaranteed not to be listening
        var port = GetClosedPort();
        var r = HttpProbe.Probe($"http://localhost:{port}/", 5000, null, 0);
        Assert.That(r.NetworkError, Is.True);
        Assert.That(r.Ok,           Is.False);
        Assert.That(r.ErrorCode,    Is.EqualTo("unreachable"));
    }

    [Test]
    public void Probe_Timeout_ReturnsTimeoutError()
    {
        using var s = new TestServer(ctx =>
        {
            // Hold the connection open longer than the probe timeout
            Thread.Sleep(3000);
            ctx.Response.StatusCode = 200;
        });
        var r = HttpProbe.Probe(s.BaseUrl, 200, null, 0);
        Assert.That(r.NetworkError, Is.True);
        Assert.That(r.Ok,           Is.False);
        Assert.That(r.ErrorCode,    Is.EqualTo("timeout"));
    }

    // ── Timing ───────────────────────────────────────────────────────────────

    [Test]
    public void Probe_ReportsPositiveElapsedTime()
    {
        using var s = new TestServer(ctx => ctx.Response.StatusCode = 200);
        var r = HttpProbe.Probe(s.BaseUrl, 5000, null, 0);
        Assert.That(r.Ms, Is.GreaterThanOrEqualTo(0));
    }

    [Test]
    public void Probe_TimeoutResult_ReportsElapsedTime()
    {
        using var s = new TestServer(ctx =>
        {
            Thread.Sleep(3000);
            ctx.Response.StatusCode = 200;
        });
        var r = HttpProbe.Probe(s.BaseUrl, 200, null, 0);
        Assert.That(r.Ms, Is.GreaterThanOrEqualTo(0));
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private static int GetClosedPort()
    {
        // Bind then immediately stop — guarantees the port is closed
        var l = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return port;
    }
}
