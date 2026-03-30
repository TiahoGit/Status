# check.ashx

**File:** `check.ashx`

## Purpose

The server-side HTTP handler that the browser dashboard calls. It has two jobs:

1. **Config endpoint** (`?action=apps`) — reads `config.json` and returns a sanitised subset safe to expose to browsers (no IPs, no internal hostnames)
2. **Probe endpoint** (`?server=X&path=/app`) — performs a real HTTP health check against a specific backend node and returns the result

It is a single self-contained `.ashx` file — `ConfigParser` and `HttpProbe` are inlined at the bottom so the file deploys to IIS with no additional dependencies.

---

## Endpoints

### `GET check.ashx?action=apps`

Returns a JSON object for the browser dashboard to consume:

```json
{
  "basePath": "/live",
  "autoRefreshSeconds": 60,
  "version": "1.0.24",
  "hosting":  { "name": "...", "logo": "...", "website": "..." },
  "customer": { "name": "...", "logo": "...", "website": "..." },
  "servers": [ { "name": "APP8-N1" }, { "name": "APP8-N2" } ],
  "applications": [ { "path": "/Key2", "label": "Key2" } ]
}
```

**What is deliberately omitted:** server IPs, hostnames, ports, schemes, and the raw config content. Only the server name is exposed so the browser can reference servers in subsequent probe calls without knowing where they live.

---

### `GET check.ashx?server=APP8-N1&path=/Key2`

Probes a single app on a single server and returns:

```json
{ "ok": true,  "status": 200,           "ms": 45   }
{ "ok": false, "status": "timeout",     "ms": 8001 }
{ "ok": false, "status": "unreachable", "ms": 12   }
```

**Flow:**
1. Validates `server` and `path` parameters (rejects empty values and paths containing `..`)
2. Looks up the server by name in `config.json` — returns HTTP 403 if not found
3. Builds the target URL using `server.Host` (the specific node) with `server.Site` as the Host header
4. Delegates to `HttpProbe.Probe()` and serialises the result

---

### `GET check.ashx?debug=1` *(localhost only)*

Full diagnostic JSON — only accessible when the request originates from the server itself (`Request.IsLocal`). Returns:
- .NET version and physical paths
- Raw config content and parsed server list
- Live connectivity test results for each configured server

Returns HTTP 403 for any remote request.

---

## Request flow (probe)

```
Browser
  └─ GET check.ashx?server=APP8-N1&path=/Key2
       └─ Validate params
       └─ Read config.json
       └─ FindServer("APP8-N1") → ServerDef { Host, Site, Port, ... }
       └─ Build URL: https://app8-n1.internal:443/Key2
            Host header: public-site.example.com
       └─ HttpProbe.Probe(url, timeoutMs, hostHeader)
            └─ HEAD → fallback GET if 405/501
            └─ Follow one 301/302 redirect
       └─ Return { ok, status, ms }
```

---

## Security measures

| Concern | Mitigation |
|---------|-----------|
| Internal IPs/hostnames exposed | `?action=apps` returns server names only |
| Path traversal | `..` in `?path=` rejected with HTTP 400 |
| Unknown server names | Returns HTTP 403, not a probe attempt |
| Stack traces in errors | `ex.Message` only, never `ex.ToString()` |
| Config file accessible via HTTP | `web.config` blocks direct requests to `config.json` at two levels |
| Debug endpoint accessible remotely | `Request.IsLocal` check returns HTTP 403 for non-local requests |

---

## Dependencies (inlined)

`ConfigParser` and `HttpProbe` are defined as top-level classes at the bottom of the file. They are exact copies of `src/ConfigParser.cs` and `src/HttpProbe.cs`. This duplication is intentional — it means the entire application deploys as four files (`check.ashx`, `default.aspx`, `config.json`, `web.config`) with no compiled DLLs or App_Code directory required.

**TL;DR:** Single-file ASP.NET handler; reads config, validates the request, probes the target node directly, and returns a minimal safe JSON response to the browser.
