#!/usr/bin/env sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
env_file="$root_dir/.envrc"

if [ ! -f "$env_file" ]; then
  echo "error: missing .envrc" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

JJ_ALIAS_CONFIG_FILE="${JJ_ALIAS_CONFIG_FILE:-jj-alias.toml}"

if [ -z "${JJ_ALIAS_NAME:-}" ] || [ -z "${JJ_ALIAS_CONFIG_FILE:-}" ]; then
  echo "error: JJ_ALIAS_NAME and JJ_ALIAS_CONFIG_FILE are required in .envrc" >&2
  exit 1
fi

case "$JJ_ALIAS_CONFIG_FILE" in
  /*)
    alias_config_file="$JJ_ALIAS_CONFIG_FILE"
    ;;
  *)
    alias_config_file="$root_dir/$JJ_ALIAS_CONFIG_FILE"
    ;;
esac

if [ ! -f "$alias_config_file" ]; then
  echo "error: missing jj alias config file: $JJ_ALIAS_CONFIG_FILE" >&2
  exit 1
fi

install_support_file() {
  config_home="$1"

  if [ -z "${JJ_ALIAS_SUPPORT_FILE:-}" ]; then
    return
  fi

  case "$JJ_ALIAS_SUPPORT_FILE" in
    /*)
      support_source="$JJ_ALIAS_SUPPORT_FILE"
      ;;
    *)
      support_source="$root_dir/$JJ_ALIAS_SUPPORT_FILE"
      ;;
  esac

  if [ ! -f "$support_source" ]; then
    echo "error: missing jj alias support file: $JJ_ALIAS_SUPPORT_FILE" >&2
    exit 1
  fi

  support_target="${JJ_ALIAS_SUPPORT_TARGET:-$(basename "$support_source")}"

  case "$support_target" in
    "" | */*)
      echo "error: JJ_ALIAS_SUPPORT_TARGET must be a file name" >&2
      exit 1
      ;;
  esac

  mkdir -p "$config_home/jj"
  cp "$support_source" "$config_home/jj/$support_target"
  chmod +x "$config_home/jj/$support_target"
}

install_support_file "${XDG_CONFIG_HOME:-$HOME/.config}"

alias_value=$(jj --config-file "$alias_config_file" config get "aliases.$JJ_ALIAS_NAME")
jj config set --user "aliases.$JJ_ALIAS_NAME" "$alias_value"
jj config get "aliases.$JJ_ALIAS_NAME" >/dev/null

echo "Installed jj alias: jj $JJ_ALIAS_NAME <codex-bin>"
