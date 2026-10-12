#!/bin/sh
# platform: macOS-only -- the tests drive the launcher, which targets Mac OS X 10.9's sh and tools
#   usage: . "$(dirname "$0")/lib/fixtures.sh" after h_setup; h_fake_npm installs a fake npm in node24/bin, h_fixture VERSION writes the installer-API fixture for $V, h_api_base points PI_INSTALLER_API_BASE at it.

h_fake_npm() {
  mkdir -p "$MG/node24/bin"
  cat > "$MG/node24/bin/npm" <<'NPM'
#!/bin/sh
printf '%s|%s|%s\n' "$(pwd -P)" "$*" "$(command -v node)" >> "$H/npm-calls"
sleep "${FAKE_NPM_SLEEP:-0}"
if [ -n "${FAKE_NPM_LOCKAGE-}" ]; then
  echo $(( $(date +%s) - $(stat -f %m "$FAKE_NPM_LOCKAGE") )) > "$H/lock-age"
fi
[ -z "${FAKE_NPM_FAIL-}" ] || exit 3
v="$(node -e 'console.log(require("./package.json").version)')"
mkdir -p node_modules/.bin
printf '#!/bin/sh\necho %s\n' "${FAKE_PI_VERSION:-$v}" > node_modules/.bin/pi
chmod +x node_modules/.bin/pi
NPM
  chmod +x "$MG/node24/bin/npm"
}

h_fixture() {
  mkdir -p "$H/api/$V"
  printf '{"name":"pi-managed","version":"%s","dependencies":{"%s":"%s"}}\n' "$1" "$PKG" "$1" > "$H/api/$V/package.json"
  printf '{"name":"pi-managed","version":"%s","lockfileVersion":3,"packages":{"":{"version":"%s","dependencies":{"%s":"%s"}},"node_modules/%s":{"version":"%s"}}}\n' \
    "$1" "$1" "$PKG" "$1" "$PKG" "$1" > "$H/api/$V/package-lock.json"
}

h_api_base() {
  PI_INSTALLER_API_BASE="file://$(printf %s "$H" | sed 's/ /%20/g')/api//"
  export PI_INSTALLER_API_BASE
}
