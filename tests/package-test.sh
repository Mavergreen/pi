#!/bin/sh
# platform: macOS-only -- builds the product archive with shipyard's pkgbuild/productbuild scripts and expands it with pkgutil
set -eu
. "$(dirname "$0")/lib/harness.sh"
if [ -z "${SHIPYARD_SCRIPTS:-}" ] || [ ! -d "$SHIPYARD_SCRIPTS" ]; then
  . "$H_REPO/build/msc.sh" || exit 1
fi
h_setup
PK="$H_REPO/packaging"
PN="$SHIPYARD_SCRIPTS/product-name.sh"

shorts_of() {
  _so=""
  while read -r _s _u || [ -n "$_s" ]; do
    [ -n "$_s" ] || continue
    _so="$_so${_so:+ }$_s"
  done < "$1"
  printf '%s\n' "$_so"
}
REQS="$(shorts_of "$H_REPO/tree/share/pi/requires")"
[ -n "$REQS" ] || { echo "FAIL: tree/share/pi/requires names no product" >&2; exit 1; }
unreg=""
for short in pi $REQS; do
  sh "$PN" repo "$short" >/dev/null 2>&1 || unreg="$unreg $short"
done
[ -z "$unreg" ] || {
  echo "FAIL: not registered in ${MAVERGREEN_PRODUCT_NAMES:-$SHIPYARD_SCRIPTS/product-names}:$unreg -- register each in shipyard's scripts/product-names first; nothing packages for an unregistered name" >&2
  exit 1
}
h_assert_eq dev.mavergreen.pi "$(sh "$PN" identifier pi)" "the registry gives pi the identifier dev.mavergreen.pi"

R="$H/repo"
mkdir -p "$R/build"
cp -R "$PK" "$H_REPO/tree" "$R/"
cp "$H_REPO/build/msc.sh" "$R/build/"
cp "$H_REPO/UPSTREAM_VERSION" "$H_REPO/LICENSE" "$H_REPO/NOTICE" "$H_REPO/README.md" "$R/"
printf '%s' "$(cat "$R/tree/share/pi/requires")" > "$R/tree/share/pi/requires"
[ "$(tail -c 1 "$R/tree/share/pi/requires" | od -An -c | tr -d ' ')" != '\n' ] \
  || { echo "FAIL: the fixture's requires still ends in a newline" >&2; exit 1; }
git -C "$R" init -q
git -C "$R" add -A
git -C "$R" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm fixture
UV="$(tr -d ' \t\r\n' < "$R/UPSTREAM_VERSION")"

APPREL="$(sh "$PN" updater-app pi)"
B="$H/b"
mkdir -p "$B/${APPREL##*/}/Contents/MacOS"
printf '#!/bin/sh\n' > "$B/${APPREL##*/}/Contents/MacOS/pi-updater"
chmod +x "$B/${APPREL##*/}/Contents/MacOS/pi-updater"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $(sh "$PN" updater-bundle-id pi)" \
  -c "Add :SUFeedURL string $(sh "$PN" feed pi)" -c 'Add :CFBundleExecutable string pi-updater' \
  -c 'Add :CFBundlePackageType string APPL' "$B/${APPREL##*/}/Contents/Info.plist" >/dev/null

A="$H/addon"
mkdir -p "$A/src/package/native"
printf 'addon bytes\n' > "$A/darwin-platform.node"
printf '%064d\n' 7 > "$A/addon-source-id"
printf '{}\n' > "$A/manifest.json"
printf 'tarball\n' > "$A/pi-tui-0.0.1.tgz"
: > "$A/src/package/native/clipboard.h"

V="$UV-mavericks.1"
bp() { sh "$R/packaging/build-pkg.sh" "$B" "$A" "$V" "$1"; }
rc=0; out="$(bp "$H/dist/pi-$V.pkg" 2>&1)" || rc=$?
h_assert_eq 0 "$rc" "build-pkg builds the product archive: $out"
case "$out" in *uncommitted*) h_assert_eq "no warning" "$out" "a committed tree/ draws no warning" ;; esac
P="$H/dist/pi-$V.pkg"
[ -f "$P" ] || { echo "FAIL: no $P" >&2; exit 1; }

rc=0; vout="$(sh "$PK/verify-pkg.sh" "$P" "$A" 2>&1)" || rc=$?
h_assert_eq 0 "$rc" "verify-pkg accepts what build-pkg built: $vout"
rc=0; iout="$(sh "$SHIPYARD_SCRIPTS/assert_pkg_installs_in_place.sh" "$P" 2>&1)" || rc=$?
h_assert_eq 0 "$rc" "no bundle in the archive relocates or version-skips: $iout"

X="$H/x"
mkdir -p "$X/root"
pkgutil --expand "$P" "$X/e"
sh "$PK/extract-component.sh" "$P" dev.mavergreen.pi "$X/root"
T="$X/root/usr/local/mavergreen/pi"
h_assert_eq "addon-source-id
darwin-platform.node
requires
seed-version" "$(ls -A "$T/share/pi")" "share/pi holds the requires, the addon, its source id and the seed version, and none of build-addon's scratch"
h_assert_eq "$UV" "$(cat "$T/share/pi/seed-version")" "seed-version is UPSTREAM_VERSION"
h_assert_ok cmp -s "$A/darwin-platform.node" "$T/share/pi/darwin-platform.node"
h_assert_ok cmp -s "$A/addon-source-id" "$T/share/pi/addon-source-id"
h_assert_ok cmp -s "$R/tree/share/pi/requires" "$T/share/pi/requires"
h_assert_eq "LICENSE
NOTICE
README.md" "$(ls -A "$T/share/doc/pi")" "the docs are the LICENSE, the NOTICE for the addon's MIT source, and the README"
h_assert_contains "$(cat "$T/share/doc/pi/NOTICE")" "Copyright (c) 2025 Mario Zechner" "the NOTICE carries pi-tui's copyright line"
h_assert_eq "addon.sh env.sh lib.sh select.sh stage.sh" "$(ls "$T/libexec/pi" | tr '\n' ' ' | sed 's/ $//')" "libexec/pi holds the launcher's modules"
h_assert_ok test -x "$T/bin/pi"
h_assert_eq "bin libexec mavergreen.plist share" "$(ls "$T" | tr '\n' ' ' | sed 's/ $//')" "the tree holds bin, libexec, share and the manifest"
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$T/mavergreen.plist" 2>/dev/null || echo "<no $1>"; }
h_assert_eq pi "$(pb product)" "the manifest names product pi"
h_assert_eq "Mavericks Pi" "$(pb name)" "the manifest names it Mavericks Pi"
h_assert_eq dev.mavergreen.pi "$(pb identifier)" "the manifest's identifier"
h_assert_eq "$V" "$(pb version)" "the manifest's version"
h_assert_eq "$(sh "$PN" feed pi)" "$(pb appcast)" "the manifest's appcast is pi's feed"
h_assert_ok test -f "$X/root/$APPREL/Contents/Info.plist"
h_assert_ok test -f "$X/root/Library/LaunchAgents/$(sh "$PN" agent-label pi).plist"

dist="$X/e/Distribution"
h_assert_contains "$(cat "$dist")" '<os-version min="10.9.5"/>' "the archive's install floor is 10.9.5"
h_assert_contains "$(cat "$dist")" '<title>Pi for Mavericks</title>' "the installer's title"
h_assert_contains "$(cat "$dist")" 'hostArchitectures="x86_64"' "the archive is x86_64-only, like node24"
h_assert_eq "dev.mavergreen.base dev.mavergreen.pi" "$(sed -n 's/.*<pkg-ref id="\([^"]*\)".*/\1/p' "$dist" | awk '!s[$0]++' | tr '\n' ' ' | sed 's/ $//')" "the helper's base component comes first, then pi"
pre="$(find "$X/e" -path '*Scripts/preinstall' | head -n 1)"
[ -n "$pre" ] || { echo "FAIL: the pi component has no preinstall" >&2; exit 1; }
h_assert_eq "$REQS" "$(sed -n "s/.*Mavericks Pi needs \([^ ]*\) installed first.*/\1/p" "$pre" | tr '\n' ' ' | sed 's/ $//')" "the preinstall requires exactly share/pi/requires' products, in its order, its unterminated last line included"
h_assert_contains "$(cat "$pre")" "https://github.com/Mavergreen/nodejs-24/releases/latest" "and names where to get node24"

VOL="$H/vol"
for short in $REQS; do mkdir -p "$VOL/usr/local/mavergreen/$short"; : > "$VOL/usr/local/mavergreen/$short/mavergreen.plist"; done
HAND="$VOL/usr/local/mavergreen/node24/lib/node_modules/@earendil-works/pi-coding-agent"
mkdir -p "$HAND" "$VOL/usr/local/mavergreen/pi/bin"
: > "$VOL/usr/local/mavergreen/pi/bin/pi"
rc=0; out="$(sh "$pre" "$P" "$VOL" "$VOL/" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "the preinstall refuses a volume where Pi is installed by hand into node24"
h_assert_contains "$out" "sudo mavergreen --root '$VOL/' unlink node24 && sudo mavergreen --root '$VOL/' link node24" "and says how to clear it"
h_assert_ok test -f "$VOL/usr/local/mavergreen/pi/bin/pi"
rm -rf "$HAND"
rc=0; out="$(sh "$pre" "$P" "$VOL" "$VOL/" 2>&1)" || rc=$?
h_assert_eq 0 "$rc" "without it the preinstall goes on: $out"
h_assert_absent "$VOL/usr/local/mavergreen/pi" "and clears the outgoing tree"

cp "$R/tree/bin/pi" "$H/committed-pi"
printf '# a local edit\n' >> "$R/tree/bin/pi"
: > "$R/tree/untracked"
rc=0; out="$(bp "$H/dist2/pi.pkg" 2>&1)" || rc=$?
h_assert_eq 0 "$rc" "a tree/ with uncommitted changes still builds: $out"
h_assert_contains "$out" "build-pkg: tree/ has uncommitted changes, which this package leaves out (it stages tree/ as committed at HEAD)" "and warns that they are not in the package"
mkdir "$X/root2"
sh "$PK/extract-component.sh" "$H/dist2/pi.pkg" dev.mavergreen.pi "$X/root2"
h_assert_ok cmp -s "$H/committed-pi" "$X/root2/usr/local/mavergreen/pi/bin/pi"
h_assert_absent "$X/root2/usr/local/mavergreen/pi/untracked" "an untracked file in tree/ stays out of the package"
git -C "$R" checkout -q -- tree/bin/pi
rm -f "$R/tree/untracked"

rc=0; out="$(sh "$R/packaging/build-pkg.sh" "$B" "$A" "$V" 2>&1)" || rc=$?
h_assert_eq 2 "$rc" "a missing argument exits 2"
h_assert_contains "$out" "usage: build-pkg.sh BUILD-DIR ADDON-DIR VERSION OUT.pkg" "and prints the usage"

mkdir "$H/noaddon"
cp "$A/addon-source-id" "$H/noaddon/"
rc=0; out="$(sh "$R/packaging/build-pkg.sh" "$B" "$H/noaddon" "$V" "$H/dist3/pi.pkg" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "an addon dir without darwin-platform.node fails"
h_assert_contains "$out" "build-pkg: no $H/noaddon/darwin-platform.node; run build/build-addon.sh" "and says how to build it"
h_assert_absent "$H/dist3/pi.pkg" "and builds nothing"

mkdir "$H/noupdater"
rc=0; out="$(sh "$R/packaging/build-pkg.sh" "$H/noupdater" "$A" "$V" "$H/dist4/pi.pkg" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "a build dir without the updater fails"
h_assert_contains "$out" "configure with -DPI_BUILD_UPDATER=ON" "and says how to build it"
h_done
