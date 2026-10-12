#!/bin/sh
# platform: macOS-only -- seeds the managed-install root Pi updates itself in on Mac OS X 10.9

PI_MARKER_JSON='{"kind":"pi-managed-install","schemaVersion":1,"layout":"releases-v1"}'
PI_PACKAGE='@earendil-works/pi-coding-agent'
PI__LOCKPID=""
PI__STAGE=""
PI__OTRAPS=""

pi__seeded() {
  pi_marker_valid || return 1
  [ -f "$PI_MROOT/current-version" ] || return 1
  pi_release_valid "$(tr -d ' \t\r\n' < "$PI_MROOT/current-version" 2>/dev/null)"
}

# spec: ref/package-manager-cli.js runManagedSelfUpdate -- proper-lockfile's lock on join(root,"update") is the
#       directory update.lock; it is stale once its mtime is over 10s old, so the holder refreshes it every 4s
pi__lock() {
  _pi_lk="$PI_MROOT/update.lock"
  _pi_lw=0
  until mkdir "$_pi_lk" 2>/dev/null; do
    if [ -d "$_pi_lk" ]; then
      # platform: `stat -f %m` is BSD stat; a GNU stat earlier on PATH rejects it
      _pi_lm="$("${PI__STAT:-/usr/bin/stat}" -f %m "$_pi_lk" 2>/dev/null)" || _pi_lm=""
      case "$_pi_lm" in
        ''|*[!0-9]*) ;;
        *)
          if [ $(( $(date +%s) - _pi_lm )) -gt 10 ]; then
            if rmdir "$_pi_lk" 2>/dev/null || [ ! -d "$_pi_lk" ]; then continue; fi
            pi_note "cannot remove the stale lock $_pi_lk"
            return 1
          fi
          ;;
      esac
      if [ "$_pi_lw" -ge "${PI__LOCK_WAIT:-600}" ]; then
        pi_note "gave up after ${_pi_lw}s waiting for another Pi install or update to release $_pi_lk"
        return 1
      fi
      [ "$_pi_lw" -gt 0 ] || pi_note "waiting for another Pi install or update to finish"
      sleep 1
      _pi_lw=$((_pi_lw+1))
    elif [ -e "$_pi_lk" ] || [ -L "$_pi_lk" ]; then
      pi_note "$_pi_lk is not a directory; remove it and retry"
      return 1
    elif ! mkdir "$_pi_lk"; then
      pi_note "cannot create the lock $_pi_lk"
      return 1
    else
      break
    fi
  done
  PI__OTRAPS="$(trap)"
  trap 'pi__abort 129' HUP
  trap 'pi__abort 130' INT
  trap 'pi__abort 143' TERM
  _pi_lpp=$$
  (
    while kill -0 "$_pi_lpp" 2>/dev/null; do
      sleep 4
      touch -c "$_pi_lk" 2>/dev/null
    done
  ) </dev/null >/dev/null 2>&1 &
  PI__LOCKPID=$!
  return 0
}

pi__unlock() {
  if [ -n "$PI__LOCKPID" ]; then
    # platform: sh reports a killed background job on stderr unless it is reaped with stderr redirected
    { kill "$PI__LOCKPID"; wait "$PI__LOCKPID"; } 2>/dev/null || :
    PI__LOCKPID=""
  fi
  rmdir "$PI_MROOT/update.lock" 2>/dev/null || :
  trap - HUP INT TERM
  eval "$PI__OTRAPS"
  PI__OTRAPS=""
  return 0
}

pi__unstage() {
  [ -z "$PI__STAGE" ] || rm -rf "$PI__STAGE" || :
  PI__STAGE=""
}

pi__abort() {
  pi__unstage
  pi__unlock
  pi_note "interrupted while installing Pi into $PI_MROOT"
  exit "$1"
}

pi__stage_fail() {
  pi__unstage
  pi_note "$*"
  return 1
}

# spec: ref/install.sh validate_managed_install_artifacts
pi__validate() {
  "$PI_MG/node24/bin/node" - "$1" "$2" "$PI_PACKAGE" "$3" <<'NODE'
const fs = require("node:fs");
const packageJson = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const packageLock = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const piPackage = process.argv[4];
const version = process.argv[5];
const root = packageLock.packages?.[""];
const piEntry = packageLock.packages?.[`node_modules/${piPackage}`];

if (packageJson.version !== version || packageJson.dependencies?.[piPackage] !== version) {
	throw new Error(`managed installer package.json must describe ${piPackage}@${version}`);
}
if (packageLock.lockfileVersion !== 3) {
	throw new Error("managed installer package-lock.json must use lockfileVersion 3");
}
if (packageLock.version !== version || root?.version !== version || root?.dependencies?.[piPackage] !== version) {
	throw new Error(`managed installer package-lock.json root must describe ${piPackage}@${version}`);
}
if (piEntry?.version !== version) {
	throw new Error(`managed installer package-lock.json does not include ${piPackage}@${version}`);
}
NODE
}

# spec: ref/package-manager-cli.js runManagedSelfUpdate and ref/install.sh's managed install, minus pruning
pi__stage_release() {
  _pi_sv="$1"
  _pi_rel="$PI_MROOT/releases/$_pi_sv"
  _pi_nb="$PI_MG/node24/bin"
  for _pi_sd in "$PI_MROOT"/staging/update-*; do
    if [ -e "$_pi_sd" ] || [ -L "$_pi_sd" ]; then rm -rf "$_pi_sd"; fi
  done
  if [ -e "$_pi_rel" ] || [ -L "$_pi_rel" ]; then
    rm -rf "$_pi_rel" || { pi_note "cannot remove the incomplete release $_pi_rel"; return 1; }
  fi
  # platform: BSD mktemp requires an explicit template
  PI__STAGE="$(mktemp -d "$PI_MROOT/staging/update-XXXXXX")" || { PI__STAGE=""; pi_note "cannot create a staging directory in $PI_MROOT/staging"; return 1; }
  pi_note "installing Pi $_pi_sv into $PI_MROOT (first run; this downloads Pi and can take a minute)"
  for _pi_af in package.json package-lock.json; do
    curl -fsSL -o "$PI__STAGE/$_pi_af" "$PI_API/$_pi_sv/$_pi_af" \
      || { pi__stage_fail "could not download $_pi_af for Pi $_pi_sv from $PI_API/$_pi_sv/$_pi_af"; return 1; }
  done
  pi__validate "$PI__STAGE/package.json" "$PI__STAGE/package-lock.json" "$_pi_sv" \
    || { pi__stage_fail "the installer manifest for Pi $_pi_sv from $PI_API is invalid"; return 1; }
  # spec: ref/package-manager-cli.js runManagedNpmCi -- the same npm ci arguments, run in the stage directory
  ( cd "$PI__STAGE" && PATH="$_pi_nb:$PATH" && export PATH \
    && npm ci --ignore-scripts --min-release-age=0 --omit=dev --include=optional --no-fund --no-audit --loglevel=error --progress=false >&2 ) \
    || { pi__stage_fail "npm ci for Pi $_pi_sv failed"; return 1; }
  _pi_sb="$PI__STAGE/node_modules/.bin/pi"
  [ -x "$_pi_sb" ] || { pi__stage_fail "npm ci did not create node_modules/.bin/pi for Pi $_pi_sv"; return 1; }
  # spec: ref/package-manager-cli.js verifyManagedRelease
  _pi_got="$(PATH="$_pi_nb:$PATH" "$_pi_sb" --version)" \
    || { pi__stage_fail "could not verify Pi $_pi_sv: pi --version failed"; return 1; }
  [ "$_pi_got" = "$_pi_sv" ] \
    || { pi__stage_fail "Pi smoke test returned version $_pi_got; expected $_pi_sv"; return 1; }
  if pi_release_valid "$_pi_sv"; then
    pi__unstage
    return 0
  fi
  if [ -e "$_pi_rel" ] || [ -L "$_pi_rel" ]; then rm -rf "$_pi_rel"; fi
  mv "$PI__STAGE" "$_pi_rel" || { pi__stage_fail "cannot move the staged Pi $_pi_sv into $_pi_rel"; return 1; }
  PI__STAGE=""
  return 0
}

# spec: .superpowers/specs/2026-10-09-mavergreen-pi-design.md, "Initial-seed detail" -- the marker and
#       current-version are written only once releases/<v> is complete, so an interrupted seed is never valid
pi__seed() {
  if { [ -e "$PI_MROOT/managed-install.json" ] || [ -L "$PI_MROOT/managed-install.json" ]; } && ! pi_marker_valid; then
    pi_note "$PI_MROOT/managed-install.json is not a marker this wrapper understands (only releases-v1); leaving $PI_MROOT untouched"
    return 1
  fi
  mkdir -p "$PI_MROOT/releases" "$PI_MROOT/staging" || { pi_note "cannot create $PI_MROOT/releases"; return 1; }
  if ! pi_release_valid "$1"; then
    pi__stage_release "$1" || return 1
  fi
  pi_write_atomic "$PI_MROOT/managed-install.json" "$PI_MARKER_JSON" \
    || { pi_note "cannot write $PI_MROOT/managed-install.json"; return 1; }
  pi_write_atomic "$PI_MROOT/current-version" "$1" \
    || { pi_note "cannot write $PI_MROOT/current-version"; return 1; }
  return 0
}

pi_stage() {
  pi__seeded && return 0
  _pi_sf="$PI_TREE/share/pi/seed-version"
  _pi_seed=""
  [ ! -f "$_pi_sf" ] || _pi_seed="$(tr -d ' \t\r\n' < "$_pi_sf")"
  pi_is_version "$_pi_seed" || pi_die "$_pi_sf is missing or does not name a Pi version; reinstall Mavergreen/pi"
  mkdir -p "$PI_MROOT" || { pi_note "cannot create $PI_MROOT"; return 1; }
  pi__lock || return 1
  _pi_src=0
  pi__seeded || pi__seed "$_pi_seed" || _pi_src=$?
  pi__unlock
  return "$_pi_src"
}
