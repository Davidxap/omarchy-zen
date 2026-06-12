#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installed_config="$HOME/.local/lib/zen-auto-style/generated.conf"

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
rm -rf "$HOME/.local/lib/zen-auto-style"
rm -rf "$HOME/.cache/zen-auto-style"

echo "Removed Zen Auto Style native host and Omarchy hook."
echo "Browser CSS imports and the Omarchy template remain in place."
echo "Use the timestamped backups under ~/.local/state/zen-auto-style/backups"
echo "if you want to restore files that existed before installation."
