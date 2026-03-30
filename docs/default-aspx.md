# default.aspx

**File:** `default.aspx`

## Purpose

The single-page browser dashboard. Loads application health status by calling `check.ashx` and renders the results as a live status table. No server-side rendering is used — the `.aspx` extension is only so IIS serves the file; all logic is client-side JavaScript.

---

## Page structure

```
header
  ├─ brand-hosting slot  (logo or name, links to website)
  ├─ brand-text          ("INFRASTRUCTURE" label + "Application Status" h1)
  ├─ brand-divider       (vertical separator, hidden if only one brand)
  └─ brand-customer slot (logo or name, links to website)
  └─ header-right
       ├─ last-checked timestamp
       ├─ theme toggle button (moon/sun icon)
       ├─ refresh button
       └─ auto-refresh toggle + label

summary-bar  (4 cards: Applications / All healthy / Degraded / Down)

table
  thead  (Application | SERVER-1 | SERVER-2 | … | Overall)
  tbody  (one row per app, one cell per server + overall badge)

footer  (version | current URL)
```

---

## JavaScript — key functions

### `loadConfig()`
Fetches `check.ashx?action=apps` and validates the response. Normalises `basePath` (strips trailing slash). Called at startup and on each refresh.

### `buildHeader(servers)`
Dynamically writes the `<thead>` row with one column per server. Called after config loads.

### `buildRows(apps, servers)`
Writes all `<tbody>` rows. Each server cell gets `id="c-{appIndex}-{serverIndex}"` for targeted updates later, and a `data-server` attribute used by the mobile CSS card layout to render server name labels.

### `probeViaProxy(serverName, appPath)`
Fetches `check.ashx?server=X&path=Y` with a 10-second client-side abort timeout. Maps the JSON response to `{ ok, code, elapsed }`. Handles proxy-level errors (non-200 from `check.ashx` itself) and network errors from `AbortController`.

### `renderCell(id, result)`
Updates a single server/app cell with a coloured pill:

| Condition | Pill class | Colour |
|-----------|-----------|--------|
| `ok: true`, status not 401/403 | `p-ok` | Green |
| `ok: true`, status 401 or 403 | `p-auth` | Amber |
| `ok: false`, code `"timeout"` | `p-warn` | Amber |
| `ok: false`, other | `p-err` | Red |
| Pending | `p-pend` | Grey |

### `renderOverall(id, row)`
Aggregates all server results for one app row into an Overall badge: `OK` (all ok), `Partial` (some ok), or `Down` (none ok).

### `updateSummary(matrix)`
Counts apps into the four summary cards after each probe completes. Runs incrementally — each probe result triggers a re-count so the numbers update in real time as checks arrive.

### `runChecks()`
Main orchestration function. Fires all `appCount × serverCount` probes in parallel using `Promise.allSettled`. Disables the Refresh button while running.

### `renderBrandSlot(id, branding)`
Renders one brand slot (hosting or customer). If `logo` is set, renders `<img>`; otherwise renders `<span class="brand-name">` with the company name. Wraps the content in `<a>` if `website` is set.

---

## Theming

Two CSS themes — dark (default) and light — defined as CSS variable sets on `[data-theme="dark"]` and `[data-theme="light"]`. The active theme is stored in `localStorage` under key `jaama-status-theme` and restored on page load. The theme toggle button switches between them.

---

## Responsive layout

- **≥ 768px (desktop):** standard flex header + multi-column table
- **< 767px (mobile):** header stacks vertically; controls become a horizontal strip; table switches to a card-per-app layout with server name labels rendered via CSS `::before { content: attr(data-server) }`

---

## Auto-refresh

When enabled, `setInterval(runChecks, secs * 1000)` is set using the `autoRefreshSeconds` value from config (default 60s). The interval is cleared and re-set each time the toggle changes to pick up any config change.

---

## Subtle points

- **Probe parallelism** — all probes are fired simultaneously; the UI updates cell-by-cell as each response arrives rather than waiting for all to complete
- **`joinPath`** — combines `basePath` and `app.path` safely, normalising double slashes and ensuring a leading `/`
- **No build step** — vanilla ES5-compatible JavaScript, no modules, no transpilation; runs directly in any browser

**TL;DR:** Single-page dashboard that fires parallel health-check requests through `check.ashx` and renders live status pills, updating the UI incrementally as each result arrives.
