#!/bin/sh
# platform: macOS-only -- the tests drive the launcher, which targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
T="$H/root/usr/local/mavergreen/pi"
. "$T/libexec/pi/lib.sh"
. "$T/libexec/pi/select.sh"
pi_init "$T/bin/pi"
R="$PI_MROOT"

mkrel() {
  mkdir -p "$R/releases/$1/node_modules/.bin"
  printf '#!/bin/sh\n' > "$R/releases/$1/node_modules/.bin/pi"
  chmod +x "$R/releases/$1/node_modules/.bin/pi"
}
marker() { printf '{"kind":"pi-managed-install","schemaVersion":1,"layout":"releases-v1"}\n' > "$R/managed-install.json"; }
choose() { pi_choose >/dev/null 2>"$H/err" && rc=0 || rc=$?; }

mkdir -p "$R/releases"
r=$(pi_choose 2>&1) && rc=0 || rc=$?
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "empty tree: non-zero"
h_assert_eq "" "$r" "empty tree: silent"

mkrel 1.0.0; mkrel 1.1.0
printf '1.0.0\n' > "$R/current-version"
r=$(pi_choose 2>&1) && rc=0 || rc=$?
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "no marker: non-zero even with releases"
h_assert_eq "" "$r" "no marker: silent"
printf '{"kind":"other","schemaVersion":1,"layout":"releases-v1"}' > "$R/managed-install.json"
h_assert_fails pi_marker_valid
printf '{"kind":"pi-managed-install","schemaVersion":12,"layout":"releases-v1"}' > "$R/managed-install.json"
h_assert_fails pi_marker_valid
printf '{"kind":"pi-managed-install","schemaVersion":1,"layout":"x"}' > "$R/managed-install.json"
h_assert_fails pi_marker_valid
printf '{\n  "layout": "releases-v1",\n  "extra": true,\n  "schemaVersion": 1,\n  "kind": "pi-managed-install"\n}\n' > "$R/managed-install.json"
h_assert_ok pi_marker_valid
marker
h_assert_ok pi_marker_valid

h_assert_eq "1.0.0" "$(pi_choose)" "reads current-version"
h_assert_eq "$R/releases/1.1.0/node_modules/.bin/pi" "$(pi_entry 1.1.0)" "pi_entry"

printf '  1.1.0 \r\n' > "$R/current-version"
h_assert_eq "1.1.0" "$(pi_choose)" "whitespace stripped"

mkrel 1.9.9; mkrel 1.10.0
h_assert_eq "1.10.0" "$(pi_newest)" "newest picks 1.10.0 over 1.9.9"

mkdir -p "$R/releases/9.0.0-beta.1/node_modules/.bin" "$R/releases/garbage" "$R/releases/9.0.0"
printf x > "$R/releases/9.0.0-beta.1/node_modules/.bin/pi"
h_assert_eq "1.10.0" "$(pi_newest)" "ignores garbage and non-executable-bin dirs"
mkrel 9.0.0-beta.1
h_assert_eq "9.0.0-beta.1" "$(pi_newest)" "valid prerelease beats lower release"
rm -rf "$R/releases/9.0.0-beta.1"

printf '7.7.7\n' > "$R/current-version"
choose
h_assert_eq 0 "$rc" "dangling: succeeds"
h_assert_eq "1.10.0" "$(pi_choose 2>/dev/null)" "dangling: falls back to newest"
h_assert_eq "1.10.0" "$(cat "$R/current-version")" "repaired current-version"
h_assert_eq 7 "$(wc -c < "$R/current-version" | tr -d ' ')" "repair wrote exactly '<v>\\n'"
set -- "$R"/current-version.tmp.*
h_assert_absent "$1" "no tmp file left"
h_assert_contains "$(cat "$H/err")" "7.7.7" "note names the missing pointer"
h_assert_contains "$(cat "$H/err")" "1.10.0" "note names the version now running"

rm "$R/current-version"
choose
h_assert_eq "1.10.0" "$(pi_choose 2>/dev/null)" "absent pointer: newest"
h_assert_eq "1.10.0" "$(cat "$R/current-version")" "absent pointer: repaired"

printf 'garbage version\n' > "$R/current-version"
h_assert_eq "1.10.0" "$(pi_choose 2>/dev/null)" "invalid pointer: newest"

rm "$R/releases/1.10.0/node_modules/.bin/pi"
printf '1.10.0\n' > "$R/current-version"
h_assert_eq "1.9.9" "$(pi_choose 2>/dev/null)" "pointer to release lacking bin/pi: falls back"

rm -rf "$R/releases"; mkdir "$R/releases"
rm -f "$R/current-version"
h_assert_fails pi_newest >/dev/null
h_assert_fails pi_choose >/dev/null 2>&1
h_assert_absent "$R/current-version" "no release: nothing written"

marker; rm -f "$R/managed-install.json"
r=$(pi_choose 2>&1) && rc=0 || rc=$?
h_assert_eq "" "$r" "missing marker: silent"
