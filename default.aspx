<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Application Status &mdash; Jaama</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@300;400;500&display=swap');
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}

/* ── Dark theme (default) ── */
[data-theme="dark"]{
  --bg:#0b0e14;--surface:#131720;--surface2:#1a2030;
  --border:rgba(255,255,255,0.07);--border-strong:rgba(255,255,255,0.14);
  --text:#e2e8f4;--muted:#6b7a99;--accent:#3b82f6;
  --ok:#22c55e;--ok-bg:rgba(34,197,94,.10);--ok-bd:rgba(34,197,94,.28);
  --warn:#f59e0b;--warn-bg:rgba(245,158,11,.10);--warn-bd:rgba(245,158,11,.28);
  --err:#ef4444;--err-bg:rgba(239,68,68,.10);--err-bd:rgba(239,68,68,.28);
  --pend-bg:rgba(107,122,153,.10);--pend-bd:rgba(107,122,153,.20);
  --logo-fill:#ffffff;
}

/* ── Light theme ── */
[data-theme="light"]{
  --bg:#f4f5f7;--surface:#ffffff;--surface2:#eef0f3;
  --border:rgba(0,0,0,0.08);--border-strong:rgba(0,0,0,0.15);
  --text:#111827;--muted:#6b7280;--accent:#2563eb;
  --ok:#16a34a;--ok-bg:rgba(22,163,74,.08);--ok-bd:rgba(22,163,74,.25);
  --warn:#d97706;--warn-bg:rgba(217,119,6,.08);--warn-bd:rgba(217,119,6,.25);
  --err:#dc2626;--err-bg:rgba(220,38,38,.08);--err-bd:rgba(220,38,38,.25);
  --pend-bg:rgba(107,114,128,.08);--pend-bd:rgba(107,114,128,.18);
  --logo-fill:#1a1a2e;
}

:root{--font:'IBM Plex Sans',sans-serif;--mono:'IBM Plex Mono',monospace}

body{background:var(--bg);color:var(--text);font-family:var(--font);font-size:14px;min-height:100vh;padding:2rem 1.5rem 4rem;transition:background .2s,color .2s}
.layout{max-width:1080px;margin:0 auto}

/* ── header ── */
header{display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:2rem;padding-bottom:1.25rem;border-bottom:1px solid var(--border);gap:1rem;flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:14px}
.brand-logo{flex-shrink:0;height:36px;width:auto;transition:filter .2s}
/* Dark logo SVG is white-on-transparent — invert to black for light mode */
[data-theme="light"]  .brand-logo{filter:invert(1)}
[data-theme="dark"]   .brand-logo{filter:none}
.brand-text{display:flex;flex-direction:column;gap:3px}
.brand-divider{width:1px;height:36px;background:var(--border-strong);flex-shrink:0}
.brand-sub{font-family:var(--mono);font-size:11px;color:var(--muted);letter-spacing:.12em;text-transform:uppercase}
h1{font-size:22px;font-weight:300;letter-spacing:-.02em}

.header-right{display:flex;flex-direction:column;align-items:flex-end;gap:6px}
.header-controls{display:flex;align-items:center;gap:8px}
.last-checked{font-family:var(--mono);font-size:11px;color:var(--muted)}

/* buttons */
.btn{background:var(--surface2);border:1px solid var(--border-strong);color:var(--text);font-family:var(--mono);font-size:11px;padding:5px 12px;border-radius:4px;cursor:pointer;letter-spacing:.05em;transition:border-color .15s,background .15s,color .15s}
.btn:hover{background:var(--surface);border-color:var(--accent)}
.btn:disabled{opacity:.4;cursor:not-allowed}

/* theme toggle button */
.theme-btn{background:var(--surface2);border:1px solid var(--border-strong);color:var(--muted);width:30px;height:30px;border-radius:4px;cursor:pointer;display:flex;align-items:center;justify-content:center;transition:border-color .15s,background .15s,color .15s;flex-shrink:0}
.theme-btn:hover{border-color:var(--accent);color:var(--text)}
.icon-moon,.icon-sun{display:none}
[data-theme="dark"]  .icon-moon{display:block}
[data-theme="light"] .icon-sun {display:block}

/* auto-refresh toggle */
.auto-row{display:flex;align-items:center;gap:8px}
.toggle-switch{position:relative;width:32px;height:18px;flex-shrink:0}
.toggle-switch input{opacity:0;width:0;height:0}
.toggle-track{position:absolute;inset:0;background:var(--surface2);border:1px solid var(--border-strong);border-radius:9px;cursor:pointer;transition:background .2s}
.toggle-track::after{content:'';position:absolute;top:2px;left:2px;width:12px;height:12px;border-radius:50%;background:var(--muted);transition:transform .2s,background .2s}
.toggle-switch input:checked + .toggle-track{background:var(--accent);border-color:var(--accent)}
.toggle-switch input:checked + .toggle-track::after{transform:translateX(14px);background:#fff}
.toggle-label{font-family:var(--mono);font-size:10px;color:var(--muted);letter-spacing:.08em;text-transform:uppercase}

/* ── summary cards ── */
.summary-bar{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:1.75rem}
.sc{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:.875rem 1rem;transition:background .2s,border-color .2s}
.sc .sl{font-family:var(--mono);font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-bottom:4px}
.sc .sv{font-size:24px;font-weight:300;letter-spacing:-.03em}
.v-ok{color:var(--ok)}.v-err{color:var(--err)}.v-warn{color:var(--warn)}.v-neutral{color:var(--muted)}

/* ── banners ── */
.banner{border-radius:6px;padding:.7rem 1rem;font-size:13px;margin-bottom:1.25rem;display:none;font-family:var(--mono);line-height:1.5}
.b-err {background:var(--err-bg); border:1px solid var(--err-bd); color:var(--err)}
.b-warn{background:var(--warn-bg);border:1px solid var(--warn-bd);color:var(--warn)}

/* ── table ── */
.table-wrap{overflow-x:auto;margin-bottom:2rem}
table{width:100%;border-collapse:collapse;font-size:13px}
thead th{font-family:var(--mono);font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);padding:.6rem 1rem;border-bottom:1px solid var(--border-strong);text-align:left;white-space:nowrap;background:var(--surface);transition:background .2s}
thead th.col-srv{text-align:center;min-width:148px}
thead th.col-ov{text-align:center;width:84px}
tbody tr{border-bottom:1px solid var(--border);transition:background .12s}
tbody tr:hover{background:var(--surface)}
tbody tr:last-child{border-bottom:none}
td{padding:.65rem 1rem;vertical-align:middle}
.td-app{font-family:var(--mono);font-size:12px;white-space:nowrap}
.td-app a{color:var(--text);text-decoration:none}
.td-app a:hover{color:var(--accent)}
.app-label{display:block;font-family:var(--font);font-size:11px;color:var(--muted);margin-top:2px;font-weight:400}
.td-srv{text-align:center}.td-ov{text-align:center}

/* ── pills ── */
.pill{display:inline-flex;align-items:center;gap:5px;font-family:var(--mono);font-size:11px;padding:3px 9px;border-radius:4px;border:1px solid transparent;white-space:nowrap;min-width:110px;justify-content:center}
.p-ok  {background:var(--ok-bg);  border-color:var(--ok-bd);  color:var(--ok)}
.p-auth{background:var(--warn-bg);border-color:var(--warn-bd);color:var(--warn)}
.p-err {background:var(--err-bg); border-color:var(--err-bd); color:var(--err)}
.p-warn{background:var(--warn-bg);border-color:var(--warn-bd);color:var(--warn)}
.p-pend{background:var(--pend-bg);border-color:var(--pend-bd);color:var(--muted)}
.pdot{width:6px;height:6px;border-radius:50%;flex-shrink:0}
.p-ok   .pdot{background:var(--ok)}
.p-auth .pdot{background:var(--warn)}
.p-err  .pdot{background:var(--err)}
.p-warn .pdot{background:var(--warn)}
.p-pend .pdot{background:var(--muted);opacity:.5}
.pms{opacity:.55;font-size:10px}

/* ── overall badge ── */
.ob{font-family:var(--mono);font-size:10px;letter-spacing:.08em;text-transform:uppercase;padding:3px 8px;border-radius:4px;display:inline-block;border:1px solid transparent}
.ob-ok  {background:var(--ok-bg);  border-color:var(--ok-bd);  color:var(--ok)}
.ob-err {background:var(--err-bg); border-color:var(--err-bd); color:var(--err)}
.ob-warn{background:var(--warn-bg);border-color:var(--warn-bd);color:var(--warn)}
.ob-pend{background:var(--pend-bg);border-color:var(--pend-bd);color:var(--muted)}

/* ── spinner ── */
.spinner{width:13px;height:13px;border-radius:50%;border:2px solid var(--border-strong);border-top-color:var(--accent);animation:spin .7s linear infinite;flex-shrink:0}
@keyframes spin{to{transform:rotate(360deg)}}
.loading-msg{display:flex;align-items:center;gap:10px;padding:1.5rem 1rem;color:var(--muted);font-family:var(--mono);font-size:12px}

/* ── footer ── */
footer{margin-top:2.5rem;padding-top:1.25rem;border-top:1px solid var(--border);display:flex;justify-content:space-between;flex-wrap:wrap;gap:.5rem}
footer span{font-family:var(--mono);font-size:10px;color:var(--muted)}

@media(max-width:640px){.summary-bar{grid-template-columns:1fr 1fr}}
</style>
</head>
<body>
<div class="layout">

<header>
  <div class="brand">
    <img id="logo-hosting" class="brand-logo" src="" alt="" style="display:none">
    <div class="brand-text">
      <span class="brand-sub">Infrastructure</span>
      <h1>Application Status</h1>
    </div>
    <div class="brand-divider" id="logo-divider" style="display:none"></div>
    <img id="logo-customer" class="brand-logo" src="" alt="" style="display:none">
  </div>

  <div class="header-right">
    <span class="last-checked" id="last-checked">Not yet checked</span>
    <div class="header-controls">
      <button class="theme-btn" id="theme-btn" onclick="toggleTheme()" title="Toggle light/dark mode">
        <!-- Moon icon (shown in dark mode — click to go light) -->
        <svg class="icon-moon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
        </svg>
        <!-- Sun icon (shown in light mode — click to go dark) -->
        <svg class="icon-sun" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="5"/>
          <line x1="12" y1="1"  x2="12" y2="3"/>
          <line x1="12" y1="21" x2="12" y2="23"/>
          <line x1="4.22" y1="4.22"  x2="5.64" y2="5.64"/>
          <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/>
          <line x1="1"  y1="12" x2="3"  y2="12"/>
          <line x1="21" y1="12" x2="23" y2="12"/>
          <line x1="4.22"  y1="19.78" x2="5.64"  y2="18.36"/>
          <line x1="18.36" y1="5.64"  x2="19.78" y2="4.22"/>
        </svg>
      </button>
      <button class="btn" id="refresh-btn" onclick="runChecks()">&#8635; Refresh</button>
    </div>
    <div class="auto-row">
      <label class="toggle-switch">
        <input type="checkbox" id="auto-toggle" onchange="toggleAuto()">
        <span class="toggle-track"></span>
      </label>
      <span class="toggle-label" id="auto-label">Auto-refresh off</span>
    </div>
  </div>
</header>

<div class="summary-bar">
  <div class="sc"><div class="sl">Applications</div><div class="sv v-neutral" id="sum-total">&#8212;</div></div>
  <div class="sc"><div class="sl">All healthy</div><div class="sv v-ok"      id="sum-ok">&#8212;</div></div>
  <div class="sc"><div class="sl">Degraded</div>   <div class="sv v-warn"    id="sum-warn">&#8212;</div></div>
  <div class="sc"><div class="sl">Down</div>        <div class="sv v-err"     id="sum-err">&#8212;</div></div>
</div>

<div class="banner b-err"  id="banner-err"></div>
<div class="banner b-warn" id="banner-warn"></div>

<div class="table-wrap">
  <table>
    <thead><tr id="thead-row">
      <th>Application</th>
      <th class="col-ov">Overall</th>
    </tr></thead>
    <tbody id="tbody">
      <tr><td colspan="10"><div class="loading-msg"><div class="spinner"></div>Loading&#8230;</div></td></tr>
    </tbody>
  </table>
</div>

<footer>
  <span id="footer-host"></span>
</footer>

</div>
<script>
(function () {

  var CFG = null;
  var autoTimer = null;
  var running = false;

  // ── Theme ──────────────────────────────────────────────────────────────────
  function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    try { localStorage.setItem('jaama-status-theme', theme); } catch(e) {}
  }

  function toggleTheme() {
    var current = document.documentElement.getAttribute('data-theme');
    applyTheme(current === 'dark' ? 'light' : 'dark');
  }

  // Restore saved theme on load
  (function() {
    try {
      var saved = localStorage.getItem('jaama-status-theme');
      if (saved === 'light' || saved === 'dark') applyTheme(saved);
    } catch(e) {}
  }());

  // ── Path helper ────────────────────────────────────────────────────────────
  function joinPath(base, path) {
    var b = (base || '').replace(/\/+$/, '');
    var p = path ? (path.charAt(0) === '/' ? path : '/' + path) : '';
    return (b + p).replace(/\/\//g, '/') || '/';
  }

  // ── Load config from server ────────────────────────────────────────────────
  async function loadConfig() {
    var r = await fetch('./check.ashx?action=apps&_nc=' + Date.now(), { cache: 'no-store' });
    if (!r.ok) throw new Error('check.ashx?action=apps returned HTTP ' + r.status);
    var d = await r.json();
    if (d.error) throw new Error(d.error);
    if (!Array.isArray(d.servers)      || !d.servers.length)      throw new Error('"servers" missing from app config');
    if (!Array.isArray(d.applications) || !d.applications.length) throw new Error('"applications" missing from app config');
    d.basePath = (d.basePath || '').replace(/\/+$/, '');

    // Derive site path prefix from current URL (e.g. /test/Status/default.aspx -> /test)
    // Used ONLY for display links — probe paths must NOT include this prefix
    // as the backend nodes are not aware of the front-end routing path
    var loc = window.location.pathname;
    var statusIdx = loc.toLowerCase().lastIndexOf('/status/');
    if (statusIdx === -1) statusIdx = loc.toLowerCase().lastIndexOf('/status');
    d.sitePrefix = statusIdx > 0 ? loc.substring(0, statusIdx).replace(/\/+$/, '') : '';

    return d;
  }

  // ── Table building ─────────────────────────────────────────────────────────
  function buildHeader(servers) {
    var row = document.getElementById('thead-row');
    var h = '<th>Application</th>';
    servers.forEach(function (s) {
      h += '<th class="col-srv">' + esc(s.name) + '</th>';
    });
    h += '<th class="col-ov">Overall</th>';
    row.innerHTML = h;
  }

  function buildRows(apps, servers) {
    var tb = document.getElementById('tbody');
    tb.innerHTML = apps.map(function (app, ai) {
      // Display link includes sitePrefix (e.g. /test/Key2)
      // Probe path uses basePath only (e.g. /Key2) — backend nodes don't know about /test
      var displayPath = joinPath(CFG.sitePrefix + CFG.basePath, app.path);
      var label = app.label ? '<span class="app-label">' + esc(app.label) + '</span>' : '';
      var tds = '<td class="td-app"><a href="' + esc(displayPath) + '" target="_blank">' + esc(displayPath) + '</a>' + label + '</td>';
      servers.forEach(function (_, si) {
        tds += '<td class="td-srv" id="c-' + ai + '-' + si + '"><span class="pill p-pend"><span class="pdot"></span>&#8230;</span></td>';
      });
      tds += '<td class="td-ov" id="ov-' + ai + '"><span class="ob ob-pend">&#8230;</span></td>';
      return '<tr>' + tds + '</tr>';
    }).join('');
  }

  // ── Probe ──────────────────────────────────────────────────────────────────
  async function probeViaProxy(serverName, appPath) {
    var timeout = 10000;
    var t0 = Date.now();
    try {
      var qs = '?server=' + encodeURIComponent(serverName) + '&path=' + encodeURIComponent(appPath);
      var r = await fetch('./check.ashx' + qs, { cache: 'no-store', signal: AbortSignal.timeout(timeout) });
      var elapsed = Date.now() - t0;
      if (!r.ok) return { ok: false, code: 'proxy-' + r.status, elapsed: elapsed };
      var d = await r.json();
      var code = d.status;
      var isOk = (d.ok === true);
      return { ok: isOk, code: String(code), elapsed: typeof d.ms === 'number' ? d.ms : elapsed };
    } catch (e) {
      return { ok: false, code: e.name === 'AbortError' ? 'timeout' : 'unreachable', elapsed: Date.now() - t0 };
    }
  }

  // ── Render ─────────────────────────────────────────────────────────────────
  function renderCell(id, r) {
    var el = document.getElementById(id);
    if (!el) return;
    if (!r || r.pending) { el.innerHTML = '<span class="pill p-pend"><span class="pdot"></span>&#8230;</span>'; return; }
    var code = r.code;
    var cls;
    if (!r.ok) {
      cls = (code === 'timeout') ? 'p-warn' : 'p-err';
    } else if (code === '401' || code === '403') {
      cls = 'p-auth';
    } else {
      cls = 'p-ok';
    }
    var ms  = (r.elapsed && r.elapsed > 0) ? '<span class="pms"> ' + r.elapsed + 'ms</span>' : '';
    el.innerHTML = '<span class="pill ' + cls + '"><span class="pdot"></span>' + esc(code) + ms + '</span>';
  }

  function renderOverall(id, row) {
    var el = document.getElementById(id);
    if (!el) return;
    var done   = row.filter(function (r) { return r && !r.pending; });
    if (!done.length) { el.innerHTML = '<span class="ob ob-pend">&#8230;</span>'; return; }
    var allOk  = done.every(function (r) { return r.ok; });
    var anyOk  = done.some( function (r) { return r.ok; });
    if      (allOk) el.innerHTML = '<span class="ob ob-ok">OK</span>';
    else if (anyOk) el.innerHTML = '<span class="ob ob-warn">Partial</span>';
    else            el.innerHTML = '<span class="ob ob-err">Down</span>';
  }

  function updateSummary(matrix) {
    var ok = 0, warn = 0, err = 0;
    matrix.forEach(function (row) {
      var done = row.filter(function (r) { return r && !r.pending; });
      if (!done.length) return;
      if      (done.every(function (r) { return r.ok; })) ok++;
      else if (done.some( function (r) { return r.ok; })) warn++;
      else                                                 err++;
    });
    document.getElementById('sum-total').textContent = matrix.length;
    document.getElementById('sum-ok').textContent    = ok;
    document.getElementById('sum-warn').textContent  = warn;
    document.getElementById('sum-err').textContent   = err;
  }

  // ── Main ───────────────────────────────────────────────────────────────────
  async function runChecks() {
    if (running) return;
    running = true;
    var btn = document.getElementById('refresh-btn');
    btn.disabled = true; btn.textContent = '\u27F3 Checking\u2026';
    hideBanner('err'); hideBanner('warn');

    try { CFG = await loadConfig(); }
    catch (e) {
      showBanner('err', 'Failed to load configuration: ' + e.message);
      btn.disabled = false; btn.textContent = '\u21BA Refresh'; running = false; return;
    }

    var hostingEl  = document.getElementById('logo-hosting');
    var customerEl = document.getElementById('logo-customer');
    var dividerEl  = document.getElementById('logo-divider');
    if (CFG.logoHosting)  { hostingEl.src  = CFG.logoHosting;  hostingEl.style.display  = ''; }
    else                  { hostingEl.style.display  = 'none'; }
    if (CFG.logoCustomer) { customerEl.src = CFG.logoCustomer; customerEl.style.display = ''; }
    else                  { customerEl.style.display = 'none'; }
    dividerEl.style.display = (CFG.logoHosting && CFG.logoCustomer) ? '' : 'none';

    buildHeader(CFG.servers);
    buildRows(CFG.applications, CFG.servers);
    ['sum-ok','sum-warn','sum-err'].forEach(function(id){ document.getElementById(id).textContent = '\u2014'; });
    document.getElementById('sum-total').textContent = CFG.applications.length;

    var matrix = CFG.applications.map(function () {
      return CFG.servers.map(function () { return { pending: true }; });
    });

    var tasks = [];
    CFG.applications.forEach(function (app, ai) {
      var appPath = joinPath(CFG.basePath, app.path);
      CFG.servers.forEach(function (srv, si) {
        tasks.push(
          probeViaProxy(srv.name, appPath).then(function (result) {
            matrix[ai][si] = result;
            renderCell('c-' + ai + '-' + si, result);
            renderOverall('ov-' + ai, matrix[ai]);
            updateSummary(matrix);
          })
        );
      });
    });

    await Promise.allSettled(tasks);

    document.getElementById('last-checked').textContent = 'Last checked ' + new Date().toLocaleTimeString('en-GB');
    btn.disabled = false; btn.textContent = '\u21BA Refresh'; running = false;
  }

  // ── Auto-refresh ───────────────────────────────────────────────────────────
  function toggleAuto() {
    var on   = document.getElementById('auto-toggle').checked;
    var secs = (CFG && CFG.autoRefreshSeconds) ? CFG.autoRefreshSeconds : 60;
    document.getElementById('auto-label').textContent = on ? 'Auto-refresh ' + secs + 's' : 'Auto-refresh off';
    clearInterval(autoTimer); autoTimer = null;
    if (on) autoTimer = setInterval(runChecks, secs * 1000);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  function showBanner(t, m) { var e = document.getElementById('banner-' + t); e.textContent = m; e.style.display = 'block'; }
  function hideBanner(t)    { document.getElementById('banner-' + t).style.display = 'none'; }
  function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

  window.runChecks   = runChecks;
  window.toggleAuto  = toggleAuto;
  window.toggleTheme = toggleTheme;

  document.getElementById('footer-host').textContent = window.location.hostname + window.location.pathname;
  runChecks();

}());
</script>
</body>
</html>
