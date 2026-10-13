#!/bin/sh
# platform: macOS-only -- drives the launcher, which targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup

MG="$H/root/usr/local/mavergreen"
mkdir -p "$H/links"
ln -s "$MG/pi/bin/pi" "$H/links/pi"

h_assert_eq "node24 https://github.com/Mavergreen/nodejs-24/releases/latest
fd https://github.com/Mavergreen/fd/releases/latest
rg https://github.com/Mavergreen/rg/releases/latest" "$(cat "$MG/pi/share/pi/requires")" "requires manifest"

run_pi() { rc=0; err=$("$H/links/pi" 2>&1 >/dev/null) || rc=$?; }

for s in node24 fd rg; do mkdir -p "$MG/$s"; : > "$MG/$s/mavergreen.plist"; done
mkdir -p "$MG/node24/bin" "$HOME/.pi/agent/install/releases/1.1.0/node_modules/.bin"
printf '#!/bin/sh\nexit 0\n' > "$MG/node24/bin/node"
printf '#!/bin/sh\n' > "$HOME/.pi/agent/install/releases/1.1.0/node_modules/.bin/pi"
chmod +x "$MG/node24/bin/node" "$HOME/.pi/agent/install/releases/1.1.0/node_modules/.bin/pi"
printf '%s\n' '{"kind":"pi-managed-install","schemaVersion":1,"layout":"releases-v1"}' > "$HOME/.pi/agent/install/managed-install.json"
printf '1.1.0\n' > "$HOME/.pi/agent/install/current-version"
run_pi
h_assert_eq 0 "$rc" "all present exits 0"
case "$err" in *"not installed"*|*missing*) h_assert_eq "" "$err" "all present has no requires complaint" ;; esac

for s in node24:nodejs-24 fd:fd rg:rg; do
  short="${s%%:*}"; repo="${s#*:}"
  mv "$MG/$short/mavergreen.plist" "$MG/$short/gone"
  run_pi
  [ "$rc" -ne 0 ] || { echo "FAIL: $short missing should fail" >&2; H_FAILS=$((H_FAILS+1)); }
  h_assert_contains "$err" "pi: $short is not installed; get it from https://github.com/Mavergreen/$repo/releases/latest" "$short missing message"
  mv "$MG/$short/gone" "$MG/$short/mavergreen.plist"
done

mv "$MG/pi/share/pi/requires" "$MG/pi/share/pi/requires.gone"
run_pi
[ "$rc" -ne 0 ] || { echo "FAIL: missing requires should fail" >&2; H_FAILS=$((H_FAILS+1)); }
h_assert_contains "$err" "missing $(cd "$MG/pi" && pwd -P)/share/pi/requires" "missing requires message"
h_done
