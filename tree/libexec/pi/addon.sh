#!/bin/sh
# platform: macOS-only -- swaps a Mac OS X 10.9 build of Pi's native addon into a managed release

# spec: .superpowers/specs/2026-10-09-mavergreen-pi-design.md §3 -- sha256 over darwin-platform.m, clipboard.h, napi.h in that order
pi_addon_source_id() {
  set -- "$1/darwin/src/darwin-platform.m" "$1/clipboard.h" "$1/napi.h"
  for _pi_asf in "$@"; do
    [ -f "$_pi_asf" ] && [ -r "$_pi_asf" ] || return 1
  done
  _pi_asid="$(cat "$@" | shasum -a 256 | cut -d' ' -f1)" || return 1
  case "$_pi_asid" in
    *[!0-9a-f]*|'') return 1 ;;
  esac
  [ "${#_pi_asid}" -eq 64 ] || return 1
  printf '%s\n' "$_pi_asid"
}

pi__addon_record() {
  _pi_are="$PI_STATE/last-addon-error"
  if [ -f "$_pi_are" ] && [ "$(cat "$_pi_are" 2>/dev/null)" = "$1" ]; then
    return 0
  fi
  mkdir -p "$PI_STATE" 2>/dev/null || :
  pi_write_atomic "$_pi_are" "$1" 2>/dev/null || :
  pi_note "$1" || :
  return 0
}

# spec: .superpowers/specs/2026-10-09-mavergreen-pi-design.md §3 "Launch-time swap" -- degrade, never block
pi_swap_addon() {
  _pi_av="$1"
  _pi_an="$PI_MROOT/releases/$_pi_av/node_modules/@earendil-works/pi-tui/native"
  _pi_ad="$_pi_an/darwin/prebuilds/darwin-x64"
  _pi_at="$_pi_ad/darwin-platform.node"
  _pi_ao="$PI_TREE/share/pi/darwin-platform.node"
  _pi_aoid=""
  if [ -f "$PI_TREE/share/pi/addon-source-id" ]; then
    _pi_aoid="$(tr -d ' \t\r\n' < "$PI_TREE/share/pi/addon-source-id" 2>/dev/null)" || _pi_aoid=""
  fi
  if [ ! -f "$_pi_ao" ] || [ "${#_pi_aoid}" -ne 64 ]; then
    pi__addon_record "Pi $_pi_av keeps its own native addon: this wrapper has no built addon or addon-source-id in $PI_TREE/share/pi (native clipboard/image off on 10.9)"
    return 0
  fi
  _pi_arid="$(pi_addon_source_id "$_pi_an")" || _pi_arid="unavailable (native sources missing)"
  if [ "$_pi_arid" != "$_pi_aoid" ]; then
    pi__addon_record "Pi $_pi_av keeps its own native addon: its source id $_pi_arid does not match ours $_pi_aoid (native clipboard/image off on 10.9)"
    return 0
  fi
  if ! cmp -s "$_pi_ao" "$_pi_at"; then
    _pi_atmp="$_pi_ad/.darwin-platform.node.$$"
    if ! { cp "$_pi_ao" "$_pi_atmp" && chmod 755 "$_pi_atmp" && mv -f "$_pi_atmp" "$_pi_at"; } 2>/dev/null; then
      rm -f "$_pi_atmp" 2>/dev/null || :
      pi__addon_record "Pi $_pi_av keeps its own native addon: could not install ours (id $_pi_aoid) into $_pi_ad"
      return 0
    fi
  fi
  rm -f "$PI_STATE/last-addon-error" 2>/dev/null || :
  return 0
}
