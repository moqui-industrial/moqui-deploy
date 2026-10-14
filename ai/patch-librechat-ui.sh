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
import sys
p, bundle = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
old = '{url:"assets/%s",revision:null}' % bundle
if s.count(old) != 1:
    sys.exit("the service worker has no precache entry for the bundle; the patch does not fit this image")
open(p, 'w', encoding='utf-8').write(s.replace(old, '{url:"assets/%s",revision:"moqui-patched-1"}' % bundle))
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
script = """<script>
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
EOF
echo "patched $BUNDLE"
