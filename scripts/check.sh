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

required_vars="
JJ_ALIAS_NAME
JJ_ALIAS_CONFIG_FILE
"

for var_name in $required_vars; do
  eval "value=\${$var_name:-}"
  if [ -z "$value" ]; then
    echo "error: missing required value in .envrc: $var_name" >&2
    exit 1
  fi
done

case "$JJ_ALIAS_NAME" in
  *[!a-z0-9-]* | "" | -* | *-)
    echo "error: JJ_ALIAS_NAME must be lower-kebab-case" >&2
    echo "received: $JJ_ALIAS_NAME" >&2
    exit 1
    ;;
esac

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

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT HUP TERM

install_support_file "$tmp_dir/config"

alias_value=$(
  XDG_CONFIG_HOME="$tmp_dir/config" jj --config-file "$alias_config_file" config get "aliases.$JJ_ALIAS_NAME"
)
XDG_CONFIG_HOME="$tmp_dir/config" jj config set --user "aliases.$JJ_ALIAS_NAME" "$alias_value"
XDG_CONFIG_HOME="$tmp_dir/config" jj config get "aliases.$JJ_ALIAS_NAME" >/dev/null

if [ -n "${JJ_ALIAS_SMOKE_ARGS:-}" ]; then
  # Intentionally allow word splitting so simple smoke args such as "--smoke" work.
  # shellcheck disable=SC2086
  XDG_CONFIG_HOME="$tmp_dir/config" jj "$JJ_ALIAS_NAME" $JJ_ALIAS_SMOKE_ARGS >/dev/null
fi

echo "Alias is valid."
