#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$project_dir/build"
output="$build_dir/zen-auto-style.xpi"

# shellcheck source=project.conf
source "$project_dir/project.conf"

extension_id="${ZEN_AUTO_STYLE_EXTENSION_ID:-$EXTENSION_ID}"
native_host_name="${ZEN_AUTO_STYLE_NATIVE_HOST_NAME:-$NATIVE_HOST_NAME}"

validate_native_host_name() {
  [[ $1 =~ ^[A-Za-z0-9_.]+$ ]]
}

validate_extension_id() {
  [[ $1 =~ ^[A-Za-z0-9._@+{}-]+$ ]]
}

if ! validate_extension_id "$extension_id"; then
  echo "Invalid extension ID: $extension_id" >&2
  echo "Use only letters, numbers, periods, underscores, @, +, -, and braces." >&2
  exit 1
fi

if ! validate_native_host_name "$native_host_name"; then
  echo "Invalid native host name: $native_host_name" >&2
  echo "Use only letters, numbers, underscores, and periods." >&2
  exit 1
fi

mkdir -p "$build_dir"
find "$build_dir" -mindepth 1 ! -name .keep -delete
mkdir -p "$build_dir/api"

sed \
  -e "s|@EXTENSION_ID@|$extension_id|g" \
  "$project_dir/manifest.json.in" \
  >"$build_dir/manifest.json"

sed \
  -e "s|@NATIVE_HOST_NAME@|$native_host_name|g" \
  "$project_dir/background.js.in" \
  >"$build_dir/background.js"

cp -a "$project_dir/api/." "$build_dir/api/"

{
  printf 'EXTENSION_ID=%q\n' "$extension_id"
  printf 'NATIVE_HOST_NAME=%q\n' "$native_host_name"
} >"$build_dir/generated.conf"

cd "$build_dir"
zip -q -r "$output" \
  manifest.json \
  background.js \
  api

echo "Built $output"
echo "Extension ID: $extension_id"
echo "Native host: $native_host_name"
