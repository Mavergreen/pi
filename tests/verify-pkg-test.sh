#!/bin/sh
# platform: macOS-only -- builds packages with pkgbuild/productbuild and expands them with pkgutil
set -eu
. "$(dirname "$0")/lib/harness.sh"
if [ -z "${SHIPYARD_SCRIPTS:-}" ] || [ ! -d "$SHIPYARD_SCRIPTS" ]; then
  . "$H_REPO/build/msc.sh" || exit 1
fi
h_setup
VP="$H_REPO/packaging/verify-pkg.sh"
printf 'pi dev.mavergreen.pi pi\n' > "$H/product-names"
MAVERGREEN_PRODUCT_NAMES="$H/product-names"
export MAVERGREEN_PRODUCT_NAMES
UV="$(tr -d ' \t\r\n' < "$H_REPO/UPSTREAM_VERSION")"

A="$H/addon"
mkdir "$A"
printf 'addon bytes\n' > "$A/darwin-platform.node"
printf '%064d\n' 7 > "$A/addon-source-id"

mk() {
  r="$H/$1"
  t="$r/usr/local/mavergreen/pi"
  mkdir -p "$t/bin" "$t/libexec/pi" "$t/share/pi" "$t/share/doc/pi" "$r/Library/Application Support/Mavergreen/pi-updater.app/Contents"
  printf '#!/bin/sh\n' > "$t/bin/pi"; chmod +x "$t/bin/pi"
  for _m in lib select stage addon env; do printf ':\n' > "$t/libexec/pi/$_m.sh"; done
  : > "$t/mavergreen.plist"
  printf 'node24 https://example.invalid\n' > "$t/share/pi/requires"
  cp "$A/darwin-platform.node" "$A/addon-source-id" "$t/share/pi/"
  printf '%s\n' "$UV" > "$t/share/pi/seed-version"
  printf '# readme\n' > "$t/share/doc/pi/README.md"
  printf 'license\n' > "$t/share/doc/pi/LICENSE"
  printf 'notice\n' > "$t/share/doc/pi/NOTICE"
  : > "$r/Library/Application Support/Mavergreen/pi-updater.app/Contents/Info.plist"
}
comp() { pkgbuild --root "$H/$1" --identifier "$2" --version 1 --install-location / "$H/$3" >/dev/null 2>&1; }
build() { comp "$1" dev.mavergreen.pi "$1.pkg"; }
refused() {
  rc=0; out="$(sh "$VP" "$H/$1.pkg" "$A" 2>&1)" || rc=$?
  h_assert_eq 1 "$rc" "$2 fails"
  h_assert_contains "$out" "$3" "$2: the failure says so"
}

mk good; build good
h_assert_ok sh "$VP" "$H/good.pkg" "$A"

for f in bin/pi libexec/pi/lib.sh libexec/pi/select.sh libexec/pi/stage.sh libexec/pi/addon.sh libexec/pi/env.sh \
         mavergreen.plist share/pi/requires share/pi/darwin-platform.node share/pi/addon-source-id share/pi/seed-version \
         share/doc/pi/README.md share/doc/pi/LICENSE share/doc/pi/NOTICE; do
  n="no$(printf '%s' "$f" | tr '/.' '__')"
  mk "$n"; rm "$H/$n/usr/local/mavergreen/pi/$f"; build "$n"
  refused "$n" "a payload without $f" "payload lacks usr/local/mavergreen/pi/$f"
done
mk noupdater; rm -rf "$H/noupdater/Library"; build noupdater
refused noupdater "a payload without the updater" "payload lacks Library/Application Support/Mavergreen/pi-updater.app"
mk noxpi; chmod -x "$H/noxpi/usr/local/mavergreen/pi/bin/pi"; build noxpi
refused noxpi "a bin/pi that is not executable" "usr/local/mavergreen/pi/bin/pi is not executable"
mk scratch; printf '{}\n' > "$H/scratch/usr/local/mavergreen/pi/share/pi/manifest.json"; build scratch
refused scratch "a share/pi carrying build-addon's scratch" "share/pi holds manifest.json"
mk otheraddon; printf 'other bytes\n' > "$H/otheraddon/usr/local/mavergreen/pi/share/pi/darwin-platform.node"; build otheraddon
refused otheraddon "an addon other than the one built" "share/pi/darwin-platform.node differs from $A/darwin-platform.node"
mk otherid; printf '%064d\n' 8 > "$H/otherid/usr/local/mavergreen/pi/share/pi/addon-source-id"; build otherid
refused otherid "an addon-source-id other than the one built" "share/pi/addon-source-id differs from $A/addon-source-id"
mk oldseed; printf '0.0.1\n' > "$H/oldseed/usr/local/mavergreen/pi/share/pi/seed-version"; build oldseed
refused oldseed "a seed-version other than UPSTREAM_VERSION" "share/pi/seed-version is 0.0.1, not UPSTREAM_VERSION ($UV)"

rc=0; out="$(sh "$VP" "$H/good.pkg" 2>&1)" || rc=$?
h_assert_eq 2 "$rc" "a missing argument exits 2"
h_assert_contains "$out" "usage: verify-pkg.sh PKG ADDON-DIR" "and prints the usage"

mkdir -p "$H/base/usr/local/mavergreen/.base"; : > "$H/base/usr/local/mavergreen/.base/file"
comp base dev.mavergreen.base base.pkg
productbuild --package "$H/base.pkg" --package "$H/good.pkg" "$H/prod.pkg" >/dev/null 2>&1
h_assert_ok sh "$VP" "$H/prod.pkg" "$A"
comp good dev.mavergreen.other other.pkg
productbuild --package "$H/base.pkg" --package "$H/other.pkg" "$H/noprod.pkg" >/dev/null 2>&1
rc=0; out="$(sh "$VP" "$H/noprod.pkg" "$A" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "a product archive without the pi component fails"
h_assert_eq "verify-pkg: extract-component: $H/noprod.pkg has no component dev.mavergreen.pi" "$out" "the failure names the identifier, through extract-component"
h_done
