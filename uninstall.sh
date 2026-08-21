#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installed_config="$HOME/.local/lib/zen-auto-style/generated.conf"
zen_root="${ZEN_CONFIG_DIR:-$HOME/.config/zen}"

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

  # Fallback: try legacy ~/.zen root (old Zen installs, zen-browser-bin)
  local legacy_root="$HOME/.zen"
  if [[ "$zen_root" != "$legacy_root" && -d "$legacy_root" ]]; then
    local legacy_installs="$legacy_root/installs.ini"
    local legacy_profiles="$legacy_root/profiles.ini"
    if [[ -f $legacy_installs ]]; then
      profile_path="$(awk -F= '$1 == "Default" { print substr($0, index($0, "=") + 1); exit }' "$legacy_installs")"
      if [[ -n $profile_path && -d $legacy_root/$profile_path ]]; then
        printf '%s\n' "$legacy_root/$profile_path"
        return
      fi
    fi
    if [[ -f $legacy_profiles ]]; then
      profile_path="$(
        awk -F= '
          $1 == "Path" { path = substr($0, index($0, "=") + 1) }
          $1 == "Default" && $2 == "1" && path != "" { print path; exit }
        ' "$legacy_profiles"
      )"
      if [[ -n $profile_path && -d $legacy_root/$profile_path ]]; then
        printf '%s\n' "$legacy_root/$profile_path"
        return
      fi
    fi
  fi

  return 1
}

remove_managed_block() {
  local target=$1
  local begin_marker=$2
  local end_marker=$3
  local temporary

  [[ -f $target ]] || return 0
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

  [[ -f $target ]] || return 0
  temporary="$(mktemp)"
  grep -Fvx "$line" "$target" >"$temporary" || true
  mv "$temporary" "$target"
}

if [[ -f $installed_config ]]; then
  # shellcheck source=/dev/null
  source "$installed_config"
  native_host_name="$NATIVE_HOST_NAME"
else
  # shellcheck source=project.conf
  source "$project_dir/project.conf"
  native_host_name="${ZEN_AUTO_STYLE_NATIVE_HOST_NAME:-$NATIVE_HOST_NAME}"
fi

rm -f "$HOME/.mozilla/native-messaging-hosts/$native_host_name.json"
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

rm -rf "$HOME/.local/lib/zen-auto-style"
rm -rf "$HOME/.cache/zen-auto-style"

echo "Removed Zen Auto Style's native host, Omarchy hook, browser imports, and managed files."
echo "User-owned CSS outside the managed blocks was preserved."
