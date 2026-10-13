#!/bin/sh
# platform: host-agnostic
set -eu
. "$(dirname "$0")/../build/msc.sh"
cd "$(dirname "$0")/.."
fails=0
ok()  { printf 'ok: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; fails=1; }

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
  # spec: .github/workflows/conventions.yml -- runs the family gate in CI with its own PyYAML
  printf 'skip: family gate -- no python3 with PyYAML here, and the gate refuses to pass without it\n'
elif sh "$SHIPYARD_SCRIPTS/check-family-conventions.sh"; then ok "family gate exits 0"; else bad "family gate exits 0"; fi

case "$(cat UPSTREAM_VERSION)" in
  ''|*[!0-9.]*|.*|*.|*..*) bad "UPSTREAM_VERSION is a bare dotted version" ;;
  *.*.*) ok "UPSTREAM_VERSION is a bare dotted version" ;;
  *) bad "UPSTREAM_VERSION is a bare dotted version" ;;
esac
cmp -s build/msc.sh "$SHIPYARD_SCRIPTS/templates/msc.sh" && ok "msc.sh matches the template" || bad "msc.sh matches the template"
grep -q '^- upstream: UPSTREAM_VERSION$' INGREDIENTS.md && ok "INGREDIENTS declares upstream state" || bad "INGREDIENTS declares upstream state"
if node -e '
const c = JSON.parse(require("fs").readFileSync(".github/renovate.json", "utf8"));
const m = (c.customManagers || []).filter((x) => x.depNameTemplate === "@earendil-works/pi-coding-agent");
if (m.length !== 1) { console.error("want one manager for @earendil-works/pi-coding-agent, found " + m.length); process.exit(1); }
if (m[0].datasourceTemplate !== "npm") { console.error("its datasource is " + m[0].datasourceTemplate + ", not npm"); process.exit(1); }
if (JSON.stringify(m[0].managerFilePatterns) !== JSON.stringify(["/^UPSTREAM_VERSION$/"])) { console.error("it does not watch UPSTREAM_VERSION alone"); process.exit(1); }
'; then ok "renovate tracks Pi on npm, in UPSTREAM_VERSION"; else bad "renovate tracks Pi on npm, in UPSTREAM_VERSION"; fi
[ "$(sh build/upstream-release-notes-url.sh 1.1.0)" = https://github.com/earendil-works/pi/releases/tag/v1.1.0 ] \
  && ok "release notes URL" || bad "release notes URL"
printf 'platform\nspec\n' | cmp -s - comment-reasons && ok "comment-reasons" || bad "comment-reasons"
exit "$fails"
