import { HEALTH_VAULT_WIDGET_URI, healthVaultResourceMeta, vaultConnectOrigins } from './constants';

const WIDGET_SCRIPT = `
var statusEl = document.getElementById("lyb-status");
var confirmToken = "";

function shareConfirmed(consentId) {
  var bridge = window.openai;
  if (!bridge || typeof bridge.callTool !== "function") return;
  return bridge.callTool("share_summary_with_chatgpt", { consentId: consentId });
}

function setStatus(text) {
  if (statusEl) statusEl.textContent = text;
}

function allowed(value) {
  try {
    return LYB_ORIGINS.indexOf(new URL(value).origin) !== -1;
  } catch (error) {
    return false;
  }
}

function line(text) {
  var node = document.createElement("p");
  node.textContent = text;
  return node;
}

function section(id) {
  return document.getElementById(id);
}

function clear(id) {
  var el = section(id);
  if (!el) return;
  while (el.firstChild) el.removeChild(el.firstChild);
}

function showDexa(rows) {
  clear("lyb-dexa");
  var el = section("lyb-dexa");
  if (!el) return;
  rows.forEach(function (row) {
    var lean = row.leanMassKg == null ? "" : ", lean mass " + row.leanMassKg + " kg";
    el.appendChild(line(row.measuredOn + ": body fat " + row.bodyFatPercent + "%" + lean));
  });
}

function showWeights(rows) {
  clear("lyb-weigh");
  var el = section("lyb-weigh");
  if (!el) return;
  rows.forEach(function (row) {
    el.appendChild(line(row.measuredOn + ": " + row.weightKg + " kg"));
  });
}

function showPhotos(rows) {
  clear("lyb-photos");
  var el = section("lyb-photos");
  if (!el) return;
  rows.forEach(function (row) {
    if (!row.imageUrl || !allowed(row.imageUrl)) return;
    var img = document.createElement("img");
    img.alt = "Progress photo";
    img.src = row.imageUrl;
    el.appendChild(img);
  });
}

function wireShare() {
  var form = document.getElementById("lyb-share");
  if (!form) return;
  form.addEventListener("submit", function (event) {
    event.preventDefault();
    var fields = [];
    form.querySelectorAll("input[name=\\"field\\"]:checked").forEach(function (input) {
      fields.push(input.value);
    });
    if (!fields.length || !confirmToken) {
      setStatus("Choose a summary, then confirm.");
      return;
    }
    fetch(LYB_ORIGIN + "/api/health-vault/consents", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ confirmToken: confirmToken, fields: fields }),
    })
      .then(function (response) { return response.json(); })
      .then(function (body) {
        var consentId = body && typeof body.consentId === "string" ? body.consentId : "";
        if (!consentId) {
          setStatus("That confirmation expired. Open the vault again.");
          return;
        }
        setStatus("Sharing the confirmed summary.");
        shareConfirmed(consentId);
      })
      .catch(function () {
        setStatus("LogYourBody could not record that confirmation.");
      });
  });
}

function handleFromHost() {
  var meta = window.openai && window.openai.toolResponseMetadata;
  var envelope = meta && (meta.mcp_tool_result || meta);
  var hidden = envelope && envelope._meta;
  return hidden && typeof hidden.viewHandle === "string" ? hidden.viewHandle : "";
}

function load() {
  wireShare();
  var handle = handleFromHost();
  if (!handle) {
    setStatus("Open the vault from LogYourBody to load this view.");
    return;
  }
  fetch(LYB_ORIGIN + "/api/health-vault/view", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ handle: handle }),
  })
    .then(function (response) {
      if (!response.ok) throw new Error("view");
      return response.json();
    })
    .then(function (view) {
      confirmToken = typeof view.confirmToken === "string" ? view.confirmToken : "";
      showDexa(Array.isArray(view.dexa) ? view.dexa : []);
      showPhotos(Array.isArray(view.photos) ? view.photos : []);
      showWeights(Array.isArray(view.weighIns) ? view.weighIns : []);
      setStatus("Loaded from LogYourBody.");
    })
    .catch(function () {
      setStatus("This vault view expired. Open it again from LogYourBody.");
    });
}

load();
`;

export function healthVaultWidgetDocument(apiOrigin: string): string {
  const origins = JSON.stringify(vaultConnectOrigins(apiOrigin));
  const origin = JSON.stringify(apiOrigin);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LogYourBody vault</title>
<style>
  body { font: 16px/1.4 -apple-system, sans-serif; margin: 16px; color: #111; background: #fff; }
  img { max-width: 100%; height: auto; }
  label { display: block; }
  button { margin-top: 12px; }
</style>
</head>
<body>
<main id="lyb-vault">
  <p id="lyb-status">Loading from LogYourBody.</p>
  <section id="lyb-dexa"></section>
  <section id="lyb-photos"></section>
  <section id="lyb-weigh"></section>
  <form id="lyb-share">
    <label><input type="checkbox" name="field" value="lean_mass"> Lean mass change</label>
    <label><input type="checkbox" name="field" value="body_fat"> Body-fat change</label>
    <label><input type="checkbox" name="field" value="weight"> Weight change</label>
    <button type="submit">Share selected summary</button>
  </form>
</main>
<script>
var LYB_ORIGIN = ${origin};
var LYB_ORIGINS = ${origins};
${WIDGET_SCRIPT}
</script>
</body>
</html>`;
}

export function healthVaultResourceDescriptor() {
  return {
    uri: HEALTH_VAULT_WIDGET_URI,
    name: 'LogYourBody vault',
    mimeType: 'text/html;profile=mcp-app' as const,
  };
}

export function healthVaultWidgetResource(apiOrigin: string) {
  return {
    uri: HEALTH_VAULT_WIDGET_URI,
    mimeType: 'text/html;profile=mcp-app',
    text: healthVaultWidgetDocument(apiOrigin),
    _meta: healthVaultResourceMeta(apiOrigin),
  };
}
