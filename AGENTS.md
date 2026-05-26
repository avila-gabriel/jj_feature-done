# Project Instructions

Build this as a `jj` command alias.

## Workflow

- Run `task bootstrap` after cloning to verify local `jj` tooling and alias configuration.
- Use `.envrc` as the customization surface for the alias name, smoke args, and support file metadata.
- Keep the alias TOML block in the file referenced by `JJ_ALIAS_CONFIG_FILE`, for example:

  ```toml
  [aliases]
  my-jj-alias = ["log", "-r", "@"]
  ```
- Prefer ordinary `jj` aliases over `jj util exec` scripts unless the workflow truly needs shell behavior.

## Verification

Run after every change:

```sh
task done
```

`task done` uses a temporary `XDG_CONFIG_HOME`, so it validates the alias without touching your real jj user config.
