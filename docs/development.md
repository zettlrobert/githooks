# Development

Work on this repo inside `nix develop`.

| Recipe | Runs |
|---|---|
| `just test` | the hook fixtures and the config drift checks (fast, no build) |
| `just check` | `nix flake check`: the same tests plus an end-to-end consumer repo, in the sandbox |
| `just lint` | this repo's own hooks on every file, plus shellcheck and shfmt on the extensionless scripts |
| `just build` | the package into `./result` |

## Layout

```text
bin/       githooks-install (nix substitutes the package path), githooks-coverage
configs/   one rule file per linter, shipped as share/githooks/*
hooks/     commit-msg.sh, pre-push.sh
jobs/      opt-in job files
tests/     run.sh (fixtures, drift checks), integration.sh (end-to-end), commit-msg/{pass,fail}/*.msg
docs/      the topic docs linked from the README, design.md for decisions
```

## CI

`.forgejo/workflows/check.yml` runs `nix flake check` and `just lint` on every pull request and every push to
`main`. Renovate keeps `flake.lock` and the workflow actions current, see [Update](update.md#this-repo).

Decisions and rejected alternatives live in [design.md](design.md).
