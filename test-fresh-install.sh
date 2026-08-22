#!/bin/bash

# test-fresh-install.sh — Verify zen-auto-style on a 100% clean profile.
#
# Creates a throwaway Zen profile in a temp directory, runs install.sh
# against it, launches Zen with -no-remote so it does not connect to your
# running instance, and verifies the installation is correct. Nothing
# touches your real ~/.zen profile.
#
# Usage:
#   ./test-fresh-install.sh           # create, install, launch, verify, keep dir
#   ./test-fresh-install.sh --clean    # same, but delete the temp profile after
#
# Requirements:
#   - Zen binary at /opt/zen-browser-bin/zen (or set ZEN_BIN=/path/to/zen)
#   - omarchy command available (for theme refresh)
#   - This script must be run from the repo root.

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zen_bin="${ZEN_BIN:-/opt/zen-browser-bin/zen}"
test_profile_root="${TEST_PROFILE_ROOT:-$(mktemp -d -t zen-auto-style-test-XXXXXX)}"
clean_after=0

if [[ ${1:-} == "--clean" ]]; then
  clean_after=1
fi

cleanup() {
  if (( clean_after )); then
    rm -rf "$test_profile_root"
    echo "Cleaned up test profile: $test_profile_root"
  else
    echo "Test profile kept at: $test_profile_root"
    echo "Re-launch with: $zen_bin -profile \"$test_profile_root\" -no-remote"
  fi
}
trap cleanup EXIT

echo "=== Zen Auto Style — Fresh Install Test ==="
echo "Test profile:  $test_profile_root"
echo "Zen binary:    $zen_bin"
echo ""

# --- Step 1: Verify Zen binary exists ---
if [[ ! -x $zen_bin ]]; then
  echo "ERROR: Zen binary not found at $zen_bin" >&2
  echo "Set ZEN_BIN=/path/to/zen to override." >&2
  exit 1
fi
echo "[1/6] Zen binary found."

# --- Step 2: Bootstrap a fresh Zen profile ---
# Zen needs to run once to create profiles.ini, installs.ini, and the profile
# directory. -profile tells Zen to use this exact dir as the profile root.
# -no-remote prevents connecting to the running instance.
# We use -P to create a new named profile, then launch briefly so Zen writes
# the ini files.
echo "[2/6] Bootstrapping fresh Zen profile..."

# Method 1: -CreateProfile creates the profile dir + profiles.ini
"$zen_bin" -CreateProfile "ZenAutoStyleTest $test_profile_root" -no-remote >/dev/null 2>&1 || true

# Method 2: If that didn't create installs.ini, launch headless briefly.
# -profile <dir> forces Zen to use that dir as a profile, creating it if needed.
if [[ ! -f "$test_profile_root/installs.ini" && ! -f "$test_profile_root/profiles.ini" ]]; then
  timeout 10 "$zen_bin" -profile "$test_profile_root" -headless -no-remote >/dev/null 2>&1 || true
fi

# Method 3: Zen may create a subdirectory profile. Find it.
profile_subdir=""
if [[ -f "$test_profile_root/installs.ini" ]]; then
  profile_subdir="$(
    awk -F= '$1 == "Default" { print substr($0, index($0, "=") + 1); exit }' \
      "$test_profile_root/installs.ini"
  )"
elif [[ -f "$test_profile_root/profiles.ini" ]]; then
  profile_subdir="$(
    awk -F= '
      $1 == "Path" { path = substr($0, index($0, "=") + 1) }
      $1 == "Default" && $2 == "1" && path != "" { print path; exit }
    ' "$test_profile_root/profiles.ini"
  )"
fi

# If still no profile found, create the structure manually and use ZEN_PROFILE
if [[ -z $profile_subdir ]]; then
  profile_subdir="zas-test.default"
  mkdir -p "$test_profile_root/$profile_subdir/chrome"
  # Create a minimal profiles.ini so install.sh's find_zen_profile can find it
  cat >"$test_profile_root/profiles.ini" <<PROFILES_INI
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=ZenAutoStyleTest
IsRelative=1
Path=$profile_subdir
Default=1
PROFILES_INI
  echo "      (Created minimal profile structure manually)"
fi

if [[ ! -d "$test_profile_root/$profile_subdir" ]]; then
  mkdir -p "$test_profile_root/$profile_subdir/chrome"
fi
echo "      Profile ready: $test_profile_root/$profile_subdir"

# --- Step 3: Run install.sh against the test profile ---
echo "[3/6] Running install.sh against test profile..."
# Use ZEN_PROFILE to point directly at the profile dir, bypassing discovery.
# Also set ZEN_CONFIG_DIR for the legacy cleanup that uses zen_root.
ZEN_CONFIG_DIR="$test_profile_root" \
ZEN_PROFILE="$test_profile_root/$profile_subdir" \
  "$project_dir/install.sh"
echo ""

# --- Step 4: Verify all installed files exist ---
echo "[4/6] Verifying installed files..."

chrome_dir="$test_profile_root/$profile_subdir/chrome"
errors=0

check_file() {
  local file=$1
  if [[ -e $file || -L $file ]]; then
    echo "  OK   $file"
  else
    echo "  FAIL $file (missing)"
    errors=$((errors + 1))
  fi
}

check_file "$chrome_dir/zen-auto-style-chrome.css"
check_file "$chrome_dir/zen-auto-style-content.css"
check_file "$chrome_dir/zen-auto-style-mods.css"
check_file "$chrome_dir/custom-zen.css"
check_file "$chrome_dir/userChrome.css"
check_file "$chrome_dir/userContent.css"
check_file "$test_profile_root/$profile_subdir/user.js"

# Verify the managed block in userChrome.css
if ! grep -q 'BEGIN ZEN AUTO STYLE' "$chrome_dir/userChrome.css" 2>/dev/null; then
  echo "  FAIL managed block missing in userChrome.css"
  errors=$((errors + 1))
fi

# Verify the only pref in user.js is the stylesheet one
dangerous_prefs=$(grep -c 'experiments\|xpinstall.signatures' \
  "$test_profile_root/$profile_subdir/user.js" 2>/dev/null || true)
if [[ -n $dangerous_prefs && $dangerous_prefs -gt 0 ]]; then
  echo "  FAIL dangerous legacy prefs found in user.js"
  errors=$((errors + 1))
else
  echo "  OK   no dangerous legacy prefs in user.js"
fi

# Verify the symlink points to an existing file
link_target=$(readlink -f "$chrome_dir/custom-zen.css" 2>/dev/null || true)
if [[ -n $link_target && -f $link_target ]]; then
  echo "  OK   custom-zen.css symlink resolves to: $link_target"
else
  echo "  WARN custom-zen.css symlink does not resolve (Omarchy may not have rendered yet)"
fi

if (( errors > 0 )); then
  echo ""
  echo "FAIL: $errors error(s) found in fresh install." >&2
  exit 1
fi
echo ""

# --- Step 5: Verify no legacy artifacts ---
echo "[5/6] Checking for legacy extension artifacts..."
legacy_errors=0
[[ -d $HOME/.local/lib/zen-auto-style ]] && { echo "  FAIL ~/.local/lib/zen-auto-style exists"; legacy_errors=$((legacy_errors + 1)); } || echo "  OK   no ~/.local/lib/zen-auto-style"
[[ -f $HOME/.mozilla/native-messaging-hosts/org.omarchy.zen_auto_style.json ]] && { echo "  FAIL native-messaging-hosts manifest exists"; legacy_errors=$((legacy_errors + 1)); } || echo "  OK   no native-messaging manifest"
if (( legacy_errors > 0 )); then
  echo "FAIL: legacy artifacts remain." >&2
  exit 1
fi
echo ""

# --- Step 6: Launch Zen with the test profile for visual inspection ---
#
# On a fresh profile, user.js is read on first launch, which sets
# toolkit.legacyUserProfileCustomizations.stylesheets=true. But userChrome.css
# is only loaded on the NEXT restart. So we need two launches:
#   1. Headless: process user.js, create prefs.js, then exit.
#   2. GUI: load userChrome.css with the pref already active.
echo "[6/7] Bootstrapping Zen (first launch to process user.js)..."
timeout 10 "$zen_bin" -profile "$test_profile_root/$profile_subdir" \
  -headless -no-remote >/dev/null 2>&1 || true

# Verify prefs.js now has the stylesheet pref
if grep -q 'legacyUserProfileCustomizations.stylesheets.*true' \
  "$test_profile_root/$profile_subdir/prefs.js" 2>/dev/null; then
  echo "      OK   prefs.js has stylesheet preference enabled."
else
  echo "      WARN prefs.js may not have the preference yet (will apply on next launch)."
fi
echo ""

echo "[7/7] Launching Zen with test profile for visual verification."
echo ""
echo "  Open about:preferences or about:newtab to check theming."
echo "  Run 'omarchy theme set <theme>' to test live palette changes."
echo "  Close Zen when done."
echo ""
echo "  Command: $zen_bin -profile \"$test_profile_root/$profile_subdir\" -no-remote"
echo ""

if [[ -t 0 ]]; then
  read -r -p "Press Enter to launch Zen, or Ctrl+C to skip..."
  "$zen_bin" -profile "$test_profile_root/$profile_subdir" -no-remote &
  wait $!
else
  echo "(Non-interactive: skipping visual launch. Run the command above manually.)"
fi

echo ""
echo "=== All checks passed. Fresh install verified. ==="
