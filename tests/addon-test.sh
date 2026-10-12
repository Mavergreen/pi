#!/bin/sh
# platform: macOS-only -- the tests drive the launcher, which targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
T="$H/root/usr/local/mavergreen/pi"
. "$T/libexec/pi/lib.sh"
. "$T/libexec/pi/select.sh"
[ -f "$T/libexec/pi/addon.sh" ] || { echo "FAIL: no libexec/pi/addon.sh" >&2; exit 1; }
. "$T/libexec/pi/addon.sh"
pi_init "$T/bin/pi"

V=1.1.0
N="$PI_MROOT/releases/$V/node_modules/@earendil-works/pi-tui/native"
X64="$N/darwin/prebuilds/darwin-x64/darwin-platform.node"
ARM="$N/darwin/prebuilds/darwin-arm64/darwin-platform.node"
OURS="$T/share/pi/darwin-platform.node"
ERR="$PI_STATE/last-addon-error"

mknative() {
  mkdir -p "$1/darwin/src"
  printf 'objc source\n' > "$1/darwin/src/darwin-platform.m"
  printf 'clipboard header\n' > "$1/clipboard.h"
  printf 'napi header\n' > "$1/napi.h"
}
mkrelease() {
  rm -rf "$PI_MROOT/releases/$V"
  mknative "$N"
  mkdir -p "$(dirname "$X64")" "$(dirname "$ARM")"
  printf 'upstream x64 addon\n' > "$X64"
  printf 'upstream arm64 addon\n' > "$ARM"
}
mkours() {
  mkdir -p "$T/share/pi"
  printf 'our 10.9 addon\n' > "$OURS"
  pi_addon_source_id "$N" > "$T/share/pi/addon-source-id"
}
swap() { pi_swap_addon "$V" 2>"$H/err" && rc=0 || rc=$?; }
fakemv() {
  cat > "$H/bin/mv" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$H/mv-calls"
for a; do printf '%s\n' "$a"; done >> "$H/mv-args"
[ "$#" -eq 3 ] && /usr/bin/stat -f %Lp "$2" >> "$H/mv-modes"
exec /bin/mv "$@"
EOF
  chmod +x "$H/bin/mv"
  PATH="$H/bin:$H_ORIG_PATH"
  rm -f "$H/mv-calls" "$H/mv-args" "$H/mv-modes"
  : > "$H/mv-calls"
}
nofakemv() { rm -f "$H/bin/mv"; PATH="$H_ORIG_PATH"; }

mknative "$H/a"
mknative "$H/b"
ida="$(pi_addon_source_id "$H/a")"
h_assert_eq "$ida" "$(pi_addon_source_id "$H/b")" "same inputs give the same id"
h_assert_eq "$(cat "$H/a/darwin/src/darwin-platform.m" "$H/a/clipboard.h" "$H/a/napi.h" | shasum -a 256 | cut -d' ' -f1)" "$ida" \
  "id is sha256 over .m, clipboard.h, napi.h in that order"
for f in darwin/src/darwin-platform.m clipboard.h napi.h; do
  mknative "$H/b"
  printf 'edit\n' >> "$H/b/$f"
  idb="$(pi_addon_source_id "$H/b")"
  h_assert_eq 1 "$([ "$idb" != "$ida" ] && echo 1 || echo 0)" "editing $f changes the id"
done
for f in darwin/src/darwin-platform.m clipboard.h napi.h; do
  mknative "$H/b"
  rm "$H/b/$f"
  out="$(pi_addon_source_id "$H/b")" && rc=0 || rc=$?
  h_assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "missing $f: non-zero"
  h_assert_eq "" "$out" "missing $f: no output"
done

mkrelease
mkours
swap
h_assert_eq 0 "$rc" "match: returns 0"
h_assert_ok cmp -s "$OURS" "$X64"
h_assert_eq "upstream arm64 addon" "$(cat "$ARM")" "match: darwin-arm64 untouched"
h_assert_eq 755 "$(stat -f %Lp "$X64")" "match: swapped addon is 0755"
h_assert_absent "$ERR" "match: no error recorded"
h_assert_eq "" "$(cat "$H/err")" "match: silent"
set -- "$(dirname "$X64")"/.darwin-platform.node.*
h_assert_absent "$1" "match: no temp file left"

mkrelease
fakemv
swap
nofakemv
h_assert_eq 0 "$rc" "rename: returns 0"
h_assert_eq 1 "$(wc -l < "$H/mv-calls" | tr -d ' ')" "rename: exactly one mv"
h_assert_eq 3 "$(wc -l < "$H/mv-args" | tr -d ' ')" "rename: mv got three arguments"
h_assert_eq "-f" "$(sed -n 1p "$H/mv-args")" "rename: mv -f"
tmp="$(sed -n 2p "$H/mv-args")"
h_assert_eq "$(dirname "$X64")" "$(dirname "$tmp")" "rename: temp is in the prebuilds dir"
h_assert_eq 1 "$([ "$tmp" != "$X64" ] && echo 1 || echo 0)" "rename: temp is not the target"
h_assert_eq "$X64" "$(sed -n 3p "$H/mv-args")" "rename: renamed over the target"
h_assert_eq 755 "$(cat "$H/mv-modes")" "rename: temp is 0755 before the rename"
h_assert_ok cmp -s "$OURS" "$X64"

touch -t 200001010000 "$X64"
before="$(stat -f '%i %m' "$X64")"
fakemv
swap
nofakemv
h_assert_eq 0 "$rc" "noop: returns 0"
h_assert_eq "$before" "$(stat -f '%i %m' "$X64")" "noop: target inode and mtime unchanged"
h_assert_eq "" "$(cat "$H/mv-calls")" "noop: no mv"
h_assert_eq "" "$(cat "$H/err")" "noop: silent"

mkdir -p "$PI_STATE"
printf 'old trouble\n' > "$ERR"
mkrelease
swap
h_assert_eq 0 "$rc" "stale: returns 0"
h_assert_ok cmp -s "$OURS" "$X64"
h_assert_absent "$ERR" "stale: successful swap clears last-addon-error"

mkrelease
oursid="$(cat "$T/share/pi/addon-source-id")"
printf 'upstream changed this\n' >> "$N/clipboard.h"
theirsid="$(pi_addon_source_id "$N")"
fakemv
swap
nofakemv
h_assert_eq 0 "$rc" "mismatch: returns 0"
h_assert_eq "upstream x64 addon" "$(cat "$X64")" "mismatch: upstream's addon left in place"
h_assert_eq "upstream arm64 addon" "$(cat "$ARM")" "mismatch: darwin-arm64 untouched"
h_assert_eq 1 "$(wc -l < "$ERR" | tr -d ' ')" "mismatch: one-line reason"
h_assert_contains "$(cat "$ERR")" "$V" "mismatch: reason names the version"
h_assert_contains "$(cat "$ERR")" "$oursid" "mismatch: reason names our id"
h_assert_contains "$(cat "$ERR")" "$theirsid" "mismatch: reason names the release's id"
h_assert_eq 0 "$(grep -c "darwin-platform.node" "$H/mv-calls" || :)" "mismatch: target never renamed"
h_assert_contains "$(cat "$H/err")" "$V" "mismatch: first time notes it"

first="$(cat "$ERR")"
swap
h_assert_eq 0 "$rc" "repeat mismatch: returns 0"
h_assert_eq "" "$(cat "$H/err")" "repeat mismatch: no second note"
h_assert_eq "$first" "$(cat "$ERR")" "repeat mismatch: same record"

rm -f "$ERR"
mkrelease
rm "$N/napi.h"
swap
h_assert_eq 0 "$rc" "missing inputs: returns 0"
h_assert_eq "upstream x64 addon" "$(cat "$X64")" "missing inputs: upstream's addon untouched"
h_assert_contains "$(cat "$ERR" 2>/dev/null)" "$V" "missing inputs: reason recorded"
h_assert_contains "$(cat "$ERR" 2>/dev/null)" "$oursid" "missing inputs: reason names our id"

rm -f "$ERR"
mkrelease
rm "$OURS"
swap
h_assert_eq 0 "$rc" "ours absent: returns 0"
h_assert_eq "upstream x64 addon" "$(cat "$X64")" "ours absent: upstream's addon untouched"
h_assert_contains "$(cat "$ERR" 2>/dev/null)" "$V" "ours absent: reason recorded"

cat > "$H/bare.sh" <<'EOF2'
set -e
. "$1/libexec/pi/lib.sh"
. "$1/libexec/pi/addon.sh"
pi_init "$1/bin/pi"
[ -z "$3" ] || PI_STATE="$3"
pi_swap_addon "$2"
echo "reached rc=$?"
EOF2
bare() { /bin/sh "$H/bare.sh" "$T" "$V" "$1" >"$H/bare-out" 2>"$H/bare-err" && rc=0 || rc=$?; }
: > "$H/notadir"

mkrelease
printf 'our 10.9 addon\n' > "$OURS"
pi_addon_source_id "$N" > "$T/share/pi/addon-source-id"
printf 'upstream changed this\n' >> "$N/clipboard.h"
bare "$H/notadir/state"
h_assert_eq 0 "$rc" "bare set -e, unwritable PI_STATE, mismatch: exits 0"
h_assert_eq "reached rc=0" "$(cat "$H/bare-out")" "bare set -e, unwritable PI_STATE, mismatch: next line runs"
h_assert_contains "$(cat "$H/bare-err")" "$V" "bare set -e, unwritable PI_STATE, mismatch: still notes"
h_assert_eq "upstream x64 addon" "$(cat "$X64")" "bare set -e, mismatch: upstream untouched"

mkrelease
bare "$H/notadir/state"
h_assert_eq 0 "$rc" "bare set -e, unwritable PI_STATE, match: exits 0"
h_assert_eq "reached rc=0" "$(cat "$H/bare-out")" "bare set -e, unwritable PI_STATE, match: next line runs"
h_assert_ok cmp -s "$OURS" "$X64"

mkrelease
bare "$H/notadir/state"
h_assert_eq "reached rc=0" "$(cat "$H/bare-out")" "bare set -e, unwritable PI_STATE, already ours: next line runs"

chmod 000 "$T/share/pi/addon-source-id"
mkrelease
bare ""
chmod 644 "$T/share/pi/addon-source-id"
h_assert_eq 0 "$rc" "bare set -e, unreadable addon-source-id: exits 0"
h_assert_eq "reached rc=0" "$(cat "$H/bare-out")" "bare set -e, unreadable addon-source-id: next line runs"
h_assert_eq "upstream x64 addon" "$(cat "$X64")" "bare set -e, unreadable addon-source-id: upstream untouched"
h_assert_contains "$(cat "$ERR" 2>/dev/null)" "$V" "bare set -e, unreadable addon-source-id: reason recorded"

chmod 555 "$(dirname "$X64")"
rm -f "$ERR"
bare ""
chmod 755 "$(dirname "$X64")"
h_assert_eq 0 "$rc" "bare set -e, read-only prebuilds dir: exits 0"
h_assert_eq "reached rc=0" "$(cat "$H/bare-out")" "bare set -e, read-only prebuilds dir: next line runs"
h_assert_eq "upstream x64 addon" "$(cat "$X64")" "bare set -e, read-only prebuilds dir: upstream untouched"
h_assert_contains "$(cat "$ERR" 2>/dev/null)" "could not install" "bare set -e, read-only prebuilds dir: reason recorded"
