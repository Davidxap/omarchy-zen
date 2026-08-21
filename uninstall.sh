#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n ${ZEN_CONFIG_DIR:-} ]]; then
  zen_root="$ZEN_CONFIG_DIR"
elif [[ -d "$HOME/.zen" ]]; then
  zen_root="$HOME/.zen"
else
  zen_root="$HOME/.config/zen"
fi

find_zen_profile() {
  local installs_file="$zen_root/installs.ini"
  local profiles_file="$zen_root/profiles.ini"
  local profile_path

  if [[ -n ${ZEN_PROFILE:-} ]]; then
    if [[ ! -d $ZEN_PROFILE ]]; then
      echo "ZEN_PROFILE does not exist: $ZEN_PROFILE" >&2
      return 1
    fi
    printf '%s\n' "$ZEN_PROFILE"
    return
  fi

  if [[ -f $installs_file ]]; then
    profile_path="$(awk -F= '$1 == "Default" { print substr($0, index($0, "=") + 1); exit }' "$installs_file")"
    if [[ -n $profile_path && -d $zen_root/$profile_path ]]; then
      printf '%s\n' "$zen_root/$profile_path"
      return
    fi
  fi

  if [[ -f $profiles_file ]]; then
    profile_path="$(
      awk -F= '
        $1 == "Path" { path = substr($0, index($0, "=") + 1) }
        $1 == "Default" && $2 == "1" && path != "" { print path; exit }
      ' "$profiles_file"
    )"
    if [[ -n $profile_path && -d $zen_root/$profile_path ]]; then
      printf '%s\n' "$zen_root/$profile_path"
      return
    fi
  fi

  return 1
}

remove_managed_block() {
  local target=$1
  local begin_marker=$2
  local end_marker=$3
  local temporary

  [[ -f $target ]] || return
  temporary="$(mktemp)"
  awk \
    -v begin="$begin_marker" \
    -v end="$end_marker" '
      $0 == begin { managed = 1; next }
      $0 == end { managed = 0; next }
      !managed { print }
    ' "$target" >"$temporary"
  mv "$temporary" "$target"
}

remove_exact_line() {
  local target=$1
  local line=$2
  local temporary

  [[ -f $target ]] || return
  temporary="$(mktemp)"
  grep -Fvx "$line" "$target" >"$temporary" || true
  mv "$temporary" "$target"
}

rm -f "$HOME/.config/omarchy/hooks/theme-set.d/zen-auto-style"

if zen_profile="$(find_zen_profile)"; then
  chrome_dir="$zen_profile/chrome"

  remove_managed_block \
    "$chrome_dir/userChrome.css" \
    '/* BEGIN ZEN AUTO STYLE */' \
    '/* END ZEN AUTO STYLE */'
  remove_managed_block \
    "$chrome_dir/userContent.css" \
    '/* BEGIN ZEN AUTO STYLE */' \
    '/* END ZEN AUTO STYLE */'
  remove_managed_block \
    "$zen_profile/user.js" \
    '// BEGIN ZEN AUTO STYLE' \
    '// END ZEN AUTO STYLE'

  remove_exact_line "$chrome_dir/userChrome.css" '@import url("zen-auto-style-chrome.css");'
  remove_exact_line "$chrome_dir/userChrome.css" '@import url("zen-auto-style-mods.css");'
  remove_exact_line "$chrome_dir/userContent.css" '@import url("zen-auto-style-content.css");'

  rm -f \
    "$chrome_dir/zen-auto-style-chrome.css" \
    "$chrome_dir/zen-auto-style-content.css" \
    "$chrome_dir/zen-auto-style-mods.css" \
    "$chrome_dir/custom-zen.css"
  rm -rf "$chrome_dir/zen-auto-style-mods"
fi

template="$HOME/.config/omarchy/themed/custom-zen.css.tpl"
if [[ -f $template ]] && cmp -s "$template" "$project_dir/assets/omarchy/custom-zen.css.tpl"; then
  rm -f "$template"
fi

# Clean up all legacy artifacts from the old extension-based install.
rm -rf "$HOME/.local/lib/zen-auto-style"
rm -f "$HOME/.mozilla/native-messaging-hosts/org.omarchy.zen_auto_style.json"
rm -rf "$HOME/.cache/zen-auto-style"

echo "Removed Zen Auto Style's Omarchy hook, browser imports, and managed files."
echo "Legacy native host and extension artifacts cleaned up."
echo "User-owned CSS outside the managed blocks was preserved."
