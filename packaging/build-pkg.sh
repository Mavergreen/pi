#!/bin/sh
# platform: macOS-only -- drives shipyard's stage_product.sh, build_component_pkg.sh and set_install_floor.sh
#   usage: build-pkg.sh BUILD-DIR ADDON-DIR VERSION OUT.pkg
#          Stages tree/ as committed, the 10.9 addon and its addon-source-id from ADDON-DIR (what
#          build/build-addon.sh printed), share/pi/seed-version from UPSTREAM_VERSION, the LICENSE, NOTICE, README and
#          BUILD-DIR's updater under /usr/local/mavergreen/pi, and wraps them in a 10.9.5-floored
#          product archive.
set -eu
usage='usage: build-pkg.sh BUILD-DIR ADDON-DIR VERSION OUT.pkg'
[ $# -eq 4 ] || { echo "$usage" >&2; exit 2; }
B=$1; A=$2; V=$3; OUT=$4
REPO=$(cd "$(dirname "$0")/.." && pwd)
die() { echo "build-pkg: $*" >&2; exit 1; }
. "$REPO/build/msc.sh"
APPREL=$(sh "$SHIPYARD/product-name.sh" updater-app pi) || die "pi has no updater in shipyard's scripts/product-names"
APP="$B/${APPREL##*/}"
[ -d "$APP" ] || die "no updater at $APP; configure with -DPI_BUILD_UPDATER=ON"
for f in darwin-platform.node addon-source-id; do
  [ -f "$A/$f" ] || die "no $A/$f; run build/build-addon.sh"
done
SEED=$(tr -d ' \t\r\n' < "$REPO/UPSTREAM_VERSION")
[ -n "$SEED" ] || die "UPSTREAM_VERSION is empty"
work=$(mktemp -d "${TMPDIR:-/tmp}/pi-pkg.XXXXXX")
trap 'rm -rf "$work"' EXIT
ROOT=$work/root
T=$ROOT/usr/local/mavergreen/pi
install -d "$T" "$T/share/pi" "$T/share/doc/pi"
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git -C "$REPO" status --porcelain -- tree)" ]; then
    echo "build-pkg: tree/ has uncommitted changes, which this package leaves out (it stages tree/ as committed at HEAD)" >&2
  fi
  git -C "$REPO" archive -o "$work/tree.tar" HEAD tree
  tar -xf "$work/tree.tar" -C "$work"
  rm -f "$work/tree.tar"
  cp -Rp "$work/tree/." "$T/"
  rm -rf "$work/tree"
else
  echo "build-pkg: no git here; staging tree/ as it is on disk, tracked or not" >&2
  cp -Rp "$REPO/tree/." "$T/"
fi
install -m 0644 "$A/darwin-platform.node" "$A/addon-source-id" "$T/share/pi/"
printf '%s\n' "$SEED" > "$T/share/pi/seed-version"
chmod 0644 "$T/share/pi/seed-version"
install -m 0644 "$REPO/LICENSE" "$REPO/NOTICE" "$REPO/README.md" "$T/share/doc/pi/"
find "$ROOT" -name '._*' -delete
set --
while read -r short _url || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  set -- "$@" --requires "$short"
done < "$T/share/pi/requires"
sh "$SHIPYARD/stage_product.sh" --stage "$ROOT" --product pi --name "Mavericks Pi" \
  --version "$V" "$@" --scripts-out "$work/scripts" --updater-app "$APP" \
  --preinstall-hook "$REPO/packaging/preinstall-hook.sh"
sh "$SHIPYARD/build_component_pkg.sh" --root "$ROOT" --identifier dev.mavergreen.pi \
  --version "$V" --install-location / --scripts "$work/scripts" --out "$work/pi-component.pkg" >&2
mkdir -p "$(dirname "$OUT")"
sh "$SHIPYARD/set_install_floor.sh" --identifier dev.mavergreen.pi --title "Pi for Mavericks" \
  --component "$work/pi-component.pkg" --out "$OUT" --require-scripts --host-arch x86_64 >&2
echo "built $OUT"
