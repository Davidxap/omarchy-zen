#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

required_commands=(awk grep install mktemp sed)
missing_commands=()

for command in "${required_commands[@]}"; do
  command -v "$command" >/dev/null 2>&1 || missing_commands+=("$command")
done

if (( ${#missing_commands[@]} )); then
  echo "Missing commands: ${missing_commands[*]}" >&2
  exit 1
fi

bash -n \
  "$project_dir/check.sh" \
  "$project_dir/install.sh" \
  "$project_dir/uninstall.sh" \
  "$project_dir/omarchy/theme-set-hook"

if rg -n 'YOUR-USER|TODO|FIXME|youremail' \
  "$project_dir" \
  --glob '!legacy/**' \
  --glob '!check.sh'; then
  echo "Release placeholders or personal identifiers remain." >&2
  exit 1
fi

echo "Release checks passed."
