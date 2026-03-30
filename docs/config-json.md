# config.json

Deployment configuration file. Placed in the application root alongside `check.ashx`. Not part of the release artefact — each deployment has its own copy configured for that environment.

> **Security:** `web.config` blocks all direct HTTP access to this file. It is only ever read server-side by `check.ashx`.

---

## Full example

```json
{
  "site": "myapp.example.com",
  "hosting": {
    "name": "Hosting Co",
    "logo": "https://example.com/hosting-logo.svg",
    "website": "https://hostingco.example.com"
  },
  "customer": {
    "name": "Customer Ltd",
    "logo": "https://example.com/customer-logo.svg",
    "website": "https://customerltd.example.com"
  },
  "basePath": "/live",
  "autoRefreshSeconds": 60,
  "servers": [
    { "name": "WEB-1", "host": "10.0.0.1", "port": 443, "scheme": "https" },
    { "name": "WEB-2", "host": "10.0.0.2", "port": 443, "scheme": "https" }
  ],
  "applications": [
    { "path": "/app1", "label": "Customer Portal" },
    { "path": "/api",  "label": "REST API" }
  ],
  "healthCheck": {
    "timeoutMs": 8000
  }
}
```

---

## Top-level fields

### `site`
**Type:** string — **Required**

The public hostname of the site being monitored. Used as the HTTP `Host` header on every health-check request so IIS routes to the correct virtual site, regardless of which node IP is being probed.

```json
"site": "myapp.example.com"
```

Can include an optional sub-folder path if the apps live under one:
```json
"site": "myapp.example.com/portal"
```

---

### `basePath`
**Type:** string — **Optional, default: `""`**

Path prefix prepended to every application path when building the probe URL and the dashboard display links. Set this when all your applications share a common root path on the servers.

```json
"basePath": "/live"
```

With `basePath: "/live"` and an app `path: "/Key2"`, the probed URL becomes `/live/Key2`.

Leave empty (`""`) if apps are at the root:
```json
"basePath": ""
```

---

### `autoRefreshSeconds`
**Type:** integer — **Optional, default: `60`**

How often the dashboard auto-refreshes (in seconds) when the auto-refresh toggle is enabled. The value is shown next to the toggle label (e.g. `Auto-refresh 30s`).

```json
"autoRefreshSeconds": 30
```

---

## Branding

### `hosting`
**Type:** object — **Optional**

Branding for the hosting/infrastructure company. Displayed on the **left** side of the dashboard header.

```json
"hosting": {
  "name": "Hosting Co",
  "logo": "https://example.com/hosting-logo.svg",
  "website": "https://hostingco.example.com"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | No | Company name shown as text if no logo is provided, or as the `alt` attribute on the logo image |
| `logo` | No | URL to a logo image (SVG recommended). If absent, `name` is rendered as text instead |
| `website` | No | URL opened in a new tab when the logo or name is clicked |

All three fields are optional. If the entire `hosting` object is omitted, no hosting brand slot is shown.

---

### `customer`
**Type:** object — **Optional**

Branding for the customer company. Displayed on the **right** side of the dashboard header, separated from the hosting brand by a vertical divider (the divider only appears when both brands have content).

```json
"customer": {
  "name": "Customer Ltd",
  "logo": "https://example.com/customer-logo.svg",
  "website": "https://customerltd.example.com"
}
```

Same fields as `hosting` — `name`, `logo`, `website` — all optional.

---

## `servers`
**Type:** array of objects — **Required**

Defines the backend nodes to probe. Each entry represents one physical or virtual server. The dashboard shows one column per server in the status table.

```json
"servers": [
  { "name": "WEB-1", "host": "10.0.0.1", "port": 443, "scheme": "https" },
  { "name": "WEB-2", "host": "10.0.0.2", "port": 443, "scheme": "https" }
]
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | Yes | — | Display name shown as a column header in the dashboard. Also the identifier used in `check.ashx?server=` requests |
| `host` | Yes | — | Hostname or IP address of the specific node. The TCP connection goes directly here, bypassing any load balancer or ARR proxy |
| `port` | No | `443` | TCP port to connect on |
| `scheme` | No | `"https"` | `"https"` or `"http"` |

**Why `host` and `site` are separate:** `site` is the public hostname (used for IIS virtual-host routing and the HTTP `Host` header). `host` is the node's own address (used for the TCP connection). This allows probing each node individually even when they sit behind a shared load balancer that would otherwise route all requests to whichever node it chooses.

---

## `applications`
**Type:** array of objects — **Required**

The application paths to check on each server. Each entry produces one row in the status table. Every combination of application × server is probed independently.

```json
"applications": [
  { "path": "/app1", "label": "Customer Portal" },
  { "path": "/api",  "label": "REST API" }
]
```

| Field | Required | Description |
|-------|----------|-------------|
| `path` | Yes | URL path of the application, relative to `basePath`. Must start with `/` |
| `label` | No | Human-friendly display name shown below the path in the table row |

The probed URL is built as: `{scheme}://{host}:{port}{basePath}{path}`

---

## `healthCheck`
**Type:** object — **Optional**

Controls how health-check requests are made.

```json
"healthCheck": {
  "timeoutMs": 8000
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `timeoutMs` | No | `8000` | Maximum time in milliseconds to wait for a response from any single probe request. Applies to both the initial HEAD and any GET fallback. A probe that exceeds this limit returns `"timeout"` with `ok: false` |

---

## Legacy fields (backward compatible)

The following flat fields are still supported for deployments that haven't migrated to the nested `hosting`/`customer` objects:

| Field | Replaced by |
|-------|-------------|
| `"logoHosting": "..."` | `hosting.logo` |
| `"logoCustomer": "..."` | `customer.logo` |
| `"logo": "..."` | `hosting.logo` (lowest-priority fallback) |

If both a nested object and a legacy field are present, the nested object takes precedence.
