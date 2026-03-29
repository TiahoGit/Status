# Tasks

## Completed

### #1 — Make logo configurable in config.json
Add a logo configuration option to `config.json` so the logo URL (currently hardcoded to Jaama's CDN URL in `default.aspx`) can be specified in config instead. The `check.ashx?action=apps` endpoint should expose the logo URL to the browser, and `default.aspx` should use it dynamically.

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
