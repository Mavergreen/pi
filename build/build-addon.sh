#!/bin/sh
# platform: macOS-only -- compiles Pi's AppKit addon with Apple clang against the pinned Mac OS X 10.9 SDK
#   usage: build/build-addon.sh
#          Builds pi-tui's darwin-platform.node (x86_64, minos 10.9) from the source shipped in the
#          pi-tui tarball that the pinned Pi (UPSTREAM_VERSION) installs, gates it with the 10.9 compat
#          guard, and writes darwin-platform.node + addon-source-id to
#          ${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/<repo>-addon, whose path is the last
#          line on stdout. Knobs: CC (default /usr/bin/clang, must be Apple clang),
#          PI_INSTALLER_API_BASE (default https://pi.dev/api/installer/releases).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
die() { echo "build-addon: $*" >&2; exit 1; }
untrail() { _u="$1"; while :; do case "$_u" in ?*/) _u="${_u%/}" ;; *) break ;; esac; done; printf '%s\n' "$_u"; }
OUT="$(untrail "${MAVERICKS_BUILD_ROOT:-$(untrail "${TMPDIR:-/tmp}")/mm-build}")/$(basename "$ROOT")-addon"
rm -f "$OUT/darwin-platform.node" "$OUT/addon-source-id" "$OUT/manifest.json"
mkdir -p "$OUT"

. "$ROOT/build/msc.sh"
. "$ROOT/tree/libexec/pi/lib.sh"
. "$ROOT/tree/libexec/pi/addon.sh"

V="$(tr -d ' \t\r\n' < "$ROOT/UPSTREAM_VERSION")"
pi_is_version "$V" || die "UPSTREAM_VERSION is not a version: '$V'"

API="${PI_INSTALLER_API_BASE:-https://pi.dev/api/installer/releases}"
while :; do case "$API" in */) API="${API%/}" ;; *) break ;; esac; done

echo "build-addon: Pi $V: fetching $API/$V" >&2
curl -fsSL "$API/$V" -o "$OUT/manifest.json" || die "cannot fetch the installer manifest $API/$V"

# spec: .superpowers/sdd/2026-10-09-mavergreen-pi-wrapper/ref/manifest-1.1.0.json -- packages[] carries name, version, tarball, integrity
TUI="$(node -e '
const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const p = (m.packages || []).find((x) => x && x.name === "@earendil-works/pi-tui");
if (!p) { console.error("no @earendil-works/pi-tui entry in the manifest"); process.exit(1); }
for (const k of ["version", "tarball", "integrity"]) {
  if (typeof p[k] !== "string" || p[k] === "") { console.error("pi-tui entry has no " + k); process.exit(1); }
}
if (!/^sha512-[A-Za-z0-9+\/]+=*$/.test(p.integrity)) { console.error("pi-tui integrity is not a single sha512-: " + p.integrity); process.exit(1); }
if (!/^https:\/\//.test(p.tarball)) { console.error("pi-tui tarball is not https: " + p.tarball); process.exit(1); }
console.log([p.version, p.tarball, p.integrity].join("\n"));
' "$OUT/manifest.json")" || die "cannot read pi-tui from the manifest for Pi $V"
TUI_V="$(printf '%s\n' "$TUI" | sed -n 1p)"
TUI_URL="$(printf '%s\n' "$TUI" | sed -n 2p)"
TUI_SRI="$(printf '%s\n' "$TUI" | sed -n 3p)"
pi_is_version "$TUI_V" || die "pi-tui version is not a version: '$TUI_V'"

TGZ="$OUT/pi-tui-$TUI_V.tgz"
echo "build-addon: pi-tui $TUI_V: fetching $TUI_URL" >&2
curl -fsSL "$TUI_URL" -o "$TGZ" || die "cannot fetch $TUI_URL"
node -e '
const want = process.argv[2];
const got = "sha512-" + require("crypto").createHash("sha512").update(require("fs").readFileSync(process.argv[1])).digest("base64");
if (got !== want) { console.error("integrity mismatch for " + process.argv[1] + "\n  expected: " + want + "\n  got:      " + got); process.exit(1); }
' "$TGZ" "$TUI_SRI" || die "pi-tui $TUI_V tarball failed its integrity check"

SRC="$OUT/src"
rm -rf "$SRC"
mkdir "$SRC"
tar -xzf "$TGZ" -C "$SRC" || die "cannot extract $TGZ"
NATIVE="$SRC/package/native"
SOURCE_ID="$(pi_addon_source_id "$NATIVE")" || die "pi-tui $TUI_V lacks the addon sources under package/native"

CC="${CC:-/usr/bin/clang}"
"$CC" --version 2>&1 | grep -q Apple || die "CC=$CC is not Apple clang"
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)" || die "cannot fetch the pinned 10.9 SDK"

# spec: .superpowers/specs/2026-10-09-mavergreen-pi-design.md §3 -- upstream's darwin/build.sh flags for a 10.9 target, verified 2026-10-12
rm -f "$OUT/darwin-platform.o"
"$CC" -fobjc-arc -std=c11 -Wall -Wextra -Oz -fvisibility=hidden \
  -mmacosx-version-min=10.9 -arch x86_64 -DNSBitmapImageFileTypePNG=NSPNGFileType \
  -isysroot "$SDK" "-F$SDK/System/Library/Frameworks" \
  -c "$NATIVE/darwin/src/darwin-platform.m" -o "$OUT/darwin-platform.o" >&2 \
  || { rm -f "$OUT/darwin-platform.o" "$OUT/darwin-platform.node"; die "compiling darwin-platform.m failed"; }
# platform: linking without -fobjc-arc keeps clang from adding libarclite, which Xcode 14.3 and later
#           no longer ship; 10.9's libobjc has the ARC entry points natively, so it is not needed there
"$CC" -mmacosx-version-min=10.9 -arch x86_64 \
  -isysroot "$SDK" "-F$SDK/System/Library/Frameworks" \
  -bundle -undefined dynamic_lookup -Wl,-dead_strip -Wl,-x -fobjc-link-runtime \
  -framework AppKit -framework CoreGraphics -framework Foundation \
  "$OUT/darwin-platform.o" -o "$OUT/darwin-platform.node" >&2 \
  || { rm -f "$OUT/darwin-platform.o" "$OUT/darwin-platform.node"; die "linking darwin-platform.node failed"; }
rm -f "$OUT/darwin-platform.o"

if ! MAVERICKS_DEVIATIONS_ROOT="$ROOT" MAVERICKS_ALLOW_ARCHS=x86_64 MAVERICKS_REQUIRE_DEFINED_SYMBOLS= \
  sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$OUT/darwin-platform.node" >&2; then
  rm -f "$OUT/darwin-platform.node"
  die "darwin-platform.node failed the 10.9 compat guard"
fi

printf '%s\n' "$SOURCE_ID" > "$OUT/addon-source-id"
echo "build-addon: built darwin-platform.node for pi-tui $TUI_V, source id $SOURCE_ID" >&2
printf '%s\n' "$OUT"
