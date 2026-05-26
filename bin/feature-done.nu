#!/usr/bin/env nu

def jj-lines [args: list<string>] {
  let result = (run-external jj ...$args | complete)

  if $result.exit_code != 0 {
    print --stderr $result.stderr
    error make { msg: $"jj command failed: jj ($args | str join ' ')" }
  }

  $result.stdout | lines
}

def jj-text [args: list<string>] {
  let result = (run-external jj ...$args | complete)

  if $result.exit_code != 0 {
    print --stderr $result.stderr
    error make { msg: $"jj command failed: jj ($args | str join ' ')" }
  }

  $result.stdout
}

def bounded-text [
  label: string,
  max_chars: int,
  max_lines: int,
] {
  let text = $in
  let original_lines = ($text | lines | length)
  let original_chars = ($text | str length)

  let line_limited = if $original_lines > $max_lines {
    $text | lines | first $max_lines | str join "\n"
  } else {
    $text
  }

  let line_limited_chars = ($line_limited | str length)
  let char_limited = if $line_limited_chars > $max_chars {
    let end = ($max_chars - 1)
    $line_limited | str substring 0..$end
  } else {
    $line_limited
  }

  if $original_lines > $max_lines or $line_limited_chars > $max_chars {
    let kept_lines = ($char_limited | lines | length)
    let kept_chars = ($char_limited | str length)

    [
      $char_limited
      ""
      $"[($label) truncated: original had ($original_lines) lines, ($original_chars) characters; kept ($kept_lines) lines, ($kept_chars) characters.]"
    ] | str join "\n"
  } else {
    $text
  }
}

def bookmark-revset [target: string] {
  $"\(($target)\) & bookmarks\(\)"
}

def trunk-bookmark-names [] {
  ["main" "master" "trunk"]
}

def bookmark-exact-pattern [name: string] {
  ["exact:" $name] | str join ""
}

def bookmark-exact-revset [name: string] {
  ['bookmarks(exact:"' $name '")'] | str join ""
}

def stack-revset [base: string] {
  $"\(($base)\)..@"
}

def dest-revset [stack: string] {
  $"exactly\(roots\(($stack)\), 1\)"
}

def sources-revset [dest: string] {
  $"\(($dest)::@\) ~ \(($dest)\)"
}

def bookmark-names-at [target: string] {
  jj-text [
    --color never
    --no-pager
    log
    --no-graph
    -r (bookmark-revset $target)
    -T 'local_bookmarks.map(|b| b.name()).join(", ") ++ "\n"'
  ] | str trim
}

def local-bookmark-target [name: string] {
  let result = (
    run-external jj
      bookmark
      list
      (bookmark-exact-pattern $name)
      "--color" never
      "-T" 'name ++ " " ++ normal_target.commit_id().short() ++ "\n"'
    | complete
  )

  if $result.exit_code != 0 {
    print --stderr $result.stderr
    error make { msg: $"jj command failed: jj bookmark list (bookmark-exact-pattern $name)" }
  }

  let lines = (
    $result.stdout
    | lines
    | where {|line| ($line | str trim) != "" }
  )

  if ($lines | length) == 0 {
    return null
  }

  if ($lines | length) > 1 {
    error make { msg: $"Local bookmark ($name) matched multiple targets" }
  }

  let fields = (($lines | first) | split row " ")

  if ($fields | length) != 2 or ($fields | get 0) != $name {
    error make { msg: $"Unexpected bookmark list output for ($name): ($lines | first)" }
  }

  {
    name: $name,
    revset: (bookmark-exact-revset $name),
    commit: ($fields | get 1),
  }
}

def resolve-base [] {
  for name in (trunk-bookmark-names) {
    let target = (local-bookmark-target $name)

    if $target != null {
      return $target
    }
  }

  error make {
    msg: "No local trunk bookmark found; expected one of: main, master, trunk"
  }
}

def codex-command-name [candidate?: string] {
  if $candidate == null or ($candidate | str trim) == "" {
    error make {
      msg: "Usage: jj feature-done <codex-bin>\nExample: jj feature-done codex-rafa"
    }
  }

  let command = ($candidate | str trim)

  if not ($command =~ '^[A-Za-z0-9_./+-]+$') {
    error make {
      msg: $"Codex command must be a command name or path without shell syntax: ($command)"
    }
  }

  $command
}

def simple-shell-token [label: string, value: string] {
  let token = ($value | str trim)

  if $token == "" {
    error make { msg: $"($label) cannot be empty" }
  }

  if not ($token =~ '^[A-Za-z0-9_./:+-]+$') {
    error make {
      msg: $"($label) must be a simple shell token without spaces or shell syntax: ($token)"
    }
  }

  $token
}

def env-or-default [name: string, fallback: string] {
  let value = ($env | get --optional $name)

  if $value == null or (($value | into string | str trim) == "") {
    $fallback
  } else {
    $value | into string
  }
}

def codex-model [] {
  simple-shell-token "Codex model" (env-or-default "FEATURE_DONE_CODEX_MODEL" "gpt-5.5")
}

def codex-reasoning-effort [] {
  simple-shell-token "Codex reasoning effort" (env-or-default "FEATURE_DONE_CODEX_REASONING_EFFORT" "low")
}

def codex-reasoning-summary [] {
  simple-shell-token "Codex reasoning summary" (env-or-default "FEATURE_DONE_CODEX_REASONING_SUMMARY" "none")
}

def codex-exec-args [] {
  [
    "exec"
    "--ephemeral"
    "--sandbox"
    "read-only"
    "--model"
    (codex-model)
    "-c"
    $"model_reasoning_effort=(codex-reasoning-effort)"
    "-c"
    $"model_reasoning_summary=(codex-reasoning-summary)"
    "-"
  ]
}

def codex-version-args [] {
  let args = (codex-exec-args)
  ($args | first (($args | length) - 1)) ++ ["--version"]
}

def interactive-shell [] {
  let shell = ($env.SHELL? | default "/bin/sh" | str trim)

  if $shell == "" {
    "/bin/sh"
  } else {
    $shell
  }
}

def codex-shell-command [command: string, args: list<string>] {
  ([$command] ++ $args) | str join " "
}

def smoke [codex_bin?: string] {
  let sample = (bookmark-revset "trunk()")

  if $sample != "(trunk()) & bookmarks()" {
    error make { msg: $"Unexpected bookmark revset: ($sample)" }
  }

  jj-lines [
    --color never
    --no-pager
    log
    --no-graph
    -r $sample
    -T 'commit_id ++ "\n"'
  ] | ignore

  let base_info = (resolve-base)
  let base = $base_info.revset
  let base_count = (
    jj-lines [--color never --no-pager log --no-graph -r $base -T 'commit_id ++ "\n"']
    | length
  )

  if $base_count != 1 {
    error make { msg: $"Base smoke revset must resolve to exactly one commit; ($base) resolved to ($base_count)" }
  }

  if (bookmark-names-at $base) == "" {
    error make { msg: $"Base smoke revset has no local bookmark: ($base)" }
  }

  let stack = (stack-revset $base)

  if (bookmark-names-at $stack) != "" {
    error make { msg: $"Stack smoke revset includes local bookmarks: ($stack)" }
  }

  let dest = (dest-revset $stack)
  let dest_count = (
    jj-lines [--color never --no-pager log --no-graph -r $dest -T 'commit_id ++ "\n"']
    | length
  )

  if $dest_count != 1 {
    error make { msg: $"Destination smoke revset must resolve to exactly one commit; ($dest) resolved to ($dest_count)" }
  }

  let sources = (sources-revset $dest)
  let root_source_count = (
    jj-lines [
      --color never
      --no-pager
      log
      --no-graph
      -r $"root\(\) & \(($sources)\)"
      -T 'commit_id ++ "\n"'
    ] | length
  )

  if $root_source_count != 0 {
    error make { msg: $"Source smoke revset includes root: ($sources)" }
  }

  if $codex_bin != null {
    let codex_command = (codex-command-name $codex_bin)
    let codex_result = (
      run-external (interactive-shell) "-ic" (
        codex-shell-command $codex_command (codex-version-args)
      )
      | complete
    )

    if $codex_result.exit_code != 0 {
      print --stderr $codex_result.stderr
      error make { msg: $"Codex command smoke failed: ($codex_command)" }
    }
  }
}

def main [
  codex_bin?: string
  --smoke
] {
  if $smoke {
    smoke $codex_bin
    return
  }

  let codex_command = (codex-command-name $codex_bin)

  let base_info = (resolve-base)
  let base = $base_info.revset
  let base_bookmark = $base_info.name
  let stack = (stack-revset $base)
  let dest = (dest-revset $stack)
  let sources = (sources-revset $dest)
  let human_files = 'all() ~ root-glob:"**/generated/**"'

  let base_count = (
    jj-lines [--color never --no-pager log --no-graph -r $base -T 'commit_id ++ "\n"']
    | length
  )

  if $base_count != 1 {
    error make { msg: $"Base revset must resolve to exactly one commit; ($base) resolved to ($base_count)" }
  }

  let base_bookmarks = (bookmark-names-at $base)

  if $base_bookmarks == "" {
    error make {
      msg: $"No local bookmark points at base ($base); refusing to rewrite history because there is no local trunk bookmark to move"
    }
  }

  let stack_count = (
    jj-lines [--color never --no-pager log --no-graph -r $stack -T 'commit_id ++ "\n"']
    | length
  )

  if $stack_count == 0 {
    error make { msg: $"No feature changes found above ($base)" }
  }

  let stack_bookmarks = (
    jj-text [
      --color never
      --no-pager
      log
      --no-graph
      -r (bookmark-revset $stack)
      -T 'separate(" ", commit_id.short(), local_bookmarks.map(|b| b.name()).join(", ")) ++ "\n"'
    ] | str trim
  )

  if $stack_bookmarks != "" {
    error make {
      msg: $"Local bookmarks are inside the computed feature stack ($stack):\n($stack_bookmarks)"
    }
  }

  let source_count = (
    jj-lines [--color never --no-pager log --no-graph -r $sources -T 'commit_id ++ "\n"']
    | length
  )

  let stack_log = (
    jj-text [--color never --no-pager log --no-graph -r $stack]
    | bounded-text "stack log" 30_000 600
  )

  let changed_files = (
    jj-text [--color never --no-pager diff --from $base --to @ --summary $human_files]
    | bounded-text "changed file summary" 20_000 800
  )

  let diff_stat = (
    jj-text [--color never --no-pager diff --from $base --to @ --stat $human_files]
    | bounded-text "diff stat" 12_000 400
  )

  let net_diff = (
    jj-text [--color never --no-pager diff --from $base --to @ --context 2 $human_files]
    | bounded-text "net diff excerpt" 45_000 1600
  )

  let prompt = ([
    "You are preparing the final commit message for a completed feature."
    ""
    "The repository uses Jujutsu in solo-dev style. There may not be a branch."
    "The developer has a stack of changes above trunk and wants the end result"
    "to look like a squash-merge commit: one polished commit on top of trunk."
    ""
    $"Base/trunk revset: ($base)"
    $"Feature stack revset: ($stack)"
    $"Destination commit, first change above trunk: ($dest)"
    $"Source commits to merge into the destination: ($sources)"
    ""
    "Task:"
    "Write the final jj change description for the single completed feature commit."
    ""
    "Use the existing change descriptions as the primary source of intent. They may"
    "contain goal, plan, deliverables, implementation notes, migrations, and WIP"
    "details. Merge the useful parts into one final description."
    ""
    "Rules:"
    "- Output ONLY the final jj change description."
    "- No markdown fences."
    "- No explanation outside the commit message."
    "- First line <= 72 characters."
    "- Use imperative mood."
    "- Body may use concise bullets if useful."
    "- Preserve the feature goal, final behavior, deliverables, migrations, and important risks."
    "- Drop WIP wording, temporary planning notes, duplicated bullets, and generated-file churn."
    "- Do not mention jj, squash, branch, stack, or Codex unless relevant to the feature itself."
    ""
    "Current stack log and descriptions:"
    $stack_log
    ""
    "Changed files, excluding generated paths:"
    $changed_files
    ""
    "Diff stat, excluding generated paths:"
    $diff_stat
    ""
    "Net diff excerpt, excluding generated paths:"
    $net_diff
  ] | str join "\n")

  print $"Using Codex command: ($codex_command)"
  print $"Using Codex model: (codex-model), effort: (codex-reasoning-effort)"

  let codex_result = (
    $prompt
    | run-external (interactive-shell) "-ic" (codex-shell-command $codex_command (codex-exec-args))
    | complete
  )

  if $codex_result.exit_code != 0 {
    print --stderr $codex_result.stderr
    error make { msg: "Codex failed to generate the final commit message" }
  }

  let msg = (
    $codex_result.stdout
    | lines
    | where {|line|
      not (($line =~ '^```[A-Za-z0-9_-]*$') or ($line == '```'))
    }
    | str join "\n"
    | str trim
  )

  if $msg == "" {
    error make { msg: "Codex produced an empty message; aborting" }
  }

  print ""
  print "Generated final message:"
  print ""
  print $msg
  print ""

  if $source_count == 0 {
    print $"Only one change above ($base); updating its description."
    jj describe -r $dest -m $msg
  } else {
    print $"Squashing ($source_count) later changes into the first change above ($base)."
    jj squash --from $sources --into $dest -m $msg
  }

  print $"Moving local bookmark ($base_bookmark) currently at ($base) to the final feature commit."
  jj bookmark move (bookmark-exact-pattern $base_bookmark) --from $base --to $dest

  print ""
  print "Final stack:"
  jj log -r $"\(($dest)\)|@|\(($base)\)" --no-pager
}
