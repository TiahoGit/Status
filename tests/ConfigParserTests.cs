using NUnit.Framework;
using System;
using System.Collections.Generic;

[TestFixture]
public class ConfigParserTests
{
    // ── Helpers ───────────────────────────────────────────────────────────────

    private static string BaseConfig(string extras = "") => $@"{{
  ""site"": ""app.example.com"",
  ""basePath"": ""/status"",
  ""autoRefreshSeconds"": 30,
  {extras}
  ""servers"": [
    {{ ""name"": ""WEB-1"", ""host"": ""10.0.0.1"", ""port"": 443, ""scheme"": ""https"" }}
  ],
  ""applications"": [
    {{ ""path"": ""/app1"", ""label"": ""My App"" }}
  ],
  ""healthCheck"": {{ ""timeoutMs"": 5000 }}
}}";

    // ── ParseLogoHosting ──────────────────────────────────────────────────────

    [Test]
    public void ParseLogoHosting_ReturnsLogoHostingValue()
    {
        var json = BaseConfig(@"""logoHosting"": ""https://host.example.com/logo.svg"",");
        Assert.That(ConfigParser.ParseLogoHosting(json), Is.EqualTo("https://host.example.com/logo.svg"));
    }

    [Test]
    public void ParseLogoHosting_FallsBackToLegacyLogoField()
    {
        var json = BaseConfig(@"""logo"": ""https://legacy.example.com/logo.svg"",");
        Assert.That(ConfigParser.ParseLogoHosting(json), Is.EqualTo("https://legacy.example.com/logo.svg"));
    }

    [Test]
    public void ParseLogoHosting_PrefersLogoHostingOverLegacyLogo()
    {
        var json = BaseConfig(@"""logoHosting"": ""https://new.example.com/logo.svg"", ""logo"": ""https://old.example.com/logo.svg"",");
        Assert.That(ConfigParser.ParseLogoHosting(json), Is.EqualTo("https://new.example.com/logo.svg"));
    }

    [Test]
    public void ParseLogoHosting_ReturnsNullWhenAbsent()
    {
        var json = BaseConfig();
        Assert.That(ConfigParser.ParseLogoHosting(json), Is.Null);
    }

    // ── ParseLogoCustomer ─────────────────────────────────────────────────────

    [Test]
    public void ParseLogoCustomer_ReturnsLogoCustomerValue()
    {
        var json = BaseConfig(@"""logoCustomer"": ""https://customer.example.com/logo.svg"",");
        Assert.That(ConfigParser.ParseLogoCustomer(json), Is.EqualTo("https://customer.example.com/logo.svg"));
    }

    [Test]
    public void ParseLogoCustomer_ReturnsNullWhenAbsent()
    {
        var json = BaseConfig();
        Assert.That(ConfigParser.ParseLogoCustomer(json), Is.Null);
    }

    [Test]
    public void ParseLogoCustomer_DoesNotFallBackToLegacyLogo()
    {
        var json = BaseConfig(@"""logo"": ""https://legacy.example.com/logo.svg"",");
        Assert.That(ConfigParser.ParseLogoCustomer(json), Is.Null);
    }

    // ── ParseBasePath ─────────────────────────────────────────────────────────

    [Test]
    public void ParseBasePath_ReturnsConfiguredValue()
    {
        var json = BaseConfig();
        Assert.That(ConfigParser.ParseBasePath(json), Is.EqualTo("/status"));
    }

    [Test]
    public void ParseBasePath_ReturnsEmptyStringWhenAbsent()
    {
        var json = @"{ ""site"": ""x"", ""servers"": [{ ""name"": ""A"", ""host"": ""1.2.3.4"" }], ""applications"": [] }";
        Assert.That(ConfigParser.ParseBasePath(json), Is.EqualTo(""));
    }

    [Test]
    public void ParseBasePath_ReturnsEmptyStringWhenExplicitlyEmpty()
    {
        var json = BaseConfig().Replace(@"""basePath"": ""/status""", @"""basePath"": """"");
        Assert.That(ConfigParser.ParseBasePath(json), Is.EqualTo(""));
    }

    // ── ParseAutoRefreshSeconds ───────────────────────────────────────────────

    [Test]
    public void ParseAutoRefreshSeconds_ReturnsConfiguredValue()
    {
        var json = BaseConfig();
        Assert.That(ConfigParser.ParseAutoRefreshSeconds(json), Is.EqualTo(30));
    }

    [Test]
    public void ParseAutoRefreshSeconds_DefaultsTo60WhenAbsent()
    {
        var json = @"{ ""site"": ""x"", ""servers"": [{ ""name"": ""A"", ""host"": ""1.2.3.4"" }], ""applications"": [] }";
        Assert.That(ConfigParser.ParseAutoRefreshSeconds(json), Is.EqualTo(60));
    }

    // ── ParseServers ──────────────────────────────────────────────────────────

    [Test]
    public void ParseServers_ParsesNameHostPortScheme()
    {
        var json = BaseConfig();
        var servers = ConfigParser.ParseServers(json);
        Assert.That(servers.Length, Is.EqualTo(1));
        Assert.That(servers[0].Name,   Is.EqualTo("WEB-1"));
        Assert.That(servers[0].Host,   Is.EqualTo("10.0.0.1"));
        Assert.That(servers[0].Port,   Is.EqualTo(443));
        Assert.That(servers[0].Scheme, Is.EqualTo("https"));
    }

    [Test]
    public void ParseServers_SiteAppliedToAllServers()
    {
        var json = BaseConfig();
        var servers = ConfigParser.ParseServers(json);
        Assert.That(servers[0].Site, Is.EqualTo("app.example.com"));
    }

    [Test]
    public void ParseServers_DefaultsPortTo443WhenAbsent()
    {
        var json = @"{
  ""site"": ""x"",
  ""servers"": [{ ""name"": ""A"", ""host"": ""1.2.3.4"", ""scheme"": ""https"" }],
  ""applications"": []
}";
        var servers = ConfigParser.ParseServers(json);
        Assert.That(servers[0].Port, Is.EqualTo(443));
    }

    [Test]
    public void ParseServers_DefaultsSchemeToHttpsWhenAbsent()
    {
        var json = @"{
  ""site"": ""x"",
  ""servers"": [{ ""name"": ""A"", ""host"": ""1.2.3.4"", ""port"": 443 }],
  ""applications"": []
}";
        var servers = ConfigParser.ParseServers(json);
        Assert.That(servers[0].Scheme, Is.EqualTo("https"));
    }

    [Test]
    public void ParseServers_UsesTimeoutMsFromHealthCheck()
    {
        var json = BaseConfig();
        var servers = ConfigParser.ParseServers(json);
        Assert.That(servers[0].TimeoutMs, Is.EqualTo(5000));
    }

    [Test]
    public void ParseServers_DefaultsTimeoutTo8000WhenAbsent()
    {
        var json = @"{
  ""site"": ""x"",
  ""servers"": [{ ""name"": ""A"", ""host"": ""1.2.3.4"" }],
  ""applications"": []
}";
        var servers = ConfigParser.ParseServers(json);
        Assert.That(servers[0].TimeoutMs, Is.EqualTo(8000));
    }

    [Test]
    public void ParseServers_ParsesMultipleServers()
    {
        var json = @"{
  ""site"": ""app.example.com"",
  ""servers"": [
    { ""name"": ""WEB-1"", ""host"": ""10.0.0.1"", ""port"": 443, ""scheme"": ""https"" },
    { ""name"": ""WEB-2"", ""host"": ""10.0.0.2"", ""port"": 8443, ""scheme"": ""https"" }
  ],
  ""applications"": []
}";
        var servers = ConfigParser.ParseServers(json);
        Assert.That(servers.Length, Is.EqualTo(2));
        Assert.That(servers[1].Name, Is.EqualTo("WEB-2"));
        Assert.That(servers[1].Host, Is.EqualTo("10.0.0.2"));
        Assert.That(servers[1].Port, Is.EqualTo(8443));
    }

    [Test]
    public void ParseServers_ThrowsWhenServersArrayMissing()
    {
        var json = @"{ ""site"": ""x"", ""applications"": [] }";
        Assert.Throws<InvalidOperationException>(() => ConfigParser.ParseServers(json));
    }

    // ── FindServer ────────────────────────────────────────────────────────────

    [Test]
    public void FindServer_FindsByNameExact()
    {
        var json = BaseConfig();
        var server = ConfigParser.FindServer(json, "WEB-1");
        Assert.That(server, Is.Not.Null);
        Assert.That(server.Name, Is.EqualTo("WEB-1"));
    }

    [Test]
    public void FindServer_FindsByNameCaseInsensitive()
    {
        var json = BaseConfig();
        var server = ConfigParser.FindServer(json, "web-1");
        Assert.That(server, Is.Not.Null);
        Assert.That(server.Name, Is.EqualTo("WEB-1"));
    }

    [Test]
    public void FindServer_ReturnsNullWhenNotFound()
    {
        var json = BaseConfig();
        Assert.That(ConfigParser.FindServer(json, "MISSING"), Is.Null);
    }

    // ── SplitObjects ──────────────────────────────────────────────────────────

    [Test]
    public void SplitObjects_SplitsMultipleTopLevelObjects()
    {
        var block = @"[{ ""a"": 1 }, { ""b"": 2 }]";
        var result = ConfigParser.SplitObjects(block);
        Assert.That(result.Count, Is.EqualTo(2));
    }

    [Test]
    public void SplitObjects_HandlesNestedObjects()
    {
        var block = @"[{ ""a"": { ""nested"": true }, ""b"": 2 }]";
        var result = ConfigParser.SplitObjects(block);
        Assert.That(result.Count, Is.EqualTo(1));
        Assert.That(result[0], Does.Contain("nested"));
    }

    [Test]
    public void SplitObjects_ReturnsEmptyListForEmptyArray()
    {
        var result = ConfigParser.SplitObjects("[]");
        Assert.That(result.Count, Is.EqualTo(0));
    }

    // ── JStr / JInt ───────────────────────────────────────────────────────────

    [Test]
    public void JStr_ExtractsStringValue()
    {
        Assert.That(ConfigParser.JStr(@"{ ""key"": ""value"" }", "key"), Is.EqualTo("value"));
    }

    [Test]
    public void JStr_ReturnsNullWhenKeyAbsent()
    {
        Assert.That(ConfigParser.JStr(@"{ ""other"": ""x"" }", "key"), Is.Null);
    }

    [Test]
    public void JInt_ExtractsIntValue()
    {
        Assert.That(ConfigParser.JInt(@"{ ""port"": 8080 }", "port", 443), Is.EqualTo(8080));
    }

    [Test]
    public void JInt_ReturnsDefaultWhenKeyAbsent()
    {
        Assert.That(ConfigParser.JInt(@"{ ""other"": 1 }", "port", 443), Is.EqualTo(443));
    }

    // ── Nvl ───────────────────────────────────────────────────────────────────

    [Test]
    public void Nvl_ReturnsFirstWhenNonEmpty()
    {
        Assert.That(ConfigParser.Nvl("a", "b"), Is.EqualTo("a"));
    }

    [Test]
    public void Nvl_ReturnsSecondWhenFirstIsNull()
    {
        Assert.That(ConfigParser.Nvl(null, "b"), Is.EqualTo("b"));
    }

    [Test]
    public void Nvl_ReturnsSecondWhenFirstIsEmpty()
    {
        Assert.That(ConfigParser.Nvl("", "b"), Is.EqualTo("b"));
    }
}
