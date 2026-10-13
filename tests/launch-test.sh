#!/bin/sh
# platform: macOS-only -- the tests drive the launcher, which targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
. "$(dirname "$0")/lib/fixtures.sh"
h_setup
MG="$H/root/usr/local/mavergreen"
T="$MG/pi"
V=1.1.0
PKG=@earendil-works/pi-coding-agent
REAL_NODE=/usr/local/mavergreen/node24/bin/node

for s in node24 fd rg; do mkdir -p "$MG/$s"; : > "$MG/$s/mavergreen.plist"; done
mkdir -p "$MG/node24/bin"
printf '%s\n' "$V" > "$T/share/pi/seed-version"
cat > "$MG/node24/bin/node" <<EOF2
#!/bin/sh
case "\${1-}" in
  -|-e) exec "$REAL_NODE" "\$@" ;;
esac
{
  for a; do printf 'arg=%s\n' "\$a"; done
  printf 'PI_OFFLINE=%s\n' "\${PI_OFFLINE-unset}"
  printf 'PI_MANAGED_INSTALL_ROOT=%s\n' "\${PI_MANAGED_INSTALL_ROOT-}"
  printf 'PATH=%s\n' "\$PATH"
} > "\$H/node-run"
exit \${FAKE_NODE_RC:-0}
EOF2
chmod +x "$MG/node24/bin/node"
h_fake_npm
h_fixture "$V"
h_api_base

R="$HOME/.pi/agent/install"
ENTRY="$R/releases/$V/node_modules/.bin/pi"
N="$R/releases/$V/node_modules/@earendil-works/pi-tui/native"
X64="$N/darwin/prebuilds/darwin-x64/darwin-platform.node"
MARKER='{"kind":"pi-managed-install","schemaVersion":1,"layout":"releases-v1"}'

calls() { if [ -f "$H/npm-calls" ]; then wc -l < "$H/npm-calls" | tr -d ' '; else echo 0; fi; }
fresh() { rm -rf "$HOME/.pi" "$HOME/Library" "$H/npm-calls" "$H/node-run"; }
seed() {
  mkdir -p "$R/releases/$1/node_modules/.bin"
  printf '#!/bin/sh\n' > "$R/releases/$1/node_modules/.bin/pi"
  chmod +x "$R/releases/$1/node_modules/.bin/pi"
  printf '%s\n' "$MARKER" > "$R/managed-install.json"
}
launch() { "$T/bin/pi" "$@" >"$H/out" 2>"$H/err" && rc=0 || rc=$?; }
nonzero() { echo $([ "$1" -ne 0 ] && echo 1 || echo 0); }

fresh
seed "$V"
printf '%s\n' "$V" > "$R/current-version"
launch --help
h_assert_eq 0 "$rc" "exec line: exits 0"
h_assert_eq "arg=$ENTRY
arg=--help" "$(grep '^arg=' "$H/node-run")" "exec line: node got exactly the entry and --help"
h_assert_eq "PI_OFFLINE=unset" "$(grep '^PI_OFFLINE=' "$H/node-run")" "exec line: PI_OFFLINE is not set"
h_assert_eq "PI_MANAGED_INSTALL_ROOT=$R" "$(grep '^PI_MANAGED_INSTALL_ROOT=' "$H/node-run")" "exec line: PI_MANAGED_INSTALL_ROOT"
case "$(grep '^PATH=' "$H/node-run")" in
  "PATH=$T/bin:$MG/node24/bin:"*) ;;
  *) h_assert_eq "PATH=$T/bin:$MG/node24/bin:..." "$(grep '^PATH=' "$H/node-run")" "exec line: PATH starts with tree/bin:node24/bin" ;;
esac
case "$(grep '^PATH=' "$H/node-run")" in
  *":$MG/fd/bin:$MG/rg/bin") ;;
  *) h_assert_eq "PATH=...:$MG/fd/bin:$MG/rg/bin" "$(grep '^PATH=' "$H/node-run")" "exec line: PATH ends with the fd and rg bins" ;;
esac
h_assert_eq "$MG/fd/bin/fd" "$(readlink "$HOME/.pi/agent/bin/fd")" "exec line: fd symlink"
h_assert_eq "$MG/rg/bin/rg" "$(readlink "$HOME/.pi/agent/bin/rg")" "exec line: rg symlink"
h_assert_eq 0 "$(calls)" "exec line: no npm"
PI_OFFLINE=true; export PI_OFFLINE
launch --help
unset PI_OFFLINE
h_assert_eq "PI_OFFLINE=true" "$(grep '^PI_OFFLINE=' "$H/node-run")" "exec line: a user's PI_OFFLINE reaches Pi unchanged"

fresh
launch --version
h_assert_eq 0 "$rc" "first run: exits 0"
h_assert_eq 1 "$(calls)" "first run: npm ran once"
printf '%s\n' "$MARKER" > "$H/marker"
h_assert_ok cmp -s "$H/marker" "$R/managed-install.json"
printf '%s\n' "$V" > "$H/cv"
h_assert_ok cmp -s "$H/cv" "$R/current-version"
h_assert_ok test -x "$ENTRY"
h_assert_eq "arg=$ENTRY
arg=--version" "$(grep '^arg=' "$H/node-run")" "first run: node exec'd on the seeded entry"

fresh
seed "$V"
printf '%s\n' "$V" > "$R/current-version"
launch "a b" "" "-x" "--" "*" 'c"d'
h_assert_eq "arg=$ENTRY
arg=a b
arg=
arg=-x
arg=--
arg=*
arg=c\"d" "$(grep '^arg=' "$H/node-run")" "args forwarded verbatim"
launch
h_assert_eq "arg=$ENTRY" "$(grep '^arg=' "$H/node-run")" "no args: only the entry"

FAKE_NODE_RC=7; export FAKE_NODE_RC
launch
unset FAKE_NODE_RC
h_assert_eq 7 "$rc" "node's exit status is the launcher's"

fresh
seed 1.0.0
seed 1.0.5
printf '9.9.9\n' > "$R/current-version"
launch --help
h_assert_eq 0 "$rc" "dangling pointer: exits 0"
h_assert_eq 0 "$(calls)" "dangling pointer: no npm"
h_assert_eq "arg=$R/releases/1.0.5/node_modules/.bin/pi
arg=--help" "$(grep '^arg=' "$H/node-run")" "dangling pointer: runs newest release"
h_assert_eq "1.0.5" "$(cat "$R/current-version")" "dangling pointer: repaired"

fresh
rm "$H/api/$V/package-lock.json"
launch --help
h_fixture "$V"
h_assert_eq 1 "$(nonzero "$rc")" "staging failure: non-zero"
h_assert_absent "$H/node-run" "staging failure: node never run"
h_assert_contains "$(cat "$H/err")" "package-lock.json" "staging failure: clear stderr"

fresh
FAKE_NPM_FAIL=1; export FAKE_NPM_FAIL
launch --help
unset FAKE_NPM_FAIL
h_assert_eq 1 "$(nonzero "$rc")" "npm failure: non-zero"
h_assert_absent "$H/node-run" "npm failure: node never run"

fresh
seed "$V"
printf '%s\n' "$V" > "$R/current-version"
mkdir -p "$N/darwin/src" "$(dirname "$X64")"
printf 'objc source\n' > "$N/darwin/src/darwin-platform.m"
printf 'clipboard header\n' > "$N/clipboard.h"
printf 'napi header\n' > "$N/napi.h"
printf 'upstream x64 addon\n' > "$X64"
printf 'our 10.9 addon\n' > "$T/share/pi/darwin-platform.node"
cat "$N/darwin/src/darwin-platform.m" "$N/clipboard.h" "$N/napi.h" | shasum -a 256 | cut -d' ' -f1 > "$T/share/pi/addon-source-id"
launch --help
h_assert_eq 0 "$rc" "addon: exits 0"
h_assert_ok cmp -s "$T/share/pi/darwin-platform.node" "$X64"

fresh
mv "$MG/rg/mavergreen.plist" "$MG/rg/gone"
launch --help
mv "$MG/rg/gone" "$MG/rg/mavergreen.plist"
h_assert_eq 1 "$(nonzero "$rc")" "missing product: non-zero"
h_assert_contains "$(cat "$H/err")" "pi: rg is not installed" "missing product: message"
h_assert_absent "$HOME/.pi" "missing product: no state written"
h_assert_absent "$HOME/Library" "missing product: no Library state"
h_assert_absent "$H/node-run" "missing product: node never run"

fresh
seed "$V"
printf '%s\n' "$V" > "$R/current-version"
printf '{"kind":"pi-managed-install","schemaVersion":2,"layout":"releases-v2"}\n' > "$R/managed-install.json"
launch --help
h_assert_eq 1 "$(nonzero "$rc")" "unknown marker: non-zero"
h_assert_contains "$(cat "$H/err")" "only releases-v1" "unknown marker: says what the wrapper understands"
h_assert_absent "$H/node-run" "unknown marker: node never run"
h_assert_eq 0 "$(calls)" "unknown marker: no npm"
h_assert_contains "$(cat "$R/managed-install.json")" '"schemaVersion":2' "unknown marker: left as found"
h_done
