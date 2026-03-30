# HttpProbe

**File:** `src/HttpProbe.cs` (also inlined verbatim in `check.ashx`)

## Purpose

Makes a synchronous HTTP request to a target application URL and returns a structured result indicating whether the app is reachable, what HTTP status code it returned, and how long it took. Designed to bypass load balancers and hit a specific backend node directly.

---

## Data structures

### `Result` (public)
Returned to callers of `Probe()`.

| Field | Type | Description |
|-------|------|-------------|
| `Ok` | bool | `true` if the app is considered healthy (see status classification below) |
| `NetworkError` | bool | `true` if the connection failed entirely (timeout, unreachable, DNS failure) |
| `StatusCode` | int | HTTP status code; `0` when `NetworkError` is `true` |
| `ErrorCode` | string | `"timeout"`, `"unreachable"`, or `"error"` when `NetworkError` is `true`; `null` otherwise |
| `Ms` | long | Elapsed time in milliseconds from request start to response received |

### `RawResult` (private)
Internal intermediate result that also carries the `Location` header needed for redirect following.

---

## Methods

### `Probe(string url, int timeoutMs, string hostHeader, int port)`

The single public entry point. Orchestrates the full probe sequence:

1. **HEAD first** — sends a HEAD request (lighter than GET, no response body)
2. **GET fallback** — if the server returns `405 Method Not Allowed` or `501 Not Implemented`, retries with GET
3. **One redirect follow** — if the response is `301` or `302` with a `Location` header, follows it with a GET request. Only one level of redirect is followed (IIS commonly redirects `/app` → `/app/`)
4. Returns the final `Result`

**Parameters:**
- `url` — the full URL to request; the hostname should be the node's own DNS name or IP so the TCP connection goes directly to that server, bypassing any load balancer
- `timeoutMs` — per-request timeout; the total wall time could be up to `2 × timeoutMs` if HEAD times out and GET is retried
- `hostHeader` — if set, overrides the HTTP `Host` header (and therefore IIS virtual-host routing) to the public site hostname; allows hitting a node by its private name/IP while IIS still routes correctly
- `port` — reserved; currently unused

---

### `DoRequest(string url, string method, int timeoutMs, string hostHeader, int port)` *(private)*

Executes a single HTTP request and returns a `RawResult`. Key behaviours:

- **TLS 1.2 forced** — `ServicePointManager.SecurityProtocol` is set to TLS 1.2 + TLS 1.1 because .NET 4.0's default is SSL 3.0/TLS 1.0, which most modern servers reject
- **Certificate validation disabled** — the `ServerCertificateValidationCallback` always returns `true`, accepting self-signed and internal CA certificates used on infrastructure nodes
- **No auto-redirect** — `AllowAutoRedirect = false` ensures redirects are handled manually by `Probe()` so the redirect target URL is visible
- **Host header override** — `req.Host = hostHeader` overrides the Host header independently of the URL, enabling node-direct probing with correct IIS virtual-host routing
- **WebException handling** — if the server returns an HTTP error status (4xx/5xx), `WebException` is thrown but `ex.Response` is populated; the status code is extracted and returned as a non-network-error result. If `ex.Response` is null (connection refused, DNS failure, timeout), it becomes a network error with `"timeout"` or `"unreachable"`

---

### `ToResult(RawResult r)` *(private)*

Converts a `RawResult` to the public `Result`, applying the **health classification rule**:

| Status | `Ok` |
|--------|------|
| 200–399 | `true` |
| 401 Unauthorized | `true` — app is up, just requires a login |
| 403 Forbidden | `true` — app is up, just access-restricted |
| 4xx (other) / 5xx | `false` |
| Network error | `false` |

401 and 403 are treated as healthy because the app is running and responding — the user just isn't authenticated. A 404 or 500 indicates something is genuinely wrong with the app.

---

## Subtle points

- **Dual copy** — identical to the inlined copy at the bottom of `check.ashx`. Any change here must be mirrored there.
- **TLS global state** — `ServicePointManager` settings are process-wide. Setting `SecurityProtocol` and `ServerCertificateValidationCallback` on every request is intentional for .NET 4.0 compatibility, but would be a concern in a multi-tenant process.
- **Redirect host pinning** — when following a redirect, the `Location` URL is used as-is, which may point to the public hostname rather than the node. The `hostHeader` is still passed so the Host header remains correct.
- **Elapsed time** — measured with `Stopwatch` from just before `WebRequest.Create` to just after the response object is received (not after the body is read, since HEAD returns no body and GET body is not consumed).

**TL;DR:** Sends HEAD (falling back to GET) to a specific backend node URL, follows one redirect, and returns whether the app is healthy along with the HTTP status code and response time.
