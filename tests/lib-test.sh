#!/bin/sh
# platform: macOS-only -- the launcher library targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
. "$H/root/usr/local/mavergreen/pi/libexec/pi/lib.sh"

h_assert_ok pi_ver_gt 1.2.10 1.2.9
h_assert_ok pi_ver_gt 1.10.0 1.9.9
h_assert_ok pi_ver_gt 2.0.0 1.99.99
h_assert_ok pi_ver_gt 1.2.1000 1.2.999
h_assert_fails pi_ver_gt 1.2.9 1.2.10
h_assert_fails pi_ver_gt 1.2.0 1.2.0
L1=100000000000000000000000; L9=99999999999999999999999
h_assert_ok pi_ver_gt "1.2.$L1" "1.2.$L9"
h_assert_fails pi_ver_gt "1.2.$L9" "1.2.$L1"
h_assert_fails pi_ver_gt 1.2.010 1.2.10
h_assert_ok pi_ver_gt 1.2.010 1.2.9
h_assert_ok pi_ver_gt 1.2.0 1.2.0-rc.1
h_assert_fails pi_ver_gt 1.2.0-rc.1 1.2.0
h_assert_ok pi_ver_gt 1.2.1-rc.1 1.2.0
h_assert_fails pi_ver_gt 1.2.0-rc.1 1.2.0-rc.1
h_assert_ok pi_ver_gt 1.2.0-rc.2 1.2.0-rc.1
h_assert_fails pi_ver_gt 1.2.0-rc.1 1.2.0-rc.2
h_assert_fails pi_ver_gt 1.2.0+b2 1.2.0+b1
h_assert_fails pi_ver_gt 1.2.0+b1 1.2.0
h_assert_ok pi_ver_gt 1.2.1+b1 1.2.0
h_assert_ok pi_ver_gt 1.2.0 1.2.0-rc.1+b9
h_assert_eq "" "$(pi_ver_gt "1.2.$L1" 1.2.5 2>&1; pi_ver_gt 1.2.5 "1.2.$L1" 2>&1)" "a field too long for test's integers is compared without an error"

for v in 1.1.0 1.1.0-rc.1 1.1.0+build.5 1.1.0-rc.1+b 0.0.0 10.20.300 1.1.0-0 1.1.0-a-b.C; do h_assert_ok pi_is_version "$v"; done
for v in '' latest 1..0 1.1 1.1.0.0 v1.1.0 1.1.0- 1.1.0+ 1.1.0-rc_1 1.1.0-rc.1+ 1.1.a .1.0 '1.1.0 x'; do h_assert_fails pi_is_version "$v"; done
h_assert_fails pi_is_version staging
h_assert_fails pi_is_version 1.1.0-rc/1
h_assert_fails pi_is_version '1.1.0-*'

printf 'abc' > "$H/sum"
h_assert_eq ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad "$(pi_sha256 "$H/sum")" "pi_sha256"

r=$(pi_note hello 2>&1 >/dev/null)
h_assert_eq "pi: hello" "$r" "pi_note"
rc=0; r=$( (pi_die boom) 2>&1 ) || rc=$?
h_assert_eq 1 "$rc" "pi_die status"
h_assert_eq "pi: boom" "$r" "pi_die message"

T="$H/root/usr/local/mavergreen/pi"
mkdir -p "$T/bin" "$H/links"
: > "$T/bin/pi"
ln -s "$T/bin/pi" "$H/links/hop2"
ln -s hop2 "$H/links/hop1"
h_assert_eq "$(cd "$T/bin" && pwd -P)/pi" "$(pi_resolve "$H/links/hop1")" "pi_resolve through two hops"
pi_init "$H/links/hop1"
PT="$(cd "$T" && pwd -P)"
h_assert_eq "$PT" "$PI_TREE" "pi_init PI_TREE through two hops"
h_assert_eq "$(dirname "$PT")" "$PI_MG" "pi_init PI_MG"
h_assert_eq "$HOME/Library/Application Support/dev.mavergreen.pi" "$PI_STATE" "pi_init PI_STATE"
h_assert_eq "$HOME/.pi/agent" "$PI_AGENT_DIR" "pi_init PI_AGENT_DIR default"
h_assert_eq "$HOME/.pi/agent/install" "$PI_MROOT" "pi_init PI_MROOT default"
agent() { PI_CODING_AGENT_DIR="$1"; pi_init "$H/links/hop1"; printf '%s|%s' "$PI_AGENT_DIR" "$PI_MROOT"; }
h_assert_eq "/z/agent|/z/agent/install" "$(agent /z/agent)" "PI_MROOT follows PI_CODING_AGENT_DIR"
h_assert_eq "$HOME/.pi/agent|$HOME/.pi/agent/install" "$(agent '')" "an empty PI_CODING_AGENT_DIR means the default"
h_assert_eq "$HOME|$HOME/install" "$(agent '~')" "PI_CODING_AGENT_DIR ~ is HOME"
h_assert_eq "$HOME|$HOME/install" "$(agent '~/')" "PI_CODING_AGENT_DIR ~/ is HOME"
h_assert_eq "$HOME/my agent|$HOME/my agent/install" "$(agent '~/my agent')" "PI_CODING_AGENT_DIR ~/x is under HOME"
h_assert_eq "/z/agent|/z/agent/install" "$(agent /z/agent//)" "trailing slashes dropped"
h_assert_eq "/|//install" "$(agent /)" "PI_CODING_AGENT_DIR / is kept"
for bad in rel/agent '~other/agent' './agent' 'file:///z/agent'; do
  rc=0; r=$( (agent "$bad") 2>&1 ) || rc=$?
  h_assert_eq 1 "$rc" "PI_CODING_AGENT_DIR $bad is refused"
  h_assert_contains "$r" "pi: PI_CODING_AGENT_DIR must be an absolute path, ~ or ~/... (it is '$bad')" "PI_CODING_AGENT_DIR $bad message"
done
unset PI_CODING_AGENT_DIR
h_assert_eq "https://pi.dev/api/installer/releases" "$PI_API" "pi_init PI_API default"
h_assert_eq "http://x.invalid/r" "$(PI_INSTALLER_API_BASE=http://x.invalid/r//; pi_init "$H/links/hop1"; printf %s "$PI_API")" "PI_API honours PI_INSTALLER_API_BASE, trailing slashes stripped"
rc=0; r=$( (HOME=/; pi_init "$H/links/hop1") 2>&1 ) || rc=$?
h_assert_eq 1 "$rc" "pi_init rejects HOME=/"
h_assert_contains "$r" "pi: HOME must be an absolute path" "pi_init HOME message"
h_done
