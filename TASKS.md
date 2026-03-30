# Tasks

## Outstanding

## Completed

### #9 — Mobile-responsive layout for header and app table
- `default.aspx` / `test-harness/index.html`: all changes scoped to `@media(max-width:767px)` — desktop unchanged
- Header stacks vertically; controls become a horizontal strip (theme toggle + refresh left, auto-refresh right, last-checked full-width below)
- `h1` scaled to 18px, logos capped at 28px, body padding reduced to 1rem
- App table replaced with card-per-app layout: `thead` hidden, each row becomes a bordered card with server results as labelled rows (`data-server` + CSS `::before`) and an Overall row at the bottom
- Pills drop fixed `min-width` on mobile; app path wraps instead of forcing overflow

### #8 — Company branding: name, logo fallback, and website link
- `config.json` / `config.sample.json`: added nested `hosting` and `customer` objects with `name`, `logo`, `website`
- `src/ConfigParser.cs` / inlined in `check.ashx`: added `BrandingDef` class, `ParseBranding()`, `ExtractObject()` with legacy fallback to `logoHosting`/`logoCustomer`
- `check.ashx`: exposes `hosting` and `customer` objects via `?action=apps`
- `default.aspx`: header brand slots render logo if present, name as text fallback, wrapped in link if website set
- `test-harness/index.html`: mock config and rendering updated to match
- `tests/ConfigParserTests.cs`: 7 new tests (59 total)

### #1 — Make logo configurable in config.json
Add a logo configuration option to `config.json` so the logo URL (currently hardcoded to Jaama's CDN URL in `default.aspx`) can be specified in config instead. The `check.ashx?action=apps` endpoint should expose the logo URL to the browser, and `default.aspx` should use it dynamically.

### #7 — Add version number to project and display in footer
- `config.json` / `config.sample.json`: added `"version": "1.0.0"` as the single source of truth
- `App_Code/ConfigParser.cs`: added `ParseVersion(string json)` returning null if absent
- `check.ashx`: exposes `version` via `?action=apps` response
- `default.aspx`: footer shows `v1.0.0` loaded from config; hidden if version not set
- `test-harness/index.html`: mock config includes version; footer updated to match
- `tests/ConfigParserTests.cs`: 3 new tests covering value, absent, and pre-release label

### #5 — Create sample config and test harness for manual UI verification
- `config.sample.json`: realistic sample with `logoHosting`, `logoCustomer`, 2 servers, 6 apps
- `test-harness/index.html`: standalone dashboard — open directly in a browser, no IIS needed. Overrides `fetch()` to return mock data covering every pill state (200, 401, timeout, unreachable, 500, 404) and both logos via inline SVG data URIs. Includes a "test harness" badge in the header so it's visually distinct from production.

### #4 — Write unit tests for the health check probe logic
Extracted probe logic from `check.ashx` into `App_Code/HttpProbe.cs`. Tests in `tests/HttpProbeTests.cs` use a real local `HttpListener` server (no mocks). Covers: 200/401/403/404/500 classification, HEAD→GET fallback (405/501), redirect following (301/302), unreachable, timeout, and elapsed time reporting.

Run with: `cd tests && dotnet test`

### #6 — Security review — audit what is exposed by each endpoint
- Removed stack trace (`ex.ToString()`) from config error response — was leaking file paths
- Removed `url` and `detail` fields from browser-facing probe responses — neither used by the UI; `detail` could expose internal error messages with IPs
- Rejected `..` in the `path` query parameter
- `web.config`: suppressed `X-Powered-By`, `X-AspNet-Version` (`enableVersionHeader="false"`), and `Server` (`removeServerHeader="true"`) headers
- `web.config`: added `<location path="config.json">` deny as a second layer on top of the existing `denyUrlSequences` rule

### #3 — Write unit tests for check.ashx config parsing
Extracted config parsing logic from `check.ashx` into `App_Code/ConfigParser.cs`. NUnit test project at `tests/ConfigParser.Tests.csproj` with 30 tests covering: logoHosting/logoCustomer parsing, legacy logo fallback, basePath, autoRefreshSeconds, server parsing (name, host, port, scheme, timeoutMs, site, defaults), FindServer (case-insensitive), SplitObjects (nested objects), JStr, JInt, Nvl.

Run with: `cd tests && dotnet test`

### #2 — Support dual logos — hosting and customer
Extend the logo config to support two logos: one for the hosting/infrastructure brand and one for the customer brand. Both should be configurable in `config.json`. The dashboard header should display both, with appropriate layout (e.g. hosting logo on the left, customer logo on the right, or side-by-side in the brand area).

**Depends on:** #1
