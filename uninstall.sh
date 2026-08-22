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

# Remove the dangerous prefs the legacy extension required. These weaken Zen's
# security posture (signature bypass + experiment APIs) and have no purpose
# once the extension is gone. Clean both user.js and prefs.js — Zen reads
# prefs.js at runtime, so cleaning only user.js leaves them active.
remove_exact_line "$zen_profile/user.js" \
  'user_pref("extensions.experiments.enabled", true);'
remove_exact_line "$zen_profile/user.js" \
  'user_pref("xpinstall.signatures.required", false);'
remove_exact_line "$zen_profile/prefs.js" \
  'user_pref("extensions.experiments.enabled", true);'
remove_exact_line "$zen_profile/prefs.js" \
  'user_pref("xpinstall.signatures.required", false);'

# Purge the ghost addon id from Zen's extension registry. The .xpi is gone,
# but prefs.js keeps the UUID mapping and weave/addonsreconciler.json keeps a
# sync record. Both are inert without the .xpi, but leaving them is not a
# 100% removal. prefs.js is rewritten by Zen on shutdown, so warn if it is
# running: the edit would be overwritten on next close.
legacy_addon_id="zen-auto-style@omarchy.local"

# Zen rewrites prefs.js on shutdown, so editing it while the browser runs is
# pointless. Refuse rather than silently lose the edit.
if [[ -f $zen_profile/.parentlock || -f $zen_profile/lock || -f $zen_profile/.lock ]]; then
  echo "Warning: Zen appears to be running. Close it before purging the ghost" >&2
  echo "addon id, or Zen will overwrite prefs.js on shutdown." >&2
fi

purge_pref_line() {
  local target=$1
  local pattern=$2

  [[ -f $target ]] || return 0
  grep -Fq "$pattern" "$target" || return 0
  backup_file "$target"
  local temporary
  temporary="$(mktemp)"
  grep -Fv "$pattern" "$target" >"$temporary" || true
  mv "$temporary" "$target"
}

purge_uuid_from_prefs() {
  local prefs_file=$1
  local uuids_line

  [[ -f $prefs_file ]] || return 0
  # Only the extensions.webextensions.uuids line holds the id→uuid map.
  uuids_line=$(grep -F 'extensions.webextensions.uuids' "$prefs_file") || return 0
  case $uuids_line in
    *"$legacy_addon_id"*) ;;
    *) return 0 ;;
  esac

  backup_file "$prefs_file"
  local temporary
  temporary="$(mktemp)"
  # Drop the trailing }); then strip the orphan comma+entry before it.
  sed "s/,\"$legacy_addon_id\":\"[^\"]*\"//" "$prefs_file" \
    | sed "s/,\"$legacy_addon_id\":\"[^\"]*\"//" \
    >"$temporary"
  mv "$temporary" "$prefs_file"
}

purge_reconciler_entry() {
  local reconciler_file=$1

  [[ -f $reconciler_file ]] || return 0
  grep -Fq "$legacy_addon_id" "$reconciler_file" || return 0
  command -v jq >/dev/null 2>&1 || return 0

  backup_file "$reconciler_file"
  local temporary
  temporary="$(mktemp)"
  jq --arg id "$legacy_addon_id" \
    'if .addons then .addons |= del(.[$id]) else . end' \
    "$reconciler_file" >"$temporary" 2>/dev/null || return 0
  mv "$temporary" "$reconciler_file"
}

purge_uuid_from_prefs "$zen_profile/prefs.js"
purge_reconciler_entry "$zen_profile/weave/addonsreconciler.json"

echo "Removed Zen Auto Style's Omarchy hook, browser imports, and managed files."
echo "Legacy native host and extension artifacts cleaned up."
echo "Ghost addon id purged from Zen's extension registry."
echo "User-owned CSS outside the managed blocks was preserved."
