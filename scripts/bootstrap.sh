#!/usr/bin/env sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

cd "$root_dir"

if ! command -v jj >/dev/null 2>&1; then
  echo "error: jj is required" >&2
  exit 1
fi

jj --version
sh scripts/check.sh
