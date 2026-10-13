#!/bin/sh
# platform: macOS-only -- builds and inspects a Mach-O AppKit addon with Apple clang against the pinned Mac OS X 10.9 SDK
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
[ -f "$H_REPO/build/msc.sh" ] || { echo "FAIL: no build/msc.sh" >&2; exit 1; }
[ -f "$H_REPO/build/build-addon.sh" ] || { echo "FAIL: no build/build-addon.sh" >&2; exit 1; }
if [ -z "${SHIPYARD_SCRIPTS:-}" ] || [ ! -d "$SHIPYARD_SCRIPTS" ]; then
  . "$H_REPO/build/msc.sh" || exit 1
fi
[ -f "$H_REPO/tree/libexec/pi/lib.sh" ] || exit 1
. "$H_REPO/tree/libexec/pi/lib.sh"
[ -f "$H_REPO/tree/libexec/pi/addon.sh" ] || exit 1
. "$H_REPO/tree/libexec/pi/addon.sh"

LIPO="${LIPO:-lipo}"
OTOOL="${OTOOL:-otool}"
NM="${NM:-nm}"
export LIPO OTOOL NM
NODE24=/usr/local/mavergreen/node24/bin/node
GUARD="$SHIPYARD_SCRIPTS/assert_binary_compatible.sh"

guard() {
  MAVERICKS_DEVIATIONS_ROOT="$H_REPO" MAVERICKS_ALLOW_ARCHS=x86_64 MAVERICKS_REQUIRE_DEFINED_SYMBOLS= \
    sh "$GUARD" "$1" >"$H/guard.out" 2>&1
}

archs() { "$LIPO" -info "$1" 2>/dev/null | sed "s/.*: //"; }

minos_of() {
  "$OTOOL" -l "$1" | awk '
    $1 == "cmd" && ($2 == "LC_VERSION_MIN_MACOSX" || $2 == "LC_BUILD_VERSION") { inlc = 1; next }
    $1 == "cmd" { inlc = 0 }
    inlc && ($1 == "version" || $1 == "minos") { print $2; exit }'
}

HOME="$H_ORIG_HOME" sh "$H_REPO/build/build-addon.sh" > "$H/build.out" || { echo "FAIL: build/build-addon.sh failed" >&2; exit 1; }
OUT="$(tail -n 1 "$H/build.out")"
NODE_FILE="$OUT/darwin-platform.node"
[ -f "$NODE_FILE" ] || { echo "FAIL: no $NODE_FILE" >&2; exit 1; }
NATIVE="$OUT/src/package/native"

h_assert_ok guard "$NODE_FILE"

h_assert_eq "x86_64" "$(archs "$NODE_FILE")" "the built addon is x86_64-only"

h_assert_eq "10.9" "$(minos_of "$NODE_FILE")" "the built addon's minos is 10.9"

want_id="$(pi_addon_source_id "$NATIVE")" || want_id="unavailable"
h_assert_eq "$want_id" "$(tr -d ' \t\r\n' < "$OUT/addon-source-id")" "addon-source-id equals the id of the fetched pi-tui native sources"

UP="$NATIVE/darwin/prebuilds/darwin-x64/darwin-platform.node"
if [ ! -f "$UP" ]; then
  echo "FAIL: upstream's prebuilt darwin-x64 addon is not in the fetched tarball: $UP" >&2
  H_FAILS=$((H_FAILS+1))
elif [ ! -f "$GUARD" ]; then
  echo "FAIL: the compat guard is missing: $GUARD" >&2
  H_FAILS=$((H_FAILS+1))
else
  guard "$UP" && rc=0 || rc=$?
  gout="$(cat "$H/guard.out")"
  h_assert_contains "$gout" "compat guard" "the guard ran on upstream's addon"
  case "$rc" in 0|126|127) echo "FAIL: guard exit status $rc is not a rejection of upstream's addon" >&2; H_FAILS=$((H_FAILS+1)) ;; esac
  upmin="$(minos_of "$UP")"
  if [ -n "$upmin" ]; then
    [ "$upmin" != "10.9" ] || { echo "FAIL: upstream's addon reads as minos 10.9" >&2; H_FAILS=$((H_FAILS+1)); }
    h_assert_contains "$gout" "minos" "the guard rejects upstream's addon (minos $upmin) by naming the minos pin"
  else
    h_assert_contains "$gout" "CANNOT MEASURE" "this host's tools cannot read upstream's addon, so the guard rejects it by failing closed (CANNOT MEASURE), not on a measured minos"
  fi
fi

if [ -x "$NODE24" ] && [ "$(archs "$NODE24")" = x86_64 ]; then
  loaded="$("$NODE24" -e '
    const m = { exports: {} };
    process.dlopen(m, process.argv[1]);
    const want = ["isModifierPressed", "getText", "setText", "getImage", "getFilePaths"];
    console.log(want.filter((k) => typeof m.exports[k] !== "function").join(" ") || "ok");
  ' "$NODE_FILE" 2>&1)" || loaded="dlopen failed: $loaded"
  h_assert_eq "ok" "$loaded" "process.dlopen exposes isModifierPressed, getText, setText, getImage, getFilePaths"
elif [ -n "${CI:-}" ]; then
  echo "FAIL: CI requires the dlopen check, and there is no x86_64 node24 at $NODE24 -- the release workflow installs node24 and primes Rosetta before the tests" >&2
  H_FAILS=$((H_FAILS+1))
else
  echo "addon-compat: dlopen check not exercised on this host (no x86_64 node24 at $NODE24)"
fi
h_done
