# Tasks

## Completed

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
