# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Workflow

- **Never commit directly to `main`.** All changes must go through a feature branch and PR.
- Work on `dev/claude` or a dedicated branch, then open a PR targeting `main`.

## Running Tests

```bash
cd tests
dotnet test
```

Requires .NET 8 SDK. To run a single test:

```bash
cd tests
dotnet test --filter "FullyQualifiedName~TestMethodName"
```

## Architecture

**Status** is a self-hosted IIS application health dashboard. It polls configured apps across multiple servers in parallel and displays live HTTP status/latency in a browser UI.

### Production Deployment (4 files)

The entire deployable application is just these files copied to an IIS virtual directory:
- `default.aspx` — Dashboard UI (HTML/CSS/JS, no framework)
- `check.ashx` — C# `IHttpHandler` serving 3 endpoints:
  - `?action=apps` — Sanitized config for the UI (server names, paths, logos, version)
  - `?server=X&path=/y` — Health probe result for one app
  - `?debug=1` — Full diagnostic JSON (localhost only)
- `config.json` — Server/app/branding configuration (blocked from direct HTTP access by `web.config`)
- `web.config` — IIS settings (security headers, request filtering, cache control)

### Intentional Code Duplication

`src/ConfigParser.cs` and `src/HttpProbe.cs` contain the shared logic, but **their classes are also inlined verbatim inside `check.ashx`**. This is by design: production deployment requires no `App_Code` directory or separate `.cs` files — just the single `check.ashx`. When modifying either source file, the corresponding inlined copy in `check.ashx` must be updated manually to stay in sync.

### Zero External Dependencies

The production code has no NuGet packages. JSON is parsed with regex (`JStr`, `JInt` helpers in `ConfigParser`). HTTP probes use synchronous `HttpWebRequest` (.NET 4.0 compatible). The test project (`tests/`) uses NUnit 3 and targets .NET 8.

### Key Behaviors in HttpProbe

- Sends HEAD first; falls back to GET on 405/501
- Follows one redirect (301/302)
- Pins TCP connections to the resolved node IP (bypasses DNS/ARR load balancing)
- Enforces TLS 1.2; accepts self-signed certificates (intentional for internal infrastructure)

### Configuration Schema

```json
{
  "site": "public-hostname",
  "basePath": "/optional/path",
  "autoRefreshSeconds": 60,
  "servers": [{"name": "WEB-1", "host": "10.0.0.1", "port": 443, "scheme": "https"}],
  "applications": [{"path": "/app1", "label": "App Label"}],
  "healthCheck": {"timeoutMs": 8000},
  "hosting": {"name": "Host Co", "logo": "https://...", "website": "https://..."},
  "customer": {"name": "Customer Ltd", "logo": "https://...", "website": "https://..."}
}
```

The legacy `"logo"` field (top-level) falls back to `"logoHosting"` for backward compatibility.

### Test Harness

`test-harness/index.html` is a standalone browser file that overrides `fetch()` with mock data to test all UI pill states without a running server.
