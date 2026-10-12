#!/bin/sh
# platform: macOS-only -- the tests drive the launcher, which targets Mac OS X 10.9's sh and tools
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
MG="$H/root/usr/local/mavergreen"
T="$MG/pi"
. "$T/libexec/pi/lib.sh"
. "$T/libexec/pi/env.sh"

mkdir -p "$MG/fd/bin" "$MG/rg/bin" "$MG/node24/bin" "$T/bin"
: > "$T/bin/pi"
for p in fd/bin/fd rg/bin/rg node24/bin/node; do : > "$MG/$p"; chmod +x "$MG/$p"; done
pi_init "$T/bin/pi"
BIN="$HOME/.pi/agent/bin"

OLDPATH="/usr/bin:$PI_MG/node24/bin:/bin:$PI_TREE/bin:/opt/x y:/sbin:/usr/sbin"
PATH="$OLDPATH"
r=$(pi_setup_env 2>&1) && rc=0 || rc=$?
h_assert_eq 0 "$rc" "pi_setup_env succeeds"
h_assert_eq "" "$r" "first call is silent when nothing is replaced"
pi_setup_env
h_assert_eq unset "${PI_OFFLINE-unset}" "PI_OFFLINE is not set by the launcher"
h_assert_eq "$PI_MROOT" "$PI_MANAGED_INSTALL_ROOT" "PI_MANAGED_INSTALL_ROOT"
h_assert_eq "$PI_TREE/bin:$PI_MG/node24/bin:/usr/bin:/bin:/opt/x y:/sbin:/usr/sbin:$PI_MG/fd/bin:$PI_MG/rg/bin" "$PATH" "PATH prepended, helper bins appended, existing entries deduped, order kept"
case "$-" in *f*) h_assert_eq noglob glob "noglob state restored" ;; esac
h_assert_eq 3 "$(printf %s "$IFS" | wc -c | tr -d " ")" "IFS restored"
h_assert_eq "$MG/fd/bin/fd" "$(readlink "$BIN/fd")" "fd symlink"
h_assert_eq "$MG/rg/bin/rg" "$(readlink "$BIN/rg")" "rg symlink"

PATH="/usr/bin:/bin"; pi_setup_env
h_assert_eq "$PI_TREE/bin:$PI_MG/node24/bin:/usr/bin:/bin:$PI_MG/fd/bin:$PI_MG/rg/bin" "$PATH" "PATH from a plain one"
PATH="$PI_MG/rg/bin:/usr/bin:$PI_MG/fd/bin:/bin"; pi_setup_env
h_assert_eq "$PI_TREE/bin:$PI_MG/node24/bin:/usr/bin:/bin:$PI_MG/fd/bin:$PI_MG/rg/bin" "$PATH" "helper bins already on PATH move to the end"
pi_setup_env
h_assert_eq "$PI_TREE/bin:$PI_MG/node24/bin:/usr/bin:/bin:$PI_MG/fd/bin:$PI_MG/rg/bin" "$PATH" "PATH is stable across repeated calls"

PI_OFFLINE=yes; export PI_OFFLINE
pi_setup_env
h_assert_eq yes "$PI_OFFLINE" "a user's PI_OFFLINE is left alone"
unset PI_OFFLINE

ls -l "$BIN/fd" > "$H/before"
r=$(pi_setup_env 2>&1)
h_assert_eq "" "$r" "idempotent: no note"
ls -l "$BIN/fd" > "$H/after"
h_assert_eq "$(cat "$H/before")" "$(cat "$H/after")" "idempotent: link untouched"
h_assert_absent "$PI_STATE/replaced-helpers" "idempotent: nothing logged"

rm "$BIN/rg"; printf 'foreign rg' > "$BIN/rg"
r=$(pi_setup_env 2>&1)
h_assert_eq "$MG/rg/bin/rg" "$(readlink "$BIN/rg")" "foreign file replaced by symlink"
h_assert_contains "$r" "rg" "note names helper"
h_assert_contains "$r" "$PI_STATE/replaced-helpers/rg." "note names backup path"
set -- "$PI_STATE"/replaced-helpers/rg.*
h_assert_eq "foreign rg" "$(cat "$1")" "foreign content preserved"
h_assert_contains "$(cat "$PI_STATE/replaced-helpers/log")" "rg" "log line"
h_assert_eq 1 "$(wc -l < "$PI_STATE/replaced-helpers/log" | tr -d ' ')" "one log line"

rm "$BIN/fd"; ln -s /elsewhere/fd "$BIN/fd"
r=$(pi_setup_env 2>&1)
h_assert_eq "$MG/fd/bin/fd" "$(readlink "$BIN/fd")" "foreign symlink replaced"
h_assert_contains "$r" "/elsewhere/fd" "note names old target"
h_assert_eq 2 "$(wc -l < "$PI_STATE/replaced-helpers/log" | tr -d ' ')" "second log line"

mkdir "$H/somedir"; rm "$BIN/fd"; ln -s "$H/somedir" "$BIN/fd"
r=$(pi_setup_env 2>&1)
h_assert_eq "$MG/fd/bin/fd" "$(readlink "$BIN/fd")" "symlink to a directory replaced"
h_assert_eq 0 "$(ls -A "$H/somedir" | wc -l | tr -d ' ')" "directory behind the old symlink untouched"
h_assert_contains "$r" "$H/somedir" "note names old directory target"

PI_CODING_AGENT_DIR="$H/agent2"; export PI_CODING_AGENT_DIR
pi_init "$T/bin/pi"
pi_setup_env
h_assert_eq "$MG/fd/bin/fd" "$(readlink "$H/agent2/bin/fd")" "honours PI_CODING_AGENT_DIR"
h_assert_eq "$H/agent2/install" "$PI_MANAGED_INSTALL_ROOT" "managed root follows PI_CODING_AGENT_DIR"

PI_CODING_AGENT_DIR='~/agent3'
cd "$H"
pi_init "$T/bin/pi"
pi_setup_env
h_assert_eq "$MG/rg/bin/rg" "$(readlink "$HOME/agent3/bin/rg")" "helpers go under a ~-expanded PI_CODING_AGENT_DIR"
h_assert_eq "$HOME/agent3/install" "$PI_MANAGED_INSTALL_ROOT" "managed root under a ~-expanded PI_CODING_AGENT_DIR"
h_assert_absent "$H/~" "no literal ~ directory in the working directory"
unset PI_CODING_AGENT_DIR

