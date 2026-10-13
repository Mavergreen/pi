#!/bin/sh
# platform: macOS-only -- installs .pkg products with /usr/sbin/installer on Mac OS X 10.9
#   usage: curl -fsSL https://github.com/Mavergreen/pi/releases/latest/download/install.sh | sh
#          Installs or updates node24, fd, rg and Pi for Mavericks, in that order, each from its
#          repo's latest release. MAVERGREEN_RELEASES overrides the base URL that holds
#          <repo>/releases/latest/download/; MAVERGREEN_INSTALL_ROOT prefixes /usr/local/mavergreen
#          when reading what is already installed.

note() { printf 'Pi for Mavericks: %s\n' "$*"; }
die() { printf 'Pi for Mavericks: ERROR: %s\n' "$*" >&2; exit 1; }

main() {
  set -eu
  base="${MAVERGREEN_RELEASES:-https://github.com/Mavergreen}"
  root="${MAVERGREEN_INSTALL_ROOT-}"

  case "$(uname -s)" in Darwin) ;; *) die "only macOS is supported" ;; esac
  osver="$(sw_vers -productVersion 2>/dev/null || :)"
  case "$osver" in
    10.9.[5-9]|10.9.[1-9][0-9]*) ;;
    *) die "Mac OS X 10.9.5 is required; this Mac runs ${osver:-an unknown version}" ;;
  esac
  case "$(uname -m)" in x86_64|amd64) ;; *) die "unsupported arch: $(uname -m)" ;; esac

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-install.XXXXXX")" || die "could not create a temporary directory"
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  plan=""
  for triple in node24:nodejs-24:nodejs fd:fd:fd rg:rg:rg pi:pi:pi; do
    short="${triple%%:*}"; rest="${triple#*:}"; repo="${rest%%:*}"; prefix="${rest#*:}"
    url="$base/$repo/releases/latest/download"
    sums="$tmp/$repo.SHA256SUMS"
    curl -fsSL --proto-redir =https -o "$sums" "$url/SHA256SUMS" || die "$repo: could not fetch $url/SHA256SUMS"
    awk -v s="$prefix" '
      { n = $2; sub(/^\*/, "", n) }
      NF == 2 && $1 ~ /^[0-9a-f]+$/ && length($1) == 64 && n ~ ("^" s "-[0-9][0-9A-Za-z.+-]*\\.pkg$") { print $1, n }
    ' "$sums" > "$sums.match"
    count="$(wc -l < "$sums.match" | tr -d ' ')"
    [ "$count" -ne 0 ] || die "$repo: its latest release lists no $prefix-<version>.pkg in SHA256SUMS"
    [ "$count" -eq 1 ] || die "$repo: its latest release lists $count $prefix-<version>.pkg in SHA256SUMS, not one"
    read -r want asset < "$sums.match"
    ver="${asset#"$prefix"-}"; ver="${ver%.pkg}"
    plist="$root/usr/local/mavergreen/$short/mavergreen.plist"
    have=""
    if [ -f "$plist" ]; then
      have="$(/usr/libexec/PlistBuddy -c 'Print :version' "$plist" 2>/dev/null || :)"
    fi
    if [ "$have" = "$ver" ]; then
      note "$short $ver is already installed"
      continue
    fi
    note "downloading $asset"
    curl -fL --proto-redir =https --progress-bar -o "$tmp/$asset" "$url/$asset" || die "$repo: could not download $url/$asset"
    got="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
    [ -n "$got" ] && [ "$got" = "$want" ] || die "$asset does not match $url/SHA256SUMS (wanted $want, got ${got:-nothing})"
    plan="$plan $asset"
  done

  if [ -n "$plan" ]; then
    # spec: packaging/preinstall-hook.sh refuses Pi installed by hand into node24; saying so here,
    #       before anything is installed, leaves nothing half done
    hand="$root/usr/local/mavergreen/node24/lib/node_modules/@earendil-works/pi-coding-agent"
    case " $plan " in
      *" pi-"*)
        if [ -e "$hand" ] || [ -L "$hand" ]; then
          note "Pi is installed by hand into Node.js 24, and its pi command would clash with this one."
          note "Remove it and relink Node.js 24, then run this again:"
          note "  sudo /usr/local/mavergreen/node24/bin/npm -g uninstall @earendil-works/pi-coding-agent"
          note "  sudo mavergreen unlink node24 && sudo mavergreen link node24"
          die "Pi installed by hand into Node.js 24 is in the way"
        fi
        ;;
    esac
    # platform: sudo -v wants a tty even when every command needs no password (verifypw=all),
    #       so a passwordless or recently-validated sudo is asked first, non-interactively
    if ! sudo -n true 2>/dev/null; then
      note "installing needs an administrator's password"
      sudo -v || die "could not get administrator rights"
    fi
    for asset in $plan; do
      note "installing $asset"
      sudo /usr/sbin/installer -pkg "$tmp/$asset" -target / || die "installer failed on $asset"
    done
  else
    note "everything is up to date"
  fi

  note "done. Open a new Terminal window, then run pi."
}

main "$@"
