#!/bin/sh
# platform: macOS-only -- the tests drive the launcher, which targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
. "$(dirname "$0")/lib/fixtures.sh"
h_setup
MG="$H/root/usr/local/mavergreen"
T="$MG/pi"
. "$T/libexec/pi/lib.sh"
. "$T/libexec/pi/select.sh"
. "$T/libexec/pi/stage.sh"

V=1.1.0
PKG=@earendil-works/pi-coding-agent
MARKER='{"kind":"pi-managed-install","schemaVersion":1,"layout":"releases-v1"}'
FLAGS='ci --ignore-scripts --min-release-age=0 --omit=dev --include=optional --no-fund --no-audit --loglevel=error --progress=false'

mkdir -p "$MG/node24/bin" "$T/share/pi"
ln -s /usr/local/mavergreen/node24/bin/node "$MG/node24/bin/node"
printf '%s\n' "$V" > "$T/share/pi/seed-version"

h_fake_npm

h_fixture "$V"
h_api_base

pi_init "$T/bin/pi"
R="$PI_MROOT"

calls() { if [ -f "$H/npm-calls" ]; then wc -l < "$H/npm-calls" | tr -d ' '; else echo 0; fi; }
stage() { pi_stage >"$H/out" 2>"$H/err" && rc=0 || rc=$?; }
fresh() { rm -rf "$R" "$H/npm-calls"; }
no_staging() {
  _what="$1"
  set -- "$R"/staging/update-*
  h_assert_absent "$1" "$_what: no staging/update-* left"
}
mtime_ago() { date -r $(( $(date +%s) - $1 )) +%Y%m%d%H%M.%S; }

stage
h_assert_eq 0 "$rc" "fresh: pi_stage succeeds"
h_assert_eq "" "$(cat "$H/out")" "fresh: nothing on stdout"
printf '%s\n' "$MARKER" > "$H/marker"
h_assert_ok cmp -s "$H/marker" "$R/managed-install.json"
h_assert_ok test -x "$R/releases/$V/node_modules/.bin/pi"
h_assert_eq "$V" "$("$R/releases/$V/node_modules/.bin/pi" --version)" "fresh: staged pi reports the seed version"
printf '%s\n' "$V" > "$H/cv"
h_assert_ok cmp -s "$H/cv" "$R/current-version"
h_assert_eq 1 "$(calls)" "fresh: one npm ci"
h_assert_eq "$FLAGS" "$(cut -d'|' -f2 "$H/npm-calls")" "fresh: npm ci flags match runManagedNpmCi"
h_assert_eq "$MG/node24/bin/node" "$(cut -d'|' -f3 "$H/npm-calls")" "fresh: node24 first on PATH for npm"
case "$(cut -d'|' -f1 "$H/npm-calls")" in
  "$R/staging/update-"??????) ;;
  *) h_assert_eq "$R/staging/update-XXXXXX" "$(cut -d'|' -f1 "$H/npm-calls")" "fresh: npm ci ran in staging/update-*" ;;
esac
no_staging "fresh"
h_assert_absent "$R/update.lock" "fresh: lock released"
set -- "$R"/*.tmp.*
h_assert_absent "$1" "fresh: no tmp files left"
jobs -p > "$H/jobs"
h_assert_eq "" "$(cat "$H/jobs")" "fresh: lock refresher reaped"
h_assert_ok pi_choose >/dev/null

stage
h_assert_eq 0 "$rc" "idempotent: succeeds"
h_assert_eq 1 "$(calls)" "idempotent: no second npm ci"
h_assert_eq "" "$(cat "$H/err")" "idempotent: silent"
mkdir "$R/update.lock"
stage
h_assert_eq 0 "$rc" "idempotent: returns without waiting on a held lock"
rmdir "$R/update.lock"

fresh
mkdir -p "$R/releases/$V/node_modules"
: > "$R/releases/$V/junk"
stage
h_assert_eq 0 "$rc" "partial: succeeds"
h_assert_eq 1 "$(calls)" "partial: invalid release is re-staged"
h_assert_absent "$R/releases/$V/junk" "partial: invalid release replaced, not merged"
h_assert_ok test -x "$R/releases/$V/node_modules/.bin/pi"
h_assert_ok pi_marker_valid
h_assert_eq "$V" "$(cat "$R/current-version")" "partial: pointer written"

rm -f "$R/managed-install.json" "$R/current-version" "$H/npm-calls"
: > "$R/releases/$V/kept"
stage
h_assert_eq 0 "$rc" "partial-valid: succeeds"
h_assert_eq 0 "$(calls)" "partial-valid: valid release reused, no npm ci"
h_assert_ok test -f "$R/releases/$V/kept"
h_assert_ok cmp -s "$H/marker" "$R/managed-install.json"
h_assert_ok cmp -s "$H/cv" "$R/current-version"

printf '9.9.9\n' > "$R/current-version"
stage
h_assert_eq 0 "$rc" "dangling pointer: succeeds"
h_assert_ok cmp -s "$H/cv" "$R/current-version"

rm -f "$H/npm-calls"
for foreign in '{"kind":"pi-managed-install","schemaVersion":2,"layout":"releases-v2"}' 'not json'; do
  printf '%s\n' "$foreign" > "$R/managed-install.json"
  printf '2.0.0\n' > "$R/current-version"
  stage
  h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "unknown marker ($foreign): refused"
  h_assert_contains "$(cat "$H/err")" "$R/managed-install.json" "unknown marker ($foreign): names the file"
  h_assert_contains "$(cat "$H/err")" "only releases-v1" "unknown marker ($foreign): says what is understood"
  h_assert_eq "$foreign" "$(cat "$R/managed-install.json")" "unknown marker ($foreign): marker untouched"
  h_assert_eq 2.0.0 "$(cat "$R/current-version")" "unknown marker ($foreign): current-version untouched"
  h_assert_eq 0 "$(calls)" "unknown marker ($foreign): no npm ci"
  h_assert_absent "$R/update.lock" "unknown marker ($foreign): lock released"
done
rm -f "$R/managed-install.json"
mkdir "$R/managed-install.json"
stage
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "marker is a directory: refused"
rmdir "$R/managed-install.json"
printf '%s\n' "$V" > "$R/current-version"
stage
h_assert_eq 0 "$rc" "missing marker beside a valid release: re-seeded"
h_assert_ok cmp -s "$H/marker" "$R/managed-install.json"
h_assert_eq 0 "$(calls)" "missing marker beside a valid release: no npm ci"

fresh
FAKE_NPM_SLEEP=2; export FAKE_NPM_SLEEP
( pi_stage >"$H/o1" 2>&1 && echo 0 > "$H/rc1" || echo $? > "$H/rc1" ) &
p1=$!
( pi_stage >"$H/o2" 2>&1 && echo 0 > "$H/rc2" || echo $? > "$H/rc2" ) &
p2=$!
wait "$p1" "$p2" || :
unset FAKE_NPM_SLEEP
h_assert_eq 0 "$(cat "$H/rc1")" "concurrent: first returns 0"
h_assert_eq 0 "$(cat "$H/rc2")" "concurrent: second returns 0"
h_assert_eq 1 "$(calls)" "concurrent: exactly one npm ci"
h_assert_eq "$V" "$(ls "$R/releases")" "concurrent: one release dir"
no_staging "concurrent"
h_assert_absent "$R/update.lock" "concurrent: lock released"
h_assert_ok cmp -s "$H/marker" "$R/managed-install.json"
h_assert_ok cmp -s "$H/cv" "$R/current-version"

fresh
FAKE_NPM_SLEEP=6 FAKE_NPM_LOCKAGE="$R/update.lock"; export FAKE_NPM_SLEEP FAKE_NPM_LOCKAGE
stage
unset FAKE_NPM_SLEEP FAKE_NPM_LOCKAGE
h_assert_eq 0 "$rc" "refresh: succeeds"
h_assert_eq 1 "$([ "$(cat "$H/lock-age")" -lt 5 ] && echo 1 || echo 0)" "refresh: lock mtime refreshed during npm ci (age $(cat "$H/lock-age")s)"

fresh
mkdir -p "$R/update.lock"
touch -t "$(mtime_ago 60)" "$R/update.lock"
stage
h_assert_eq 0 "$rc" "stale lock: broken and seeded"
h_assert_eq 1 "$(calls)" "stale lock: npm ci ran"
h_assert_absent "$R/update.lock" "stale lock: released"

printf '#!/bin/sh\nexit 1\n' > "$H/bin/stat"
chmod +x "$H/bin/stat"
fresh
mkdir -p "$R/update.lock"
touch -t "$(mtime_ago 60)" "$R/update.lock"
OPATH="$PATH"; PATH="$H/bin:$PATH"
stage
PATH="$OPATH"
h_assert_eq 0 "$rc" "GNU-style stat first on PATH: stale lock still broken"
h_assert_eq 1 "$(calls)" "GNU-style stat first on PATH: seeded"

fresh
mkdir -p "$R/update.lock"
touch -t "$(mtime_ago 60)" "$R/update.lock"
PI__STAT="$H/bin/stat" PI__LOCK_WAIT=2
stage
unset PI__STAT PI__LOCK_WAIT
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "unreadable lock mtime: bounded wait, then non-zero"
h_assert_contains "$(cat "$H/err")" "gave up after 2s" "unreadable lock mtime: treated as fresh and timed out"
h_assert_eq 0 "$(calls)" "unreadable lock mtime: npm ci never ran"
h_assert_ok test -d "$R/update.lock"
rmdir "$R/update.lock"

fresh
mkdir -p "$R/update.lock"
( pi_stage >"$H/o1" 2>&1 && echo 0 > "$H/rc1" || echo $? > "$H/rc1" ) &
p1=$!
sleep 2
h_assert_eq 0 "$(calls)" "held lock: waits"
h_assert_ok test -d "$R/update.lock"
rmdir "$R/update.lock"
wait "$p1" || :
h_assert_eq 0 "$(cat "$H/rc1")" "held lock: proceeds once released"
h_assert_eq 1 "$(calls)" "held lock: then seeds"

fresh
h_fixture 1.0.0
stage
h_fixture "$V"
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "validation: non-zero"
h_assert_eq 0 "$(calls)" "validation: npm ci never ran"
h_assert_eq "" "$(ls "$R/releases")" "validation: nothing in releases"
h_assert_absent "$R/managed-install.json" "validation: no marker"
h_assert_absent "$R/current-version" "validation: no pointer"
no_staging "validation"
h_assert_absent "$R/update.lock" "validation: lock released"
h_assert_contains "$(cat "$H/err")" "$PKG@$V" "validation: names the expected package"

fresh
rm "$H/api/$V/package-lock.json"
stage
h_fixture "$V"
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "download: non-zero"
h_assert_contains "$(cat "$H/err")" "package-lock.json" "download: names the artifact"
no_staging "download"
h_assert_absent "$R/managed-install.json" "download: no marker"

fresh
FAKE_NPM_FAIL=1; export FAKE_NPM_FAIL
stage
unset FAKE_NPM_FAIL
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "npm failure: non-zero"
h_assert_eq "" "$(ls "$R/releases")" "npm failure: nothing in releases"
no_staging "npm failure"
h_assert_absent "$R/managed-install.json" "npm failure: no marker"
h_assert_absent "$R/current-version" "npm failure: no pointer"
h_assert_absent "$R/update.lock" "npm failure: lock released"
jobs -p > "$H/jobs"
h_assert_eq "" "$(cat "$H/jobs")" "npm failure: lock refresher reaped"

fresh
FAKE_PI_VERSION=0.0.1; export FAKE_PI_VERSION
stage
unset FAKE_PI_VERSION
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "smoke: non-zero"
h_assert_contains "$(cat "$H/err")" "0.0.1" "smoke: names the version it got"
h_assert_eq "" "$(ls "$R/releases")" "smoke: nothing in releases"
no_staging "smoke"

fresh
FAKE_NPM_SLEEP=3; export FAKE_NPM_SLEEP
( pi_stage >"$H/o1" 2>&1; echo "survived $?" >> "$H/o1" ) &
p1=$!
sleep 1
kill -TERM "$p1"
wait "$p1" && rc=0 || rc=$?
unset FAKE_NPM_SLEEP
h_assert_eq 143 "$rc" "TERM: exits 128+15"
h_assert_eq "" "$(ls "$R/releases")" "TERM: nothing in releases"
no_staging "TERM"
h_assert_absent "$R/update.lock" "TERM: lock released"
h_assert_absent "$R/managed-install.json" "TERM: no marker"
h_assert_contains "$(cat "$H/o1")" "interrupted" "TERM: noted"

trap 'echo mine' INT
stage
trap > "$H/traps"
h_assert_contains "$(cat "$H/traps")" "echo mine" "prior INT trap restored"
case "$(cat "$H/traps")" in *TERM*) h_assert_eq "" "TERM trap left" "no TERM trap left behind" ;; esac
trap - INT

fresh
rm "$T/share/pi/seed-version"
r=$(pi_stage 2>&1) && rc=0 || rc=$?
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "no seed-version: non-zero"
h_assert_contains "$r" "seed-version" "no seed-version: names the file"
printf 'nope\n' > "$T/share/pi/seed-version"
r=$(pi_stage 2>&1) && rc=0 || rc=$?
h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "bad seed-version: non-zero"
h_assert_eq 0 "$(calls)" "bad seed-version: npm ci never ran"
