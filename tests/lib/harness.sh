#!/bin/sh
# platform: macOS-only -- the tests drive the launcher, which targets Mac OS X 10.9's sh and tools
#   usage: . "$(dirname "$0")/lib/harness.sh"; h_setup; ... h_assert_* ...  h_setup installs the EXIT trap; h_teardown removes $H and fails the test if any assert failed.
#          asserts must not run inside $(...) or a pipeline: their failure count would be lost.

H_FAILS=0
H_REPO="$(cd "$(dirname "$0")/.." && pwd)"
H_ORIG_HOME="${HOME-}"
H_ORIG_PATH="$PATH"

h_setup() {
  trap h_teardown EXIT
  unset XDG_DATA_HOME PI_CODING_AGENT_DIR PI_INSTALLER_API_BASE PI_OFFLINE
  H="$(mktemp -d "${TMPDIR:-/tmp}/pi test.XXXXXX")"
  H="$(cd "$H" && pwd -P)"
  export H
  _h_mg="$H/root/usr/local/mavergreen"
  mkdir -p "$_h_mg" "$H/home" "$H/bin"
  cp -R "$H_REPO/tree" "$_h_mg/pi"
  HOME="$H/home"
  export HOME
}

h_teardown() {
  [ -n "${H-}" ] && rm -rf "$H"
  HOME="$H_ORIG_HOME"
  PATH="$H_ORIG_PATH"
  export HOME PATH
  [ "${H_FAILS:-0}" -eq 0 ] || exit 1
}

h_assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: $3" >&2
    echo "  expected: $1" >&2
    echo "  actual:   $2" >&2
    H_FAILS=$((H_FAILS+1))
  fi
}

h_assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) echo "FAIL: $3" >&2; echo "  missing: $2" >&2; echo "  in: $1" >&2; H_FAILS=$((H_FAILS+1)) ;;
  esac
}

h_assert_ok() {
  "$@" || { echo "FAIL: expected success: $*" >&2; H_FAILS=$((H_FAILS+1)); }
}

h_assert_fails() {
  if "$@"; then echo "FAIL: expected failure: $*" >&2; H_FAILS=$((H_FAILS+1)); fi
}

h_assert_absent() {
  if [ -e "$1" ] || [ -L "$1" ]; then echo "FAIL: $2" >&2; echo "  present: $1" >&2; H_FAILS=$((H_FAILS+1)); fi
}
