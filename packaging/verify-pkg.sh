#!/bin/sh
# platform: macOS-only -- expands the package with pkgutil
#   usage: verify-pkg.sh PKG ADDON-DIR
#          Fails, naming the first problem, unless PKG's dev.mavergreen.pi payload holds the launcher,
#          its modules, the manifest, the README and pi's updater, and its share/pi holds exactly the
#          requires list, ADDON-DIR's darwin-platform.node and addon-source-id byte for byte, and a
#          seed-version equal to UPSTREAM_VERSION.
set -eu
[ $# -eq 2 ] || { echo "usage: verify-pkg.sh PKG ADDON-DIR" >&2; exit 2; }
pkg="$1"; addon="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
[ -f "$pkg" ] || { echo "verify-pkg: no such package: $pkg" >&2; exit 1; }
[ -d "$addon" ] || { echo "verify-pkg: no such addon directory: $addon" >&2; exit 1; }
. "$REPO/build/msc.sh"
app="$(sh "$SHIPYARD/product-name.sh" updater-app pi)" || { echo "verify-pkg: pi has no updater in shipyard's scripts/product-names" >&2; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/verify-pkg.XXXXXX")"
trap 'rm -rf "$work"' EXIT
root="$work/root"
mkdir "$root"
err="$(sh "$HERE/extract-component.sh" "$pkg" dev.mavergreen.pi "$root" 2>&1)" || { echo "verify-pkg: $err" >&2; exit 1; }
t="$root/usr/local/mavergreen/pi"
need() { [ -e "$1" ] || { echo "verify-pkg: payload lacks ${1#"$root"/}" >&2; exit 1; }; }
needx() { need "$1"; [ -x "$1" ] || { echo "verify-pkg: ${1#"$root"/} is not executable" >&2; exit 1; }; }
needx "$t/bin/pi"
for m in lib select stage addon env; do need "$t/libexec/pi/$m.sh"; done
need "$t/mavergreen.plist"
for f in requires darwin-platform.node addon-source-id seed-version; do need "$t/share/pi/$f"; done
need "$t/share/doc/pi/README.md"
need "$root/$app"
for f in $(ls -A "$t/share/pi"); do
  case "$f" in
    requires|darwin-platform.node|addon-source-id|seed-version) ;;
    *) echo "verify-pkg: share/pi holds $f, which is none of requires, darwin-platform.node, addon-source-id and seed-version" >&2; exit 1 ;;
  esac
done
for f in darwin-platform.node addon-source-id; do
  cmp -s "$t/share/pi/$f" "$addon/$f" \
    || { echo "verify-pkg: share/pi/$f differs from $addon/$f" >&2; exit 1; }
done
want="$(tr -d ' \t\r\n' < "$REPO/UPSTREAM_VERSION")"
got="$(cat "$t/share/pi/seed-version")"
[ "$got" = "$want" ] || { echo "verify-pkg: share/pi/seed-version is $got, not UPSTREAM_VERSION ($want)" >&2; exit 1; }
