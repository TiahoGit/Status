# Tasks

## Pending

### #1 — Make logo configurable in config.json
Add a logo configuration option to `config.json` so the logo URL (currently hardcoded to Jaama's CDN URL in `default.aspx`) can be specified in config instead. The `check.ashx?action=apps` endpoint should expose the logo URL to the browser, and `default.aspx` should use it dynamically.

---

### #2 — Support dual logos — hosting and customer
Extend the logo config to support two logos: one for the hosting/infrastructure brand and one for the customer brand. Both should be configurable in `config.json`. The dashboard header should display both, with appropriate layout (e.g. hosting logo on the left, customer logo on the right, or side-by-side in the brand area).

**Depends on:** #1
