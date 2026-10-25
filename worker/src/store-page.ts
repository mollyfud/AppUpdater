// Token-gated store page served at GET /store (+ /store.js). Plain HTML/JS, no framework.
// The invite link carries the token in the URL fragment (#t=...), which browsers never send
// to the server; the script reads it and strips it from the address bar.

export interface StorePalette {
  bg: string;
  surface: string;
  text: string;
  muted: string;
  border: string;
  accent: string;
  accentText: string;
  error: string;
}

/** Colour pairs are checked for 4.5:1 contrast in test/store-page.test.ts. */
export const STORE_PALETTE: { light: StorePalette; dark: StorePalette } = {
  light: {
    bg: "#f4f6f8",
    surface: "#ffffff",
    text: "#1b1f24",
    muted: "#4a5360",
    border: "#c9d0d8",
    accent: "#1f5fbf",
    accentText: "#ffffff",
    error: "#a8201a",
  },
  dark: {
    bg: "#111418",
    surface: "#1b2027",
    text: "#e8ebef",
    muted: "#aab3bf",
    border: "#3a434f",
    accent: "#8cb8ff",
    accentText: "#0b1a33",
    error: "#ff9b93",
  },
};

function cssVars(p: StorePalette): string {
  return `--bg:${p.bg};--surface:${p.surface};--text:${p.text};--muted:${p.muted};--border:${p.border};--accent:${p.accent};--accent-text:${p.accentText};--error:${p.error};`;
}

export const STORE_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="referrer" content="no-referrer">
<title>Private Apps</title>
<style>
:root{${cssVars(STORE_PALETTE.light)}color-scheme:light dark}
@media (prefers-color-scheme: dark){:root{${cssVars(STORE_PALETTE.dark)}}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:640px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:1.5rem;margin:0 0 4px}
h2{font-size:1.15rem;margin:0}
p{margin:8px 0}
.muted{color:var(--muted)}
.error{color:var(--error);font-weight:600}
.card{background:var(--surface);color:var(--text);border:1px solid var(--border);border-radius:12px;padding:16px;margin:16px 0}
.row{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-top:12px}
button,.btn{font:inherit;font-weight:600;border-radius:8px;padding:10px 16px;cursor:pointer;border:1px solid var(--accent);background:var(--accent);color:var(--accent-text)}
button.secondary{background:var(--surface);color:var(--text);border-color:var(--border)}
button:disabled{opacity:.6;cursor:wait}
input[type=password],input[type=text]{font:inherit;width:100%;padding:10px 12px;border-radius:8px;border:1px solid var(--border);background:var(--surface);color:var(--text)}
details{margin-top:8px}
summary{cursor:pointer;color:var(--muted)}
pre{white-space:pre-wrap;font:inherit;margin:8px 0 0}
ol{padding-left:20px;margin:8px 0}
label{display:flex;gap:8px;align-items:center}
</style>
</head>
<body>
<main>
<h1>Private Apps</h1>
<p class="muted" id="viewer">Enter the access token you were given.</p>
<section id="login" class="card" hidden>
<form id="login-form">
<label for="token-input" style="display:block;font-weight:600;margin-bottom:8px">Access token</label>
<input id="token-input" type="password" autocomplete="off" spellcheck="false" placeholder="aug_...">
<div class="row"><button type="submit">Show my apps</button></div>
</form>
<p id="login-error" class="error" hidden></p>
</section>
<section id="howto" class="card" hidden>
<h2>How to install</h2>
<ol>
<li>Tap <strong>Download</strong> on an app below and open the file.</li>
<li>If Android asks, allow your browser to <strong>install unknown apps</strong>, then install. (If Google Play Protect warns that the app is unrecognized, tap <em>More details</em> &rarr; <em>Install anyway</em>).</li>
<li>Open the app, tap the <strong>Settings</strong> (gear) button and paste your access token so it can update itself.</li>
</ol>
<div class="row">
<button type="button" id="copy-token">Copy access token</button>
<button type="button" class="secondary" id="forget">Forget token</button>
</div>
<div class="row"><label><input type="checkbox" id="remember"> Remember on this device</label></div>
<p id="copy-status" class="muted" role="status"></p>
</section>
<p id="status" class="muted" role="status"></p>
<div id="apps"></div>
</main>
<script src="/store.js"></script>
</body>
</html>
`;

export const STORE_JS = `"use strict";
(function () {
  var KEY = "appUpdaterStoreToken";
  var token = "";
  var $ = function (id) { return document.getElementById(id); };

  function storageGet() { try { return localStorage.getItem(KEY) || ""; } catch (e) { return ""; } }
  function storageSet(v) { try { if (v) localStorage.setItem(KEY, v); else localStorage.removeItem(KEY); } catch (e) {} }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  }

  function api(path) {
    return fetch(path, { headers: { Authorization: "Bearer " + token }, cache: "no-store" });
  }

  function showLogin(message) {
    $("login").hidden = false;
    $("howto").hidden = true;
    $("apps").textContent = "";
    $("status").textContent = "";
    $("viewer").textContent = "Enter the access token you were given.";
    var err = $("login-error");
    err.hidden = !message;
    err.textContent = message || "";
  }

  function formatSize(bytes) {
    if (!bytes) return "";
    if (bytes < 1024 * 1024) return Math.max(1, Math.round(bytes / 1024)) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
  }

  function render(data) {
    $("login").hidden = true;
    $("howto").hidden = false;
    $("remember").checked = storageGet() === token;
    $("viewer").textContent = data.viewer ? "Shared with " + data.viewer + "." : "";
    var list = $("apps");
    list.textContent = "";
    var apps = data.apps || [];
    $("status").textContent = apps.length ? "" : "No apps have been shared with this token yet.";
    apps.forEach(function (app) {
      var card = el("article", "card");
      card.appendChild(el("h2", "", app.title || app.appId));
      if (app.summary) card.appendChild(el("p", "", app.summary));
      var meta = "Version " + app.versionName + " (build " + app.versionCode + ")";
      if (app.releaseDate) meta += " - " + String(app.releaseDate).slice(0, 10);
      if (app.fileSize) meta += " - " + formatSize(app.fileSize);
      card.appendChild(el("p", "muted", meta));
      if (app.shareable === false) card.appendChild(el("p", "muted", "Not shared (owner view)."));
      if (app.releaseNotes) {
        var d = el("details");
        d.appendChild(el("summary", "", "What's new"));
        d.appendChild(el("pre", "", app.releaseNotes));
        card.appendChild(d);
      }
      var row = el("div", "row");
      var btn = el("button", "", "Download");
      btn.type = "button";
      var msg = el("span", "muted");
      btn.addEventListener("click", function () { download(app.appId, btn, msg); });
      row.appendChild(btn);
      row.appendChild(msg);
      card.appendChild(row);
      list.appendChild(card);
    });
  }

  function download(appId, btn, msg) {
    btn.disabled = true;
    msg.className = "muted";
    msg.textContent = "Preparing download...";
    api("/api/v1/update/" + encodeURIComponent(appId))
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (m) {
        if (!m.downloadUrl) throw new Error("no download link");
        msg.textContent = "Download started.";
        window.location.href = m.downloadUrl;
      })
      .catch(function (e) {
        msg.className = "error";
        msg.textContent = "Download failed (" + e.message + ").";
      })
      .then(function () { btn.disabled = false; });
  }

  function load() {
    $("status").textContent = "Loading...";
    api("/api/v1/catalog")
      .then(function (r) {
        if (r.status === 401 || r.status === 403) {
          if (storageGet() === token) storageSet("");
          token = "";
          showLogin("That token was not accepted. It may have expired or been revoked.");
          return null;
        }
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (data) { if (data) render(data); })
      .catch(function (e) { $("status").textContent = "Could not load apps (" + e.message + ")."; });
  }

  $("login-form").addEventListener("submit", function (ev) {
    ev.preventDefault();
    token = $("token-input").value.trim();
    $("token-input").value = "";
    if (token) load(); else showLogin("Paste your access token first.");
  });
  $("copy-token").addEventListener("click", function () {
    var status = $("copy-status");
    if (!navigator.clipboard) { status.textContent = "Copying is not available in this browser."; return; }
    navigator.clipboard.writeText(token).then(
      function () { status.textContent = "Token copied. Paste it in the app's Settings."; },
      function () { status.textContent = "Could not copy the token."; }
    );
  });
  $("forget").addEventListener("click", function () {
    storageSet("");
    token = "";
    showLogin("");
  });
  $("remember").addEventListener("change", function (ev) {
    storageSet(ev.target.checked ? token : "");
  });

  function tokenFromHash() {
    var m = /(?:^#|&)t=([^&]+)/.exec(window.location.hash);
    if (!m) return "";
    history.replaceState(null, "", window.location.pathname);
    return decodeURIComponent(m[1]);
  }

  // An invite link opened in an already-open store tab only changes the fragment.
  window.addEventListener("hashchange", function () {
    var t = tokenFromHash();
    if (t) { token = t; load(); }
  });

  token = tokenFromHash() || storageGet();
  if (token) load(); else showLogin("");
})();
`;

export const STORE_SECURITY_HEADERS: Record<string, string> = {
  "Content-Security-Policy":
    "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self'; form-action 'none'; frame-ancestors 'none'; base-uri 'none'",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Cache-Control": "no-store",
  "X-Robots-Tag": "noindex, nofollow",
};
