#!/bin/bash
# Removes the "Skills" entry of the sidebar of LibreChat v0.8.7 (the Agent Builder entry has a setting of its own,
# endpoints.agents.disableBuilder). LibreChat has no setting for this entry: it appears together with the skills capability that
# the chats need, so the one condition in the client bundle is replaced in a copy of the bundle, which the compose override mounts.
# The script refuses to run on a bundle where the text it replaces is not there (another version of the image).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="$(sed -n 's/^ *image: *\(ghcr.io\/danny-avila\/librechat:[^ ]*\).*/\1/p' "$HERE/librechat-compose.yml" | head -1)"
OUT="$HERE/librechat/client-patch"
mkdir -p "$OUT"
BUNDLE="$(docker run --rm --entrypoint sh "$IMAGE" -c 'cd /app/client/dist/assets && grep -l "com_ui_skills:" index.*.js | head -1')"
[ -n "$BUNDLE" ] || { echo "client bundle not found in $IMAGE" >&2; exit 1; }
docker run --rm --entrypoint cat "$IMAGE" "/app/client/dist/assets/$BUNDLE" > "$OUT/$BUNDLE"
python3 - "$OUT/$BUNDLE" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = "c&&v&&_.push({title:`com_ui_skills`"
if s.count(old) != 1:
    sys.exit("the skills entry of the sidebar is not in this bundle exactly once; the patch does not fit this image")
open(p, 'w', encoding='utf-8').write(s.replace(old, "!1&&_.push({title:`com_ui_skills`"))
PY
# Browsers are served the precompressed copies of the bundle (.br and .gz next to it), not the file: the copies are made again from
# the patched file, or the browsers would keep getting the original.
node -e '
const fs = require("fs"), z = require("zlib"), f = process.argv[1];
const raw = fs.readFileSync(f);
fs.writeFileSync(f + ".br", z.brotliCompressSync(raw, { params: { [z.constants.BROTLI_PARAM_QUALITY]: 11 } }));
fs.writeFileSync(f + ".gz", z.gzipSync(raw, { level: 9 }));
' "$OUT/$BUNDLE"

# The service worker of LibreChat keeps the bundle in its precache by file name (revision null, the name is a hash), so a changed
# file under the same name would never be fetched again by a browser that has the old one: the entry gets a revision, and a changed
# sw.js makes the browsers install the new worker (it skips waiting and claims the page).
docker run --rm --entrypoint cat "$IMAGE" /app/client/dist/sw.js > "$OUT/sw.js"
python3 - "$OUT/sw.js" "$BUNDLE" <<'PY'
import hashlib, sys
p, bundle = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
old = '{url:"assets/%s",revision:null}' % bundle
if s.count(old) != 1:
    sys.exit("the service worker has no precache entry for the bundle; the patch does not fit this image")
bundle_path = p.rsplit('/', 1)[0] + '/' + bundle
revision = 'moqui-' + hashlib.sha256(open(bundle_path, 'rb').read()).hexdigest()[:16]
open(p, 'w', encoding='utf-8').write(s.replace(old, '{url:"assets/%s",revision:"%s"}' % (bundle, revision)))
PY

# The theme of Moqui (the switch Dark/Light of its navbar) reaches LibreChat when it is shown in the side panel of Moqui: the page
# of Moqui posts {type:'moqui-theme', dark:true|false} to the frame and this listener, in the index.html of LibreChat, sets the
# theme the same way LibreChat does (class on <html> and the color-theme key). Only the origins named here are listened to.
MOQUI_ORIGINS="${MOQUI_ORIGINS:-http://localhost:8080,http://127.0.0.1:8080}"
docker run --rm --entrypoint cat "$IMAGE" /app/client/dist/index.html > "$OUT/index.html"
python3 - "$OUT/index.html" "$MOQUI_ORIGINS" <<'PY'
import sys, json
p, origins = sys.argv[1], [o.strip() for o in sys.argv[2].split(',') if o.strip()]
s = open(p, encoding='utf-8').read()
script = r"""<script>
(function () {
  var ORIGINS = %s;
  window.addEventListener('message', function (e) {
    if (ORIGINS.indexOf(e.origin) < 0 || !e.data || e.data.type !== 'moqui-theme') return;
    var theme = e.data.dark ? 'dark' : 'light';
    try { localStorage.setItem('color-theme', theme); } catch (x) {}
    var c = document.documentElement.classList;
    c.remove(theme === 'dark' ? 'light' : 'dark');
    c.add(theme);
  });
  function post(target, message) {
    ORIGINS.forEach(function (o) { try { target.postMessage(message, o); } catch (x) {} });
  }
  if (window.parent !== window) post(window.parent, { type: 'librechat-ready' });
  var chartScript;
  var chartPalette = ['#1976d2', '#26a69a', '#9c27b0', '#ff9800', '#ef5350', '#5c6bc0', '#66bb6a', '#8d6e63'];
  function boundedText(value, limit) {
    return typeof value === 'string' ? value.slice(0, limit) : '';
  }
  function chartSpec(value) {
    var spec;
    try { spec = JSON.parse(value); } catch (x) { return null; }
    if (!spec || ['bar', 'line', 'pie', 'doughnut'].indexOf(spec.type) < 0 || !Array.isArray(spec.labels) || !Array.isArray(spec.datasets)) return null;
    if (spec.labels.length < 1 || spec.labels.length > 100 || spec.datasets.length < 1 || spec.datasets.length > 8) return null;
    var labels = spec.labels.map(function (label) { return boundedText(String(label), 120); });
    var datasets = spec.datasets.map(function (dataset, index) {
      if (!dataset || !Array.isArray(dataset.data) || dataset.data.length !== labels.length) return null;
      var data = dataset.data.map(function (number) { return Number(number); });
      if (data.some(function (number) { return !Number.isFinite(number); })) return null;
      return {
        label: boundedText(dataset.label || ('Series ' + (index + 1)), 120),
        data: data,
        backgroundColor: chartPalette[index],
        borderColor: chartPalette[index],
        borderWidth: 1
      };
    });
    return datasets.some(function (dataset) { return !dataset; }) ? null : { title: boundedText(spec.title || 'Chart', 160), type: spec.type, labels: labels, datasets: datasets };
  }
  function loadChart(callback) {
    if (window.Chart) { callback(); return; }
    if (chartScript) { chartScript.addEventListener('load', callback, { once: true }); return; }
    chartScript = document.createElement('script');
    chartScript.src = 'https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js';
    chartScript.integrity = 'sha384-vsrfeLOOY6KuIYKDlmVH5UiBmgIdB1oEf7p01YgWHuqmOHfZr374+odEv96n9tNC';
    chartScript.crossOrigin = 'anonymous';
    chartScript.addEventListener('load', callback, { once: true });
    document.head.appendChild(chartScript);
  }
  function renderChart(code) {
    if (code.dataset.moquiChartRendered) return;
    var spec = chartSpec(code.textContent);
    if (!spec || !code.parentElement || !code.parentElement.parentElement) return;
    code.dataset.moquiChartRendered = 'true';
    loadChart(function () {
      if (!window.Chart) return;
      var pre = code.parentElement;
      var panel = document.createElement('section');
      panel.style.cssText = 'max-width:720px;height:420px;margin:1rem 0;padding:1rem;border:1px solid #777;border-radius:.5rem;background:var(--surface-primary,#fff)';
      var title = document.createElement('h3');
      title.textContent = spec.title;
      title.style.margin = '0 0 .75rem';
      var canvas = document.createElement('canvas');
      canvas.setAttribute('role', 'img');
      canvas.setAttribute('aria-label', spec.title);
      panel.appendChild(title);
      panel.appendChild(canvas);
      pre.parentElement.insertBefore(panel, pre.nextSibling);
      pre.style.display = 'none';
      new window.Chart(canvas, {
        type: spec.type,
        data: { labels: spec.labels, datasets: spec.datasets },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: spec.datasets.length > 1 }, tooltip: { enabled: true } },
          scales: (spec.type === 'bar' || spec.type === 'line') ? { y: { beginAtZero: true } } : {}
        }
      });
    });
  }
  function renderCharts() {
    document.querySelectorAll('pre code.language-chartjs, pre code[class*="language-chartjs"]').forEach(renderChart);
  }
  var chartTimer;
  new MutationObserver(function () {
    clearTimeout(chartTimer);
    chartTimer = setTimeout(renderCharts, 100);
  }).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
  document.addEventListener('DOMContentLoaded', renderCharts);
  // In the side panel of Moqui the identity provider cannot be used when the browser blocks third-party cookies, so a page that
  // needs a sign-in says so and Moqui does it in a window of its own; that window closes itself once it is in the chat.
  var tries = 0;
  var watcher = setInterval(function () {
    tries++;
    var path = location.pathname;
    if (window.parent !== window) {
      if (/^\/login/.test(path) && document.body && /OpenID/i.test(document.body.innerText)) {
        post(window.parent, { type: 'librechat-login-required', loginUrl: location.origin + '/oauth/openid' });
        clearInterval(watcher);
      }
    } else if (window.opener && /^\/c\//.test(path)) {
      post(window.opener, { type: 'librechat-logged-in' });
      clearInterval(watcher);
      setTimeout(function () { window.close(); }, 300);
    }
    if (tries > 240) clearInterval(watcher);
  }, 500);
})();
</script>
</head>""" % json.dumps(origins)
if s.count('</head>') != 1:
    sys.exit('index.html has no single </head>; the patch does not fit this image')
open(p, 'w', encoding='utf-8').write(s.replace('</head>', script, 1))
PY

# Non-image local attachments (PDF, CSV, Excel, XML, ZIP) uploaded to LibreChat (/app/uploads/<userId>/<uuid>__<filename>)
# are staging files for the skills-python sandbox and Moqui's attach_content tool. Do not base64-encode them into
# message.documents (which would blow up OpenAI context/size limits or fail on CSV/XLSX/ZIP); instead, inject a lightweight
# staging reference into message.fileContext so the model knows the relative inbox path and metadata.
docker run --rm --entrypoint cat "$IMAGE" /app/api/app/clients/BaseClient.js > "$OUT/BaseClient.js"
python3 - "$OUT/BaseClient.js" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read().replace('\r\n', '\n')

old_docs = """  async addDocuments(message, attachments) {
    const documentResult = await encodeAndFormatDocuments("""

new_docs = """  async addDocuments(message, attachments) {
    const remoteAttachments = (attachments || []).filter(
      (f) => (f?.source ?? FileSources.local) !== FileSources.local,
    );
    if (remoteAttachments.length === 0) {
      message.documents = undefined;
      return attachments || [];
    }
    const documentResult = await encodeAndFormatDocuments("""

old_ctx = """  async addFileContextToMessage(message, attachments) {
    const fileContext = await extractFileContext({
      attachments,
      req: this.options?.req,
      tokenCountFn: (text) => countTokens(text),
    });

    if (fileContext) {
      message.fileContext = fileContext;
    }
  }"""

new_ctx = """  async addFileContextToMessage(message, attachments) {
    const fileContext = await extractFileContext({
      attachments,
      req: this.options?.req,
      tokenCountFn: (text) => countTokens(text),
    });
    const localDocs = (attachments || []).filter(
      (f) =>
        (f?.source ?? FileSources.local) === FileSources.local &&
        !(f?.type || '').startsWith('image/') &&
        f?.filepath,
    );
    const inboxLines = localDocs.map((f) => {
      const rel = String(f.filepath).replace(/^\\/?uploads\\//, '');
      return `[Staging file in inbox: "${rel}" (filename: "${f.filename || rel}", size: ${f.bytes || 0} bytes, type: ${f.type || 'unknown'}) — read via skills-python (eplan_bom.py, pdf_pages.py, run_python, run_bash) or attach to Moqui via attach_content]`;
    });
    const combined = [fileContext, ...inboxLines].filter(Boolean).join('\\n');
    if (combined) {
      message.fileContext = combined;
    }
  }"""

if s.count(old_docs) != 1 or s.count(old_ctx) != 1:
    sys.exit("BaseClient.js does not match expected addDocuments / addFileContextToMessage methods")
s = s.replace(old_docs, new_docs, 1).replace(old_ctx, new_ctx, 1)
open(p, 'w', encoding='utf-8').write(s)
PY

cat > "$HERE/librechat-ui-patch.generated.yml" <<EOF
# Generated by patch-librechat-ui.sh; do not edit.
services:
  moqui-librechat:
    volumes:
      - ./librechat/client-patch/$BUNDLE:/app/client/dist/assets/$BUNDLE:ro
      - ./librechat/client-patch/$BUNDLE.br:/app/client/dist/assets/$BUNDLE.br:ro
      - ./librechat/client-patch/$BUNDLE.gz:/app/client/dist/assets/$BUNDLE.gz:ro
      - ./librechat/client-patch/index.html:/app/client/dist/index.html:ro
      - ./librechat/client-patch/sw.js:/app/client/dist/sw.js:ro
      - ./librechat/client-patch/BaseClient.js:/app/api/app/clients/BaseClient.js:ro
EOF
echo "patched $BUNDLE and BaseClient.js"
