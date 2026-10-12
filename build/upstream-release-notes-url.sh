#!/bin/sh
# platform: host-agnostic
set -eu
printf 'https://github.com/earendil-works/pi/releases/tag/v%s\n' "${1:?usage: upstream-release-notes-url.sh <upstream-version>}"
