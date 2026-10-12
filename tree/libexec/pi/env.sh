#!/bin/sh
# platform: macOS-only -- the environment Pi needs on Mac OS X 10.9

# spec: .superpowers/specs/2026-10-09-mavergreen-pi-design.md, "Why the helper wiring works (fd/rg)"
pi_ensure_helper() {
  _pi_hn="$1"
  _pi_ht="$2"
  _pi_hd="$PI_AGENT_DIR/bin"
  _pi_hp="$_pi_hd/$_pi_hn"
  mkdir -p "$_pi_hd" 2>/dev/null || { pi_note "cannot create $_pi_hd; $_pi_hn is not wired"; return 1; }
  if [ -L "$_pi_hp" ] && [ "$(readlink "$_pi_hp")" = "$_pi_ht" ]; then
    return 0
  fi
  _pi_hrd="$PI_STATE/replaced-helpers"
  _pi_hwas=""
  _pi_hnow="$(date +%s)"
  if [ -L "$_pi_hp" ]; then
    _pi_hwas="symlink to $(readlink "$_pi_hp"), replaced"
    # platform: mv -f of a symlink onto a symlink to a directory moves it into that directory
    rm -f "$_pi_hp" 2>/dev/null
  elif [ -e "$_pi_hp" ]; then
    _pi_hbk="$_pi_hrd/$_pi_hn.$_pi_hnow"
    if mkdir -p "$_pi_hrd" 2>/dev/null && mv "$_pi_hp" "$_pi_hbk" 2>/dev/null; then
      _pi_hwas="moved to $_pi_hbk"
    else
      pi_note "cannot move foreign $_pi_hp aside; $_pi_hn is not wired"
      return 1
    fi
  fi
  _pi_htmp="$_pi_hd/.$_pi_hn.$$"
  rm -f "$_pi_htmp"
  if ln -s "$_pi_ht" "$_pi_htmp" 2>/dev/null && mv -f "$_pi_htmp" "$_pi_hp" 2>/dev/null \
     && [ "$(readlink "$_pi_hp")" = "$_pi_ht" ]; then
    :
  else
    rm -f "$_pi_htmp"
    pi_note "cannot link $_pi_hp to $_pi_ht; $_pi_hn is not wired"
    return 1
  fi
  if [ -n "$_pi_hwas" ]; then
    pi_note "replaced foreign $_pi_hp ($_pi_hwas); now links to $_pi_ht"
    mkdir -p "$_pi_hrd" 2>/dev/null && printf '%s %s %s\n' "$_pi_hnow" "$_pi_hp" "$_pi_hwas" >> "$_pi_hrd/log" 2>/dev/null || true
  fi
  return 0
}

pi_setup_env() {
  PI_MANAGED_INSTALL_ROOT="$PI_MROOT"
  export PI_MANAGED_INSTALL_ROOT
  # platform: node24/bin serves pi's `#!/usr/bin/env node` shebang and npm during `pi update`
  _pi_e1="$PI_TREE/bin"
  _pi_e2="$PI_MG/node24/bin"
  # spec: .superpowers/specs/2026-10-09-mavergreen-pi-design.md, "Why the helper wiring works (fd/rg)" -- the
  #       helpers' bins go last on PATH, Pi's fallback when ~/.pi/agent/bin is not wired
  _pi_e3="$PI_MG/fd/bin"
  _pi_e4="$PI_MG/rg/bin"
  _pi_rest=""
  _pi_oifs="$IFS"
  case "$-" in *f*) _pi_nf=1 ;; *) _pi_nf=0; set -f ;; esac
  IFS=:
  for _pi_pe in $PATH; do
    case "$_pi_pe" in "$_pi_e1"|"$_pi_e2"|"$_pi_e3"|"$_pi_e4") continue ;; esac
    _pi_rest="${_pi_rest:+$_pi_rest:}$_pi_pe"
  done
  IFS="$_pi_oifs"
  [ "$_pi_nf" -eq 1 ] || set +f
  PATH="$_pi_e1:$_pi_e2${_pi_rest:+:$_pi_rest}:$_pi_e3:$_pi_e4"
  export PATH
  pi_ensure_helper fd "$PI_MG/fd/bin/fd" || true
  pi_ensure_helper rg "$PI_MG/rg/bin/rg" || true
  return 0
}
