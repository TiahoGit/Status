# ConfigParser

**File:** `src/ConfigParser.cs` (also inlined verbatim in `check.ashx`)

## Purpose

Parses the `config.json` file into strongly-typed objects. It has no dependency on `HttpContext` or any ASP.NET types, so it can be used and unit-tested independently of IIS.

---

## Data structures

### `ServerDef`
Represents one entry from the `servers` array in config.

| Field | Type | Description |
|-------|------|-------------|
| `Name` | string | Display name (e.g. `APP8-N1`) |
| `Host` | string | Node hostname or IP — used as the TCP connection target |
| `Site` | string | Public hostname — used as the HTTP `Host` header and for SNI |
| `Port` | int | TCP port (default 443) |
| `Scheme` | string | `https` or `http` (default `https`) |
| `TimeoutMs` | int | Per-request timeout in ms (default 8000) |

### `BrandingDef`
Represents the branding configuration for one company slot (hosting or customer).

| Field | Type | Description |
|-------|------|-------------|
| `Name` | string | Company name shown as text if no logo is provided |
| `Logo` | string | URL to a logo image |
| `Website` | string | URL to navigate to when the logo or name is clicked |

---

## Methods

### Top-level scalar fields

**`ParseVersion(string json)`**
Extracts the `"version"` string from a JSON blob. Returns `null` if absent or if the input is `null`. Safe to call with the content of `version.json`.

**`ParseBasePath(string json)`**
Extracts `"basePath"`. Returns an empty string if the field is absent.

**`ParseAutoRefreshSeconds(string json)`**
Extracts `"autoRefreshSeconds"`. Returns `60` if absent.

**`ParseLogoHosting(string json)`**
Extracts `"logoHosting"`, falling back to the legacy `"logo"` top-level field for backward compatibility. Returns `null` if neither is present.

**`ParseLogoCustomer(string json)`**
Extracts `"logoCustomer"`. Does not fall back to `"logo"`. Returns `null` if absent.

---

### Branding

**`ParseBranding(string json, string key)`**
Parses the nested branding object for `key` (`"hosting"` or `"customer"`):
1. Finds the nested object `{ "name": ..., "logo": ..., "website": ... }` using `ExtractObject`
2. If `logo` is absent from the nested object, falls back to the legacy flat fields (`logoHosting` / `logoCustomer`)
3. Returns `null` if name, logo, and website are all absent

**`ExtractObject(string json, string key)` *(private)***
Finds a nested JSON object by key using a depth-counting brace walk. Handles arbitrarily nested objects correctly — unlike a simple regex match on `{[^}]*}`.

---

### Servers

**`ParseServers(string json)`**
Parses the `"servers"` array into a `ServerDef[]`. The global `"site"` and `"timeoutMs"` fields are read once and applied to every server. Throws `InvalidOperationException` if the `"servers"` array is missing entirely.

**`FindServer(string json, string name)`**
Searches the parsed servers for a match on `name`, case-insensitively. Returns `null` if not found. Used by `check.ashx` to validate the `?server=` query parameter against config before probing.

---

### JSON micro-parser

Because the project has no external JSON library dependency, three small helpers handle field extraction via regex:

**`JStr(string obj, string key)`**
Extracts a string value from a JSON fragment. The regex handles escaped characters inside strings (`\"`). Returns `null` if the key is absent.

**`JInt(string obj, string key, int def)`**
Extracts an integer value. Returns `def` if the key is absent.

**`SplitObjects(string block)`**
Splits a JSON array string into individual object strings by counting `{` and `}` depth. Returns an empty list for `[]`. Correctly handles nested objects (e.g. a server entry that itself contained a sub-object).

**`Nvl(string a, string b)`**
Returns `a` if non-null and non-empty, otherwise `b`. Used as a null-coalescing helper throughout parsing.

---

## Subtle points

- **No `System.Text.Json` or `Newtonsoft.Json`** — parsing is done with regex + brace counting to keep the deployment zero-dependency and .NET 4.0 compatible.
- **`Unescape`** wraps `Regex.Unescape`, converting JSON escape sequences (e.g. `\"`, `\\`) back to their literal characters.
- **Dual copy** — this file is the canonical source for unit tests. An identical copy is inlined at the bottom of `check.ashx` so the handler deploys as a single file. Any change here must be mirrored there.

**TL;DR:** Stateless utility class that reads `config.json` text and returns typed objects — no I/O, no ASP.NET, fully testable.
