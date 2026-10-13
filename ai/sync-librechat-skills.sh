#!/bin/bash
# Builds the deployment-skills directory of LibreChat (librechat/skills, mounted at /app/skills) from the skill repositories.
# LibreChat reads one directory, with the skills at its root (SKILL.md inside each), refuses symlinks and duplicate names, and
# loads them at startup: so each skill folder is copied flat into it. Run before `docker compose up` (start-ai-stack.sh does).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HERE/librechat/skills"
SOURCES=(
  "/home/igor/development/projects/cybersecurity/vers2/test/moqui-agent-skills/skills"
  "/home/igor/development/projects/moqui/master/moqui-plc/agent-skills/skills"
)
mkdir -p "$TARGET"
declare -A seen
for src in "${SOURCES[@]}"; do
  [ -d "$src" ] || { echo "missing skill source: $src" >&2; exit 1; }
  if find "$src" -type l | grep -q .; then echo "symlinks are refused by LibreChat, found in $src" >&2; find "$src" -type l >&2; exit 1; fi
  for dir in "$src"/*/; do
    [ -f "$dir/SKILL.md" ] || continue
    name="$(basename "$dir")"
    if [ -n "${seen[$name]:-}" ]; then echo "duplicate skill folder $name ($src and ${seen[$name]})" >&2; exit 1; fi
    seen[$name]="$src"
    rsync -a --delete --exclude '.git' --exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store' "$dir" "$TARGET/$name/"
  done
done
# LibreChat accepts a fixed set of frontmatter keys; the Agent Skills key `compatibility` is not one of them, so in the copy it moves
# under `metadata` (the sources stay as the specification has them)
python3 - "$TARGET" <<'PY'
import sys, pathlib, yaml
for md in sorted(pathlib.Path(sys.argv[1]).glob('*/SKILL.md')):
    text = md.read_text(encoding='utf-8')
    if not text.startswith('---'): continue
    head, sep, body = text[3:].partition('\n---')
    fm = yaml.safe_load(head) or {}
    if 'compatibility' not in fm: continue
    fm.setdefault('metadata', {})['compatibility'] = fm.pop('compatibility')
    md.write_text('---\n' + yaml.safe_dump(fm, sort_keys=False, allow_unicode=True, width=1000) + '---' + body, encoding='utf-8')
PY
# what no source has any more goes away
for existing in "$TARGET"/*/; do
  [ -d "$existing" ] || continue
  [ -n "${seen[$(basename "$existing")]:-}" ] || rm -rf "$existing"
done
echo "skills in $TARGET: $(ls "$TARGET" | wc -l)"
