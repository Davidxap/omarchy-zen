#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook_dir="$HOME/.config/omarchy/hooks/theme-set.d"
template_dir="$HOME/.config/omarchy/themed"
if [[ -n ${ZEN_CONFIG_DIR:-} ]]; then
  zen_root="$ZEN_CONFIG_DIR"
elif [[ -d "$HOME/.zen" ]]; then
  zen_root="$HOME/.zen"
else
  zen_root="$HOME/.config/zen"
fi
state_dir="$HOME/.local/state/zen-auto-style"
backup_root="$state_dir/backups/$(date +%Y%m%d-%H%M%S-%N)-$$"

find_zen_profile() {
  local installs_file="$zen_root/installs.ini"
  local profiles_file="$zen_root/profiles.ini"
  local profile_path

  if [[ -n ${ZEN_PROFILE:-} ]]; then
    if [[ ! -d $ZEN_PROFILE ]]; then
      echo "ZEN_PROFILE does not exist: $ZEN_PROFILE" >&2
      echo "Start the browser once, or remove the override to use auto-discovery." >&2
      return 1
    fi
    printf '%s\n' "$ZEN_PROFILE"
    return
  fi

  if [[ -f $installs_file ]]; then
    profile_path="$(
      awk -F= '
        $1 == "Default" {
          value = substr($0, index($0, "=") + 1)
          if (value != "") {
            print value
            exit
          }
        }
      ' "$installs_file"
    )"
    if [[ -n $profile_path && -d $zen_root/$profile_path ]]; then
      printf '%s\n' "$zen_root/$profile_path"
      return
    fi
  fi

  if [[ -f $profiles_file ]]; then
    profile_path="$(
      awk -F= '
        $1 == "Path" { path = substr($0, index($0, "=") + 1) }
        $1 == "Default" && $2 == "1" && path != "" {
          print path
          exit
        }
      ' "$profiles_file"
    )"
    if [[ -n $profile_path && -d $zen_root/$profile_path ]]; then
      printf '%s\n' "$zen_root/$profile_path"
      return
    fi
  fi

  return 1
}

backup_file() {
  local path=$1

  if [[ -e $path || -L $path ]]; then
    mkdir -p "$backup_root"
    cp -a "$path" "$backup_root/"
  fi
}

# Install with backups, skipping identical content (keeps mtimes stable and
# avoids pointless writes on re-runs).
install_file() {
  local src=$1 dst=$2 mode=$3

  if [[ -f $dst && ! -L $dst ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  backup_file "$dst"
  install -m "$mode" "$src" "$dst"
}

ensure_managed_block() {
  local target=$1
  local begin_marker=$2
  local end_marker=$3
  local content=$4
  local temporary
  local existed=0

  [[ -e $target ]] && existed=1
  touch "$target"
  temporary="$(mktemp)"

  awk \
    -v begin="$begin_marker" \
    -v end="$end_marker" '
      $0 == begin { managed = 1; next }
      $0 == end { managed = 0; next }
      !managed { print }
    ' "$target" >"$temporary"

  {
    printf '%s\n%s\n%s\n\n' "$begin_marker" "$content" "$end_marker"
    cat "$temporary"
  } >"$temporary.new"

  if cmp -s "$temporary.new" "$target"; then
    rm -f "$temporary" "$temporary.new"
  else
    (( existed )) && backup_file "$target"
    mv "$temporary.new" "$target"
    rm -f "$temporary"
  fi
}

remove_legacy_line() {
  local target=$1
  local line=$2
  local temporary

  [[ -f $target ]] || return 0
  grep -Fqx "$line" "$target" || return 0

  backup_file "$target"
  temporary="$(mktemp)"
  grep -Fvx "$line" "$target" >"$temporary" || true
  mv "$temporary" "$target"
}

zen_profile="$(find_zen_profile)" || {
  echo "Unable to find Zen's active profile under $zen_root." >&2
  echo "Start Zen once, or rerun with ZEN_PROFILE=/absolute/profile/path." >&2
  exit 1
}

chrome_dir="$zen_profile/chrome"

mkdir -p \
  "$hook_dir" \
  "$template_dir" \
  "$chrome_dir"

# Fast path: if this exact plugin version is already installed and the wiring
# is intact, there is nothing to do. Keeps the service's per-login run in the
# low milliseconds (no writes, no backups).
plugin_version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$project_dir/manifest.json" | head -n1)"
stamp_file="$state_dir/installed"
stamp_value="${plugin_version:-unknown}"
if [[ -f $stamp_file ]] && [[ $stamp_value == "$(cat "$stamp_file")" ]] \
  && [[ -L $chrome_dir/custom-zen.css ]] \
  && grep -qs 'BEGIN ZEN AUTO STYLE' "$chrome_dir/userChrome.css" \
  && grep -qs 'legacyUserProfileCustomizations.stylesheets' "$zen_profile/user.js" \
  && cmp -s "$project_dir/assets/omarchy/custom-zen.css.tpl" "$template_dir/custom-zen.css.tpl" 2>/dev/null \
  && cmp -s "$project_dir/assets/zen/zen-auto-style-chrome.css" "$chrome_dir/zen-auto-style-chrome.css" 2>/dev/null \
  && cmp -s "$project_dir/omarchy/theme-set-hook" "$hook_dir/zen-auto-style" \
  && [[ -f $state_dir/render-custom-zen.py ]]; then
  echo "Omarchy Zen ${plugin_version:-?} already installed; nothing to do."
  exit 0
fi

install_file \
  "$project_dir/omarchy/theme-set-hook" \
  "$hook_dir/zen-auto-style" 755

mkdir -p "$state_dir"
install_file \
  "$project_dir/tools/render-custom-zen.py" \
  "$state_dir/render-custom-zen.py" 755

install_file \
  "$project_dir/assets/omarchy/custom-zen.css.tpl" \
  "$template_dir/custom-zen.css.tpl" 644

install_file \
  "$project_dir/assets/zen/zen-auto-style-chrome.css" \
  "$chrome_dir/zen-auto-style-chrome.css" 644
install_file \
  "$project_dir/assets/zen/zen-auto-style-content.css" \
  "$chrome_dir/zen-auto-style-content.css" 644

# Remove mods leftovers from previous installs (feature removed in 1.2.0).
rm -rf "$chrome_dir/zen-auto-style-mods" "$chrome_dir/zen-auto-style-mods.css"

remove_legacy_line \
  "$chrome_dir/userChrome.css" \
  '@import url("zen-auto-style-chrome.css");'
remove_legacy_line \
  "$chrome_dir/userChrome.css" \
  '@import url("zen-auto-style-mods.css");'
remove_legacy_line \
  "$chrome_dir/userContent.css" \
  '@import url("zen-auto-style-content.css");'

ensure_managed_block \
  "$chrome_dir/userChrome.css" \
  '/* BEGIN ZEN AUTO STYLE */' \
  '/* END ZEN AUTO STYLE */' \
  '@import url("zen-auto-style-chrome.css");'
ensure_managed_block \
  "$chrome_dir/userContent.css" \
  '/* BEGIN ZEN AUTO STYLE */' \
  '/* END ZEN AUTO STYLE */' \
  '@import url("zen-auto-style-content.css");'

# Remove dangerous prefs left over from the legacy extension-based install.
#
# prefs.js is the file Zen actually reads at runtime. user.js is only applied
# on startup and then merged into prefs.js, so cleaning user.js alone leaves
# the dangerous values active. Clean BOTH files.
remove_legacy_line \
  "$zen_profile/user.js" \
  'user_pref("extensions.experiments.enabled", true);'
remove_legacy_line \
  "$zen_profile/user.js" \
  'user_pref("xpinstall.signatures.required", false);'
remove_legacy_line \
  "$zen_profile/prefs.js" \
  'user_pref("extensions.experiments.enabled", true);'
remove_legacy_line \
  "$zen_profile/prefs.js" \
  'user_pref("xpinstall.signatures.required", false);'

# Only toolkit.legacyUserProfileCustomizations.stylesheets is needed for
# userChrome.css to work. No experiment_apis, no signature bypass.
remove_legacy_line \
  "$zen_profile/user.js" \
  'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
ensure_managed_block \
  "$zen_profile/user.js" \
  '// BEGIN ZEN AUTO STYLE' \
  '// END ZEN AUTO STYLE' \
  'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'

backup_file "$chrome_dir/custom-zen.css"

# Resolve the Omarchy theme directory for both 4.x (state) and legacy (config)
if [[ -d "$HOME/.local/state/omarchy/current/theme" ]]; then
  _theme_custom_css="$HOME/.local/state/omarchy/current/theme/custom-zen.css"
elif [[ -d "$HOME/.config/omarchy/current/theme" ]]; then
  _theme_custom_css="$HOME/.config/omarchy/current/theme/custom-zen.css"
else
  _theme_custom_css="$HOME/.local/state/omarchy/current/theme/custom-zen.css"
fi

ln -sfn "$_theme_custom_css" "$chrome_dir/custom-zen.css"

# Clean up legacy extension and native host artifacts from previous installs.
rm -rf "$HOME/.local/lib/zen-auto-style"
rm -f "$HOME/.mozilla/native-messaging-hosts/org.omarchy.zen_auto_style.json"
rm -rf "$HOME/.cache/zen-auto-style"

if command -v omarchy >/dev/null 2>&1; then
  if ! timeout 30 omarchy theme refresh >/dev/null 2>&1; then
    echo "Warning: 'omarchy theme refresh' failed; run it manually." >&2
  fi
else
  echo "Warning: omarchy is not on PATH; run 'omarchy theme refresh' later." >&2
fi

# Deterministic guard: omarchy skips template renders when the theme ships its
# own custom-zen.css or a theme switch was interrupted, leaving a stale sheet
# behind. Verify the state sheet matches the resolved palette and re-render
# from colors.toml if it does not.
_theme_root="$(dirname "$_theme_custom_css")"
if [[ -f $state_dir/render-custom-zen.py && -f $_theme_root/colors.toml && -f $_theme_custom_css ]]; then
  _expected="$(sed -n 's/^background *= *"\(#[0-9a-fA-F]\{6\}\)"/\1/p' "$_theme_root/colors.toml" | head -n1)"
  _actual="$(sed -n 's/--custom-zen-bg: *\(#[0-9a-fA-F]\{6\}\);/\1/p' "$_theme_custom_css" | head -n1)"
  if [[ $_expected != "$_actual" ]]; then
    if timeout 30 python3 "$state_dir/render-custom-zen.py" "$_theme_root/colors.toml" "$_theme_custom_css" \
      >/dev/null 2>&1; then
      echo "Re-rendered custom-zen.css from the current palette."
    else
      echo "Warning: could not re-render custom-zen.css from colors.toml." >&2
    fi
  fi
fi

# Stamp the successful install so subsequent runs can take the fast path.
mkdir -p "$state_dir"
printf '%s\n' "$stamp_value" >"$stamp_file"

# Keep only the 5 most recent backups.
if [[ -d $backup_root ]]; then
  while IFS= read -r old; do
    rm -rf "$old"
  done < <(ls -1d "$state_dir"/backups/*/ 2>/dev/null | sort -r | tail -n +6)
fi

echo "Installed Zen CSS into: $zen_profile"
echo "Installed Omarchy template and theme hook."
if [[ -d $backup_root ]]; then
  echo "Backups: $backup_root"
fi
echo "Restart Zen once to pick up the themed CSS."
