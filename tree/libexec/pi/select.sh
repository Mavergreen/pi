#!/bin/sh
# platform: macOS-only -- the launcher chooses among releases Pi's managed installer lays out on 10.9

pi_marker_valid() {
  [ -f "$PI_MROOT/managed-install.json" ] || return 1
  _pi_mk="$(tr -d ' \t\r\n' < "$PI_MROOT/managed-install.json")"
  case "$_pi_mk" in *'"kind":"pi-managed-install"'*) ;; *) return 1 ;; esac
  case "$_pi_mk" in *'"layout":"releases-v1"'*) ;; *) return 1 ;; esac
  case "$_pi_mk" in
    *'"schemaVersion":1'[0-9]*) return 1 ;;
    *'"schemaVersion":1'*) return 0 ;;
  esac
  return 1
}

pi_entry() { printf '%s\n' "$PI_MROOT/releases/$1/node_modules/.bin/pi"; }

pi_release_valid() {
  pi_is_version "$1" && [ -x "$PI_MROOT/releases/$1/node_modules/.bin/pi" ]
}

pi_newest() {
  _pi_best=""
  for _pi_d in "$PI_MROOT"/releases/*; do
    _pi_c="${_pi_d##*/}"
    pi_release_valid "$_pi_c" || continue
    if [ -z "$_pi_best" ] || pi_ver_gt "$_pi_c" "$_pi_best"; then _pi_best="$_pi_c"; fi
  done
  [ -n "$_pi_best" ] || return 1
  printf '%s\n' "$_pi_best"
}

pi_choose() {
  pi_marker_valid || return 1
  _pi_cur=""
  [ -f "$PI_MROOT/current-version" ] && _pi_cur="$(tr -d ' \t\r\n' < "$PI_MROOT/current-version")"
  if pi_release_valid "$_pi_cur"; then
    printf '%s\n' "$_pi_cur"
    return 0
  fi
  _pi_pick="$(pi_newest)" || return 1
  pi_write_atomic "$PI_MROOT/current-version" "$_pi_pick" || pi_note "could not update $PI_MROOT/current-version"
  if [ -n "$_pi_cur" ]; then
    pi_note "current-version named $_pi_cur, which is not an installed release; running $_pi_pick"
  else
    pi_note "current-version was absent or empty; running $_pi_pick"
  fi
  printf '%s\n' "$_pi_pick"
}
