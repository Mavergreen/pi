#!/bin/sh
# platform: macOS-only -- the hook runs inside an Installer preinstall on Mac OS X 10.9
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
HOOK="$H_REPO/packaging/preinstall-hook.sh"
NM=usr/local/mavergreen/node24/lib/node_modules/@earendil-works/pi-coding-agent

h_assert_ok sh -n "$HOOK"
h_assert_eq "" "$(grep -nE '(^|[;&|[:space:]])(exit|set -e)([[:space:]]|$)' "$HOOK" || :)" "the hook has no exit and no set -e"

{
  printf '#!/bin/sh\nROOT="${3%%/}"\n(\n:\n'
  cat "$HOOK"
  printf '\n) || { echo "pi: preinstall hook failed" >&2; exit 1; }\necho "pi: past the hook"\nexit 0\n'
} > "$H/preinstall"
run() { sh "$H/preinstall" pkg dest "$1" >"$H/out" 2>"$H/err" && rc=0 || rc=$?; }

VOL="$H/vol ume"
mkdir -p "$VOL/usr/local/mavergreen/node24/bin"
run "$VOL/"
h_assert_eq 0 "$rc" "no hand-installed Pi: the preinstall goes on"
h_assert_eq "pi: past the hook" "$(cat "$H/out")" "no hand-installed Pi: past the hook"
h_assert_eq "" "$(cat "$H/err")" "no hand-installed Pi: silent"

mkdir -p "$VOL/$NM"
run "$VOL/"
h_assert_eq 1 "$rc" "hand-installed Pi in node24: the preinstall stops"
h_assert_eq "" "$(cat "$H/out")" "hand-installed Pi in node24: stops before anything after the hook"
h_assert_contains "$(cat "$H/err")" "$VOL/$NM" "hand-installed Pi in node24: names what it found"
h_assert_contains "$(cat "$H/err")" "  sudo rm -rf '$VOL/$NM' '$VOL/usr/local/mavergreen/node24/bin/pi'" "another volume: the remedy removes the package and its bin link there"
h_assert_contains "$(cat "$H/err")" "  sudo mavergreen --root '$VOL/' unlink node24 && sudo mavergreen --root '$VOL/' link node24" "another volume: the relink names that volume"
h_assert_contains "$(cat "$H/err")" "pi: preinstall hook failed" "hand-installed Pi in node24: the hook's verdict stops the preinstall"

rm -rf "$VOL/$NM"
mkdir -p "$VOL/usr/local/mavergreen/node24/lib/node_modules/@earendil-works"
ln -s /nonexistent "$VOL/$NM"
run "$VOL/"
h_assert_eq 1 "$rc" "a dangling link where the package was still stops the preinstall"

{
  printf '#!/bin/sh\nROOT=""\n(\n:\n'
  cat "$HOOK"
  printf '\n) || exit 1\nexit 0\n'
} > "$H/boot"
sh "$H/boot" >/dev/null 2>"$H/err" && rc=0 || rc=$?
if [ -e "/$NM" ] || [ -L "/$NM" ]; then
  h_assert_eq 1 "$rc" "the boot volume has Pi installed by hand into node24: refused"
  h_assert_contains "$(cat "$H/err")" "  sudo /usr/local/mavergreen/node24/bin/npm -g uninstall @earendil-works/pi-coding-agent" "boot volume: the remedy is node24's npm"
  h_assert_contains "$(cat "$H/err")" "  sudo mavergreen unlink node24 && sudo mavergreen link node24" "boot volume: then relink node24"
else
  h_assert_eq 0 "$rc" "the boot volume has no Pi installed into node24: allowed"
  h_assert_eq "" "$(cat "$H/err")" "boot volume: silent"
fi
