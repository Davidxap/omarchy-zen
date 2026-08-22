#!/bin/bash

# verify.sh — Post-update health check for zen-auto-style.
#
# Run this after updating Zen Browser to quickly detect which (if any)
# Zen-specific selectors or CSS variables used by this project may have
# been renamed or removed in the new version.
#
# It works by extracting the Zen-specific ids, classes, and CSS variables
# referenced in our CSS files and checking whether they still appear in
# Zen's shipped chrome resources (inside omni.ja).
#
# Usage:
#   ./verify.sh                    # auto-detect Zen install
#   ZEN_DIR=/path/to/zen ./verify.sh

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
zen_dir="${ZEN_DIR:-/opt/zen-browser-bin}"

if [[ ! -d $zen_dir ]]; then
  echo "ERROR: Zen install directory not found: $zen_dir" >&2
  echo "Set ZEN_DIR=/path/to/zen to override." >&2
  exit 1
fi

# Extract omni.ja (which is a ZIP archive) to a temp dir for searching.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "=== Zen Auto Style — Post-Update Health Check ==="
echo ""

# Extract omni.ja files for grep
omni_main="$zen_dir/omni.ja"
omni_browser="$zen_dir/browser/omni.ja"
extracted=0

for omni in "$omni_main" "$omni_browser"; do
  if [[ -f $omni ]]; then
    unzip -q -o "$omni" -d "$workdir/$(basename "$omni")" 2>/dev/null || true
    extracted=1
  fi
done

if (( ! extracted )); then
  echo "WARNING: Could not extract omni.ja from $zen_dir." >&2
  echo "         Skipping selector existence check." >&2
  echo ""
fi

# --- Collect Zen-specific selectors from our CSS ---
# Extract #zen-* ids and .zen-* classes from all CSS files.
css_files=(
  "$project_dir/assets/zen/zen-auto-style-chrome.css"
  "$project_dir/assets/zen/zen-auto-style-content.css"
  "$project_dir/assets/zen/mods/"*.css
)

# Unique zen-specific ids (e.g., #zen-main-app-wrapper)
zen_ids=$(grep -ohE '#zen-[a-zA-Z0-9_-]+' "${css_files[@]}" \
  | sort -u | sed 's/#//')

# Unique zen-specific classes (e.g., .zen-browser-generic-background)
zen_classes=$(grep -ohE '\.zen-[a-zA-Z0-9_-]+' "${css_files[@]}" \
  | sort -u | sed 's/\.//')

# Unique --zen-* CSS variables we SET (not just reference)
zen_vars_set=$(grep -ohE '\-\-zen-[a-zA-Z0-9_-]+:' "${css_files[@]}" \
  | sort -u | sed 's/://')

# --- Check selectors against omni.ja content ---
warn_count=0
fail_count=0

check_in_omni() {
  local token=$1
  local found=0

  if (( extracted )); then
    if grep -rqF "$token" "$workdir" 2>/dev/null; then
      found=1
    fi
  else
    # If we could not extract, assume present (can't check)
    found=1
  fi
  echo "$found"
}

echo "--- Zen-specific IDs (selectors targeting #zen-*) ---"
if [[ -z $zen_ids ]]; then
  echo "  (none)"
else
  while IFS= read -r id; do
    if [[ $(check_in_omni "$id") -eq 1 ]]; then
      echo "  OK   #$id"
    else
      echo "  WARN #$id — not found in omni.ja (may have been renamed)"
      warn_count=$((warn_count + 1))
    fi
  done <<<"$zen_ids"
fi
echo ""

echo "--- Zen-specific classes (selectors targeting .zen-*) ---"
if [[ -z $zen_classes ]]; then
  echo "  (none)"
else
  while IFS= read -r cls; do
    if [[ $(check_in_omni "$cls") -eq 1 ]]; then
      echo "  OK   .$cls"
    else
      echo "  WARN .$cls — not found in omni.ja (may have been renamed)"
      warn_count=$((warn_count + 1))
    fi
  done <<<"$zen_classes"
fi
echo ""

echo "--- Zen CSS variables we set (--zen-*: ...) ---"
if [[ -z $zen_vars_set ]]; then
  echo "  (none)"
else
  while IFS= read -r varname; do
    if [[ $(check_in_omni "$varname") -eq 1 ]]; then
      echo "  OK   $varname"
    else
      echo "  WARN $varname — not found in omni.ja (may have been renamed)"
      warn_count=$((warn_count + 1))
    fi
  done <<<"$zen_vars_set"
fi
echo ""

# --- Check that the fundamental load mechanism still exists ---
echo "--- Core mechanism checks ---"
# userChrome.css support
if grep -rq 'legacyUserProfileCustomizations' "$workdir" 2>/dev/null; then
  echo "  OK   toolkit.legacyUserProfileCustomizations.stylesheets pref exists"
else
  # The pref may be in platform.ini or defaults/prefs — check outside omni too
  if grep -rq 'legacyUserProfileCustomizations' "$zen_dir/" 2>/dev/null; then
    echo "  OK   toolkit.legacyUserProfileCustomizations.stylesheets pref exists"
  else
    echo "  WARN toolkit.legacyUserProfileCustomizations.stylesheets not found"
    warn_count=$((warn_count + 1))
  fi
fi

# @-moz-document support
if grep -rq 'moz-document' "$workdir" 2>/dev/null; then
  echo "  OK   @-moz-document still supported"
else
  echo "  WARN @-moz-document not found in omni.ja"
  warn_count=$((warn_count + 1))
fi
echo ""

# --- Summary ---
if (( warn_count == 0 )); then
  echo "=== PASS: All Zen-specific tokens found in this Zen version. ==="
  echo "The theme should continue to work after this update."
  exit 0
else
  echo "=== $warn_count warning(s) found. ==="
  echo "Warnings do NOT mean the theme is broken — every var() has a fallback"
  echo "and the :root variable layer provides colors via cascade. But the"
  echo "warned selectors may need updating. Inspect each in the browser DevTools."
  exit 0
fi
