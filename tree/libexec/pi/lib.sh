#!/bin/sh
# platform: macOS-only -- the launcher exists to run Pi on Mac OS X 10.9

pi_die() { echo "pi: $*" >&2; exit 1; }
pi_note() { echo "pi: $*" >&2; }

pi_resolve() {
  _pi_rp="$1"
  _pi_hops=0
  while [ -L "$_pi_rp" ]; do
    _pi_hops=$((_pi_hops+1))
    [ "$_pi_hops" -le 40 ] || pi_die "too many symlinks: $1"
    _pi_rt="$(readlink "$_pi_rp")"
    case "$_pi_rt" in
      /*) _pi_rp="$_pi_rt" ;;
      *) _pi_rp="$(dirname "$_pi_rp")/$_pi_rt" ;;
    esac
  done
  _pi_rd="$(CDPATH= cd -P "$(dirname "$_pi_rp")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$_pi_rd" "$(basename "$_pi_rp")"
}

pi_init() {
  case "${HOME-}" in /*[!/.]*) ;; *) pi_die "HOME must be an absolute path other than / (it is '${HOME-}')" ;; esac
  _pi_p="$(pi_resolve "$1")" || exit 1
  _pi_d="$(dirname "$_pi_p")"
  PI_TREE="$(dirname "$_pi_d")"
  PI_MG="$(dirname "$PI_TREE")"
  PI_STATE="$HOME/Library/Application Support/dev.mavergreen.pi"
  # spec: Pi 1.1.0 dist/config.js getAgentDir and dist/utils/paths.js normalizePath -- `~` and `~/...` mean HOME
  PI_AGENT_DIR="${PI_CODING_AGENT_DIR-}"
  case "$PI_AGENT_DIR" in
    '') PI_AGENT_DIR="$HOME/.pi/agent" ;;
    '~') PI_AGENT_DIR="$HOME" ;;
    '~/'*) PI_AGENT_DIR="$HOME/${PI_AGENT_DIR#??}" ;;
  esac
  case "$PI_AGENT_DIR" in
    /*) ;;
    *) pi_die "PI_CODING_AGENT_DIR must be an absolute path, ~ or ~/... (it is '$PI_CODING_AGENT_DIR')" ;;
  esac
  while :; do case "$PI_AGENT_DIR" in ?*/) PI_AGENT_DIR="${PI_AGENT_DIR%/}" ;; *) break ;; esac; done
  PI_MROOT="$PI_AGENT_DIR/install"
  _pi_api="${PI_INSTALLER_API_BASE:-https://pi.dev/api/installer/releases}"
  while :; do case "$_pi_api" in */) _pi_api="${_pi_api%/}" ;; *) break ;; esac; done
  PI_API="$_pi_api"
}

pi_is_version() {
  _pi_v="$1"
  case "$_pi_v" in ''|*[!0-9A-Za-z.+-]*) return 1 ;; esac
  _pi_bld=""
  case "$_pi_v" in
    *+*) _pi_bld="${_pi_v#*+}"; _pi_v="${_pi_v%%+*}"
         case "$_pi_bld" in ''|*+*) return 1 ;; esac ;;
  esac
  case "$_pi_v" in
    *-*) _pi_pre="${_pi_v#*-}"; _pi_v="${_pi_v%%-*}"
         [ -n "$_pi_pre" ] || return 1 ;;
  esac
  case "$_pi_v" in ''|*[!0-9.]*|.*|*.|*..*) return 1 ;; esac
  case "$_pi_v" in *.*.*) ;; *) return 1 ;; esac
  case "${_pi_v#*.*.}" in *.*) return 1 ;; esac
  return 0
}

pi__cmp_core_gt0_lt1_eq2() {
  _pi_a="$1"; _pi_b="$2"
  while [ -n "$_pi_a" ] || [ -n "$_pi_b" ]; do
    _pi_fa="${_pi_a%%.*}"; _pi_fb="${_pi_b%%.*}"
    case "$_pi_a" in *.*) _pi_a="${_pi_a#*.}" ;; *) _pi_a="" ;; esac
    case "$_pi_b" in *.*) _pi_b="${_pi_b#*.}" ;; *) _pi_b="" ;; esac
    while :; do case "$_pi_fa" in 0?*) _pi_fa="${_pi_fa#0}" ;; *) break ;; esac; done
    while :; do case "$_pi_fb" in 0?*) _pi_fb="${_pi_fb#0}" ;; *) break ;; esac; done
    : "${_pi_fa:=0}" "${_pi_fb:=0}"
    [ "${#_pi_fa}" -gt "${#_pi_fb}" ] && return 0
    [ "${#_pi_fa}" -lt "${#_pi_fb}" ] && return 1
    while [ -n "$_pi_fa" ]; do
      _pi_da="${_pi_fa%"${_pi_fa#?}"}"; _pi_db="${_pi_fb%"${_pi_fb#?}"}"
      [ "$_pi_da" -gt "$_pi_db" ] && return 0
      [ "$_pi_da" -lt "$_pi_db" ] && return 1
      _pi_fa="${_pi_fa#?}"; _pi_fb="${_pi_fb#?}"
    done
  done
  return 2
}

pi_ver_gt() {
  _pi_ga="${1%%+*}"; _pi_gb="${2%%+*}"
  _pi_pa=""; _pi_pb=""
  case "$_pi_ga" in *-*) _pi_pa="${_pi_ga#*-}"; _pi_ga="${_pi_ga%%-*}" ;; esac
  case "$_pi_gb" in *-*) _pi_pb="${_pi_gb#*-}"; _pi_gb="${_pi_gb%%-*}" ;; esac
  _pi_rc=0
  pi__cmp_core_gt0_lt1_eq2 "$_pi_ga" "$_pi_gb" || _pi_rc=$?
  [ "$_pi_rc" -eq 0 ] && return 0
  [ "$_pi_rc" -eq 1 ] && return 1
  if [ -z "$_pi_pa" ]; then [ -n "$_pi_pb" ]; return; fi
  [ -n "$_pi_pb" ] || return 1
  [ "$(expr "x$_pi_pa" '>' "x$_pi_pb")" = 1 ]
}

# spec: ref/package-manager-cli.js activateManagedRelease -- write a temp file beside the target, rename over it
pi_write_atomic() {
  _pi_wt="$1.tmp.$$"
  if printf '%s\n' "$2" > "$_pi_wt" && mv -f "$_pi_wt" "$1"; then
    return 0
  fi
  rm -f "$_pi_wt"
  return 1
}

pi_sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
