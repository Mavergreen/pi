#!/bin/sh
# platform: macOS-only -- drives packaging/install.sh, which reads plists with 10.9's /usr/libexec/PlistBuddy
set -eu
. "$(dirname "$0")/lib/harness.sh"
[ -x /usr/libexec/PlistBuddy ] || exit 77
h_setup
I="$H_REPO/packaging/install.sh"
REL="$H/rel"
mkdir -p "$H/tmp"
MAVERGREEN_RELEASES="file://$(printf %s "$REL" | sed "s/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g")"
MAVERGREEN_INSTALL_ROOT="$H/root"
TMPDIR="$H/tmp/"
PATH="$H/bin:$PATH"
export MAVERGREEN_RELEASES MAVERGREEN_INSTALL_ROOT TMPDIR PATH

cat > "$H/bin/sudo" <<'SUDO'
#!/bin/sh
if [ "$*" = "-n true" ]; then [ -n "${H_NOPASSWD-}" ] || exit 1; echo "sudo -n true" >> "$H/run.log"; exit 0; fi
if [ "$*" = "-v" ]; then
  [ -z "${H_NOPASSWD-}" ] || { echo "sudo -v without a tty" >> "$H/run.log"; exit 1; }
  echo "sudo -v" >> "$H/run.log"; exit 0
fi
if [ "$1" = /usr/sbin/installer ] && [ "$2" = -pkg ] && [ "$4" = -target ] && [ "$5" = / ] && [ $# -eq 5 ]; then
  [ -f "$3" ] || { echo "missing $3" >> "$H/run.log"; exit 1; }
  case "$3" in "$H/tmp/"*) ;; *) echo "outside the temp dir: $3" >> "$H/run.log"; exit 1 ;; esac
  echo "install $(basename "$3") $(cat "$3")" >> "$H/run.log"
  exit 0
fi
echo "unexpected sudo $*" >> "$H/run.log"
exit 1
SUDO
cat > "$H/bin/sw_vers" <<'SW'
#!/bin/sh
[ "$*" = "-productVersion" ] || exit 1
printf '%s\n' "${H_OSVER-10.9.5}"
SW
cat > "$H/bin/uname" <<'UN'
#!/bin/sh
case "$*" in
  -s) printf '%s\n' "${H_KERNEL-Darwin}" ;;
  -m) printf '%s\n' "${H_ARCH-x86_64}" ;;
  *) exec /usr/bin/uname "$@" ;;
esac
UN
cat > "$H/bin/installer" <<'INS'
#!/bin/sh
echo "installer reached without sudo: $*" >> "$H/run.log"
exit 1
INS
chmod +x "$H/bin/sudo" "$H/bin/sw_vers" "$H/bin/uname" "$H/bin/installer"
hash -r

pub() {
  _d="$REL/$1/releases/latest/download"
  mkdir -p "$_d"
  shift
  for _a in "$@"; do printf 'payload %s\n' "$_a" > "$_d/$_a"; done
  (cd "$_d" && shasum -a 256 "$@" > SHA256SUMS)
}
release_all() {
  rm -rf "$REL"
  pub nodejs-24 nodejs-24.21.0-mavericks.1.pkg node24.xml build-info-cross.txt
  pub fd fd-10.5.0-mavericks.1.pkg fd.xml build-info-native.txt
  pub rg rg-15.2.0-mavericks.1.pkg rg.xml build-info-native.txt
  pub pi pi-1.1.0-mavericks.1.pkg pi.xml install.sh
}
installed() {
  _p="$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/$1/mavergreen.plist"
  mkdir -p "$(dirname "$_p")"
  rm -f "$_p"
  /usr/libexec/PlistBuddy -c "Add :version string $2" "$_p" >/dev/null
}
fresh() {
  rm -rf "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen" "$H/run.log"
  : > "$H/run.log"
  release_all
}
run() { rc=0; out="$(sh "$I" 2>&1)" || rc=$?; log="$(cat "$H/run.log")"; last="$(printf '%s\n' "$out" | tail -n 1)"; }
DONE="Pi for Mavericks: done. Open a new Terminal window, then run pi."
tmp_left() { ls -A "$H/tmp"; }

ALL="sudo -v
install nodejs-24.21.0-mavericks.1.pkg payload nodejs-24.21.0-mavericks.1.pkg
install fd-10.5.0-mavericks.1.pkg payload fd-10.5.0-mavericks.1.pkg
install rg-15.2.0-mavericks.1.pkg payload rg-15.2.0-mavericks.1.pkg
install pi-1.1.0-mavericks.1.pkg payload pi-1.1.0-mavericks.1.pkg"

fresh; run
h_assert_eq 0 "$rc" "a fresh install succeeds: $out"
h_assert_eq "$ALL" "$log" "installs all four, in order, after one sudo -v"
h_assert_eq "$DONE" "$last" "ends saying to open a new Terminal window, then run pi"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after success"

fresh; H_NOPASSWD=1; export H_NOPASSWD; run; unset H_NOPASSWD
h_assert_eq 0 "$rc" "an administrator whose sudo needs no password installs without a tty: $out"
h_assert_eq "sudo -n true
${ALL#sudo -v
}" "$log" "passwordless sudo installs all four without sudo -v, which wants a tty even then"
case "$out" in *"needs an administrator's password"*) h_assert_eq "no password note" "$out" "passwordless sudo is not told it needs a password" ;; esac

fresh; installed node24 24.21.0-mavericks.1; installed rg 15.1.0-mavericks.2; run
h_assert_eq 0 "$rc" "an update succeeds: $out"
h_assert_eq "sudo -v
install fd-10.5.0-mavericks.1.pkg payload fd-10.5.0-mavericks.1.pkg
install rg-15.2.0-mavericks.1.pkg payload rg-15.2.0-mavericks.1.pkg
install pi-1.1.0-mavericks.1.pkg payload pi-1.1.0-mavericks.1.pkg" "$log" "skips the product whose manifest records the release's version, matched by its short name, not its pkg's"
h_assert_contains "$out" "node24 24.21.0-mavericks.1 is already installed" "names the product it skips"

fresh
installed node24 24.21.0-mavericks.1; installed fd 10.5.0-mavericks.1
installed rg 15.2.0-mavericks.1; installed pi 1.1.0-mavericks.1
run
h_assert_eq 0 "$rc" "an up-to-date system succeeds: $out"
h_assert_eq "" "$log" "nothing to install asks for no password"
h_assert_eq "$DONE" "$last" "an up-to-date run still ends saying what to do next"

HAND="$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/node24/lib/node_modules/@earendil-works/pi-coding-agent"
fresh; installed node24 24.21.0-mavericks.1; mkdir -p "$HAND"; run
h_assert_eq 1 "$rc" "Pi installed by hand into node24 stops the install"
h_assert_contains "$out" "sudo /usr/local/mavergreen/node24/bin/npm -g uninstall @earendil-works/pi-coding-agent" "says how to remove the hand-installed Pi"
h_assert_contains "$out" "sudo mavergreen unlink node24 && sudo mavergreen link node24" "says how to relink node24"
h_assert_eq "" "$log" "the hand-installed Pi is found before anything is installed"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after the refusal"
fresh; installed node24 24.21.0-mavericks.1; mkdir -p "$(dirname "$HAND")"; ln -s /nonexistent "$HAND"; run
h_assert_eq 1 "$rc" "a dangling link where the hand-installed Pi goes also stops the install"
rm -rf "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/node24"

fresh; H_OSVER=10.8.5; export H_OSVER; run; unset H_OSVER
h_assert_eq 1 "$rc" "refuses 10.8"
h_assert_contains "$out" "Mac OS X 10.9.5 is required" "the 10.8 refusal says 10.9.5 is required"
h_assert_contains "$out" "10.8.5" "the 10.8 refusal names the running version"
h_assert_eq "" "$log" "refusing 10.8 runs nothing"

fresh; H_OSVER=10.10.5; export H_OSVER; run; unset H_OSVER
h_assert_eq 1 "$rc" "refuses 10.10"

for _v in 10.9 10.9.4 10.9.0; do
  fresh; H_OSVER=$_v; export H_OSVER; run; unset H_OSVER
  h_assert_eq 1 "$rc" "refuses $_v"
  h_assert_contains "$out" "Mac OS X 10.9.5 is required" "the $_v refusal says 10.9.5 is required"
  h_assert_eq "" "$log" "refusing $_v runs nothing"
done

fresh
mkdir -p "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/node24" "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/rg"
: > "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/node24/mavergreen.plist"
/usr/libexec/PlistBuddy -c "Add :name string rg" "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/rg/mavergreen.plist" >/dev/null
run
h_assert_eq 0 "$rc" "an empty or versionless manifest does not stop the install: $out"
h_assert_eq "$ALL" "$log" "an empty or versionless manifest counts as not installed"

cat > "$H/bin/curl" <<'CURL'
#!/bin/sh
echo "$*" >> "$H/curl.log"
exec /usr/bin/curl "$@"
CURL
chmod +x "$H/bin/curl"; hash -r
fresh; : > "$H/curl.log"; run
h_assert_eq 0 "$rc" "install with a logging curl succeeds: $out"
_n="$(grep -c . "$H/curl.log" || :)"; _p="$(grep -c -F -e '--proto-redir =https' "$H/curl.log" || :)"
h_assert_ok test "$_n" -ge 8
h_assert_eq "$_n" "$_p" "every curl call restricts redirects to https"
rm "$H/bin/curl"; hash -r

fresh; H_KERNEL=Linux; export H_KERNEL; run; unset H_KERNEL
h_assert_eq 1 "$rc" "refuses a kernel other than Darwin"
h_assert_contains "$out" "only macOS is supported" "the kernel refusal keeps its wording"

fresh; H_ARCH=i386; export H_ARCH; run; unset H_ARCH
h_assert_eq 1 "$rc" "refuses a 32-bit Mac"
h_assert_contains "$out" "unsupported arch: i386" "the arch refusal keeps its wording"

fresh; printf 'tampered\n' > "$REL/rg/releases/latest/download/rg-15.2.0-mavericks.1.pkg"; run
h_assert_eq 1 "$rc" "a checksum mismatch fails"
h_assert_contains "$out" "rg-15.2.0-mavericks.1.pkg" "the mismatch names the pkg"
h_assert_eq "" "$log" "a checksum mismatch is found before anything is installed"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after a failure"

fresh
_d="$REL/fd/releases/latest/download"
printf 'payload old\n' > "$_d/fd-10.4.0-mavericks.3.pkg"
(cd "$_d" && shasum -a 256 fd-10.4.0-mavericks.3.pkg >> SHA256SUMS)
run
h_assert_eq 1 "$rc" "a release with two matching pkgs fails"
h_assert_contains "$out" "fd: its latest release lists 2" "the failure names the repo"
h_assert_eq "" "$log" "two matching pkgs install nothing"

fresh
_d="$REL/nodejs-24/releases/latest/download"
(cd "$_d" && shasum -a 256 node24.xml > SHA256SUMS)
run
h_assert_eq 1 "$rc" "a release with no matching pkg fails"
h_assert_contains "$out" "nodejs-24: its latest release lists no nodejs-<version>.pkg" "the failure names the repo and the pkg it looked for"
h_assert_eq "" "$log" "no matching pkg installs nothing"

fresh
_d="$REL/pi/releases/latest/download"
{ grep -v "\.pkg$" "$_d/SHA256SUMS"; printf "%s extra\n" "$(grep "\.pkg$" "$_d/SHA256SUMS")"; } > "$_d/SHA256SUMS.new"; mv "$_d/SHA256SUMS.new" "$_d/SHA256SUMS"
run
h_assert_eq 1 "$rc" "a SHA256SUMS line with an extra field does not match"
h_assert_contains "$out" "pi:" "the failure names the repo"
h_assert_eq "" "$log" "an extra-field line installs nothing"

fresh; rm "$REL/rg/releases/latest/download/SHA256SUMS"; run
h_assert_eq 1 "$rc" "a release without SHA256SUMS fails"
h_assert_contains "$out" "rg: could not fetch" "the failure names the repo"
h_assert_eq "" "$log" "a missing SHA256SUMS installs nothing"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after a fetch failure"

fresh
rc=0; out="$(cat "$I" | sh 2>&1)" || rc=$?; log="$(cat "$H/run.log")"; last="$(printf '%s\n' "$out" | tail -n 1)"
h_assert_eq 0 "$rc" "works when piped into sh: $out"
h_assert_eq "$ALL" "$log" "piped into sh, installs all four in order"
h_assert_eq "$DONE" "$last" "piped into sh, ends saying what to do next"
h_assert_eq "" "$(tmp_left)" "piped into sh, the temp dir is removed"

_rq="$(sed 's/ .*//' "$H_REPO/tree/share/pi/requires" | tr '\n' ' ')pi"
_is="$(sed -n 's/^ *for triple in \(.*\); do$/\1/p' "$I" | tr ' ' '\n' | sed 's/:.*//' | tr '\n' ' ' | sed 's/ $//')"
h_assert_eq "$_rq" "$_is" "install.sh installs exactly what the pkg requires, in the same order, then pi"

W="$H_REPO/.github/workflows/release.yml"
_wc="$(grep -n -F 'cp packaging/install.sh "$BUILD/dist/install.sh"' "$W" | head -n 1 | cut -d: -f1)"
_wp="$(grep -n -F 'sh packaging/verify-pkg.sh' "$W" | head -n 1 | cut -d: -f1)"
_wn="$(grep -n -F -- '- name: Release notes' "$W" | head -n 1 | cut -d: -f1)"
h_assert_ok test "${_wp:-99}" -lt "${_wc:-0}"
h_assert_ok test "${_wc:-99}" -lt "${_wn:-0}"
h_done
