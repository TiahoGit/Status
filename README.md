# Status

A self-hosted application health dashboard for IIS. Polls each configured application across multiple servers and displays live status pills with HTTP response codes and latency.

## Features

- Polls every app × server combination in parallel via a server-side proxy
- HEAD → GET fallback; follows a single redirect (IIS `/app` → `/app/`)
- 401/403 responses treated as "up but auth-gated" (amber, not red)
- Dark/light theme with localStorage persistence
- Configurable auto-refresh interval
- Debug endpoint (`?debug=1`, localhost-only) for diagnosing config and connectivity

## Files

| File | Purpose |
|------|---------|
| `default.aspx` | Dashboard UI — HTML/CSS/JS, no build step |
| `check.ashx` | C# HTTP handler — proxies health probes, serves config to browser |
| `config.json` | Server and application configuration |
| `web.config` | IIS settings — default document, no-cache headers, blocks direct access to `config.json` |

## Requirements

- IIS with ASP.NET 4.0+ enabled
- Application pool identity must have read access to the physical path
- No NuGet packages or build step required

## Deployment

1. Copy all four files into an IIS virtual directory or application.
2. Edit `config.json` (see below).
3. Browse to the directory — `default.aspx` loads automatically.

## Configuration

Edit `config.json`:

```json
{
  "site": "myapp.example.com",
  "basePath": "",
  "autoRefreshSeconds": 60,
  "servers": [
    { "name": "WEB-1", "host": "10.0.0.1", "port": 443, "scheme": "https" },
    { "name": "WEB-2", "host": "10.0.0.2", "port": 443, "scheme": "https" }
  ],
  "applications": [
    { "path": "/app1", "label": "Customer Portal" },
    { "path": "/app2", "label": "Admin Panel" }
  ],
  "healthCheck": {
    "timeoutMs": 8000
  }
}
```

| Field | Description |
|-------|-------------|
| `site` | Public hostname used for TLS SNI and the `Host:` header on all probes |
| `basePath` | Optional path prefix prepended to every application path before probing |
| `autoRefreshSeconds` | Interval for the auto-refresh toggle (default `60`) |
| `servers[].name` | Display name shown in the dashboard column header |
| `servers[].host` | IP address (or hostname) of the node — TCP connections are pinned here, bypassing DNS/ARR |
| `servers[].port` | TCP port (default `443`) |
| `servers[].scheme` | `https` or `http` (default `https`) |
| `applications[].path` | URL path to probe (e.g. `/myapp`) |
| `applications[].label` | Optional human-readable label shown below the path |
| `healthCheck.timeoutMs` | Per-probe timeout in milliseconds (default `8000`) |

> `config.json` is never sent to the browser. `check.ashx?action=apps` returns a sanitised subset (server names, app paths/labels) with no IPs or hostnames.

## How It Works

```
Browser                          IIS (check.ashx)              Target node
  |                                     |                            |
  |-- GET check.ashx?action=apps ------>|                            |
  |<- { servers, applications } --------|                            |
  |                                     |                            |
  |-- GET check.ashx?server=X&path=/y ->|                            |
  |                                     |-- HEAD https://site/y ---->|
  |                                     |<- 200 OK (45 ms) ----------|
  |<- { ok:true, status:200, ms:45 } ---|                            |
```

1. On load (and on each refresh) the browser calls `check.ashx?action=apps` to fetch servers and applications.
2. For each app × server pair the browser calls `check.ashx?server=NAME&path=/path`.
3. `check.ashx` looks up the server in `config.json`, builds the probe URL using `site` as the hostname, pins the TCP connection to `host` (the node IP), then returns a JSON result.
4. The browser renders each cell as a coloured pill.

## Status Indicators

| Colour | Meaning |
|--------|---------|
| Green | HTTP 2xx (or 3xx after redirect) |
| Amber | HTTP 401 / 403 (auth-gated but reachable), or timeout |
| Red | Network unreachable, or HTTP 4xx / 5xx |
| Grey | Pending / not yet checked |

## Debug Endpoint

Accessible **from the server only** (localhost):

```
https://your-site/Status/check.ashx?debug=1
```

Returns full diagnostic JSON: .NET version, resolved config path, parsed server list (including IPs), and a live connectivity test to each node.

## Security Notes

- `config.json` is blocked from direct browser access by `web.config` (`denyUrlSequences`).
- The `?debug=1` endpoint is restricted to `Request.IsLocal` (server loopback only).
- TLS certificate validation is intentionally disabled in `check.ashx` to support internal/self-signed certificates on node IPs. This is by design for infrastructure monitoring.
