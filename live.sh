#!/bin/bash

# Omarchy Zen live reload: opt-in, extension-free.
#
# Installs a Firefox autoconfig script (live/omarchy-zen.cfg) into Zen's
# install directory. At startup Zen runs it with chrome privileges; it polls
# the profile's chrome/custom-zen.css once per second and re-registers the
# palette variables when the theme changes, so Zen repaints without a restart.
#
# No extension, no signature bypass, no experiments pref, no open port, no
# daemon. Tradeoff: the two files live in the root-owned Zen install dir, so
# enable/disable needs sudo. Unowned files survive zen-browser-bin upgrades.
#
# Usage: ./live.sh enable | disable | status

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state_dir="$HOME/.local/state/zen-auto-style"
state_file="$state_dir/live"
cfg_name="omarchy-zen.cfg"
prefs_name="omarchy-zen-prefs.js"

find_zen_dir() {
  local dir launcher

  if [[ -n ${ZEN_INSTALL_DIR:-} ]]; then
    printf '%s\n' "$ZEN_INSTALL_DIR"
    return
  fi

  # The Arch package ships /usr/bin/zen-browser as `exec <dir>/zen-bin "$@"`.
  for launcher in zen-browser zen; do
    command -v "$launcher" >/dev/null 2>&1 || continue
    launcher="$(readlink -f "$(command -v "$launcher")")"
    dir="$(sed -n 's|^exec \(/[^ ]*\)/zen-bin.*|\1|p' "$launcher" 2>/dev/null | head -n1)"
    [[ -z $dir ]] && dir="$(dirname "$launcher")"
    if [[ -f $dir/application.ini ]]; then
      printf '%s\n' "$dir"
      return
    fi
  done

  [[ -f /opt/zen-browser-bin/application.ini ]] && printf '%s\n' /opt/zen-browser-bin && return
  return 1
}

# Autoconfig honors a single general.config.filename; refuse to clobber
# another tool's loader (fx-autoconfig, enterprise config, ...).
foreign_autoconfig() {
  local zen_dir=$1
  grep -ls 'general.config.filename' "$zen_dir"/defaults/pref/*.js \
    | grep -v "/$prefs_name\$" || true
}

zen_dir="$(find_zen_dir)" || {
  echo "Unable to find the Zen install directory." >&2
  echo "Rerun with ZEN_INSTALL_DIR=/path/to/zen (the dir with application.ini)." >&2
  exit 1
}

case "${1:-status}" in
  enable)
    foreign="$(foreign_autoconfig "$zen_dir")"
    if [[ -n $foreign ]]; then
      echo "Another autoconfig loader is already configured:" >&2
      printf '  %s\n' $foreign >&2
      echo "Live reload was not enabled; the restart-based sync keeps working." >&2
      exit 1
    fi
    sudo install -Dm644 "$project_dir/live/$prefs_name" "$zen_dir/defaults/pref/$prefs_name"
    sudo install -Dm644 "$project_dir/live/$cfg_name" "$zen_dir/$cfg_name"
    mkdir -p "$state_dir"
    printf '%s\n' "$zen_dir" >"$state_file"
    echo "Live reload enabled in $zen_dir."
    echo "Restart Zen once; from then on theme switches apply instantly."
    ;;
  disable)
    sudo rm -f "$zen_dir/defaults/pref/$prefs_name" "$zen_dir/$cfg_name"
    rm -f "$state_file"
    echo "Live reload disabled. Restart Zen to unload it."
    ;;
  status)
    if [[ -f $zen_dir/$cfg_name && -f $zen_dir/defaults/pref/$prefs_name ]]; then
      if cmp -s "$project_dir/live/$cfg_name" "$zen_dir/$cfg_name"; then
        echo "enabled ($zen_dir)"
      else
        echo "enabled, outdated ($zen_dir) — rerun: ./live.sh enable"
      fi
    else
      echo "disabled ($zen_dir)"
    fi
    ;;
  *)
    echo "Usage: $0 enable | disable | status" >&2
    exit 2
    ;;
esac
