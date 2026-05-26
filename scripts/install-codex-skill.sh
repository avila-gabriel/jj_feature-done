#!/usr/bin/env sh
set -eu

skill_name_input="${1:-}"
source_dir="${2:-codex_skill}"
skills_dir="${CODEX_SKILLS_DIR:-$HOME/.agents/skills}"

usage() {
  echo "Usage:"
  echo "  sh scripts/install-codex-skill.sh <skill-name> [skill-dir]"
}

render_template() {
  source_file="$1"
  target_file="$2"

  awk \
    -v skill_name="$SKILL_NAME" \
    -v skill_description="$SKILL_DESCRIPTION" \
    -v skill_purpose="$SKILL_PURPOSE" \
    -v tool_description="$TOOL_DESCRIPTION" \
    -v jj_alias_name="$JJ_ALIAS_NAME" \
    -v jj_alias_toml="$JJ_ALIAS_TOML" \
    -v critical_constraint="${CRITICAL_CONSTRAINT:-}" \
    '
    function replace_all(value, needle, replacement, output, index_) {
      output = ""
      while ((index_ = index(value, needle)) > 0) {
        output = output substr(value, 1, index_ - 1) replacement
        value = substr(value, index_ + length(needle))
      }
      return output value
    }

    {
      line = $0
      line = replace_all(line, "{{SKILL_NAME}}", skill_name)
      line = replace_all(line, "{{SKILL_DESCRIPTION}}", skill_description)
      line = replace_all(line, "{{SKILL_PURPOSE}}", skill_purpose)
      line = replace_all(line, "{{TOOL_DESCRIPTION}}", tool_description)
      line = replace_all(line, "{{JJ_ALIAS_NAME}}", jj_alias_name)
      line = replace_all(line, "{{JJ_ALIAS_TOML}}", jj_alias_toml)
      line = replace_all(line, "{{CRITICAL_CONSTRAINT}}", critical_constraint)
      print line
    }
    ' "$source_file" > "$target_file"
}

if [ -z "$skill_name_input" ]; then
  usage
  exit 1
fi

slug=$(
  printf '%s' "$skill_name_input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
)

if [ -z "$slug" ]; then
  echo "error: invalid skill name: $skill_name_input" >&2
  exit 1
fi

if [ ! -f "$source_dir/SKILL.md.template" ]; then
  echo "error: missing skill source: $source_dir/SKILL.md.template" >&2
  exit 1
fi

SKILL_NAME="${SKILL_NAME:-$slug}"
SKILL_DESCRIPTION="${SKILL_DESCRIPTION:-}"
SKILL_PURPOSE="${SKILL_PURPOSE:-}"
TOOL_DESCRIPTION="${TOOL_DESCRIPTION:-}"
JJ_ALIAS_NAME="${JJ_ALIAS_NAME:-}"
JJ_ALIAS_TOML="${JJ_ALIAS_TOML:-}"
CRITICAL_CONSTRAINT="${CRITICAL_CONSTRAINT:-}"

for required in SKILL_DESCRIPTION SKILL_PURPOSE TOOL_DESCRIPTION JJ_ALIAS_NAME JJ_ALIAS_TOML; do
  eval "value=\${$required}"
  if [ -z "$value" ]; then
    echo "error: missing $required" >&2
    exit 1
  fi
done

mkdir -p "$skills_dir"

target_dir="$skills_dir/$slug"
tmp_dir="$skills_dir/.$slug.tmp.$$"

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT INT HUP TERM

rm -rf "$tmp_dir"
mkdir -p "$tmp_dir"
cp -R "$source_dir"/. "$tmp_dir"/

find "$tmp_dir" -type f -name '*.template' | while IFS= read -r template_file; do
  target_file=${template_file%.template}
  render_template "$template_file" "$target_file"
  rm -f "$template_file"
done

frontmatter_name=$(
  sed -n 's/^name:[[:space:]]*//p' "$tmp_dir/SKILL.md" \
    | head -n 1 \
    | tr -d '"'
)

if [ "$frontmatter_name" != "$slug" ]; then
  echo "error: skill name mismatch" >&2
  echo "  expected: name: $slug" >&2
  echo "  found:    name: $frontmatter_name" >&2
  rm -rf "$tmp_dir"
  exit 1
fi

if [ -d "$target_dir" ]; then
  action="Updated"
else
  action="Created"
fi

rm -rf "$target_dir"
mv "$tmp_dir" "$target_dir"
trap - EXIT INT HUP TERM

echo "$action skill: $target_dir/SKILL.md"
