#!/bin/sh
# platform: macOS-only -- runs inside the Installer preinstall shipyard's stage_product.sh writes for Mac OS X 10.9
_pi_hand="$ROOT/usr/local/mavergreen/node24/lib/node_modules/@earendil-works/pi-coding-agent"
if [ -e "$_pi_hand" ] || [ -L "$_pi_hand" ]; then
  echo "Pi for Mavericks: Pi is installed by hand into Node.js 24 ($_pi_hand), and its pi command would clash with this one." >&2
  echo "Remove it, relink Node.js 24, then run this installer again:" >&2
  if [ -z "$ROOT" ]; then
    echo "  sudo /usr/local/mavergreen/node24/bin/npm -g uninstall @earendil-works/pi-coding-agent" >&2
    echo "  sudo mavergreen unlink node24 && sudo mavergreen link node24" >&2
  else
    # platform: node24's npm wrapper hard-codes /usr/local/mavergreen, so on another volume it would act on the boot volume
    echo "  sudo rm -rf '$_pi_hand' '$ROOT/usr/local/mavergreen/node24/bin/pi'" >&2
    echo "  sudo mavergreen --root '$ROOT/' unlink node24 && sudo mavergreen --root '$ROOT/' link node24" >&2
  fi
  false
fi
