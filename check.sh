#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

required_commands=(awk grep install jq mktemp python3 rg sed unzip zip)
missing_commands=()

for command in "${required_commands[@]}"; do
  command -v "$command" >/dev/null 2>&1 || missing_commands+=("$command")
done

if (( ${#missing_commands[@]} )); then
  echo "Missing commands: ${missing_commands[*]}" >&2
  exit 1
fi

bash -n \
  "$project_dir/build.sh" \
  "$project_dir/check.sh" \
  "$project_dir/install.sh" \
  "$project_dir/uninstall.sh" \
  "$project_dir/omarchy/theme-set-hook"

python3 -m py_compile "$project_dir/native/zen-auto-style-host.py"
rm -rf "$project_dir/native/__pycache__"

node_check="${NODE:-node}"
if command -v "$node_check" >/dev/null 2>&1; then
  "$node_check" --check <"$project_dir/background.js.in"
  "$node_check" --check "$project_dir/api/style-reloader/implementation.js"
fi

"$project_dir/build.sh" >/dev/null

jq empty \
  "$project_dir/build/manifest.json" \
  "$project_dir/api/style-reloader/schema.json"

unzip -t "$project_dir/build/zen-auto-style.xpi" >/dev/null

if rg -n 'YOUR-USER|TODO|FIXME|youremail' \
  "$project_dir" \
  --glob '!build/**' \
  --glob '!check.sh'; then
  echo "Release placeholders or personal identifiers remain." >&2
  exit 1
fi

echo "Release checks passed."
