# githooks

Shared git hooks and linters for my repos, as one nix package: lefthook, the formatters and linters, their
rule files, and the commit-message and branch-name conventions. A repo adopts it with a few committed lines,
gets the same checks on commit, from `just lint` and in CI, and never downloads anything at commit time.

## Lefthook in a nutshell

Lefthook is a git hook runner, not a linter. `lefthook.yml` lists git hooks such as `pre-commit`; under each
hook sit jobs, and a job is a shell command plus a `glob` saying which files it applies to. `lefthook install`
writes small stubs into `.git/hooks`. On `git commit` the stub starts lefthook, which hands each job the
staged files matching its glob, runs the jobs in parallel, and blocks the commit if one fails. `stage_fixed`
makes it re-add files a formatter rewrote, so the fix lands in the commit. `extends` merges another YAML file
into yours: that is how this package's base arrives. `lefthook run pre-commit --all-files` runs the same jobs
by hand; `LEFTHOOK=0 git commit` skips them once.

## Install

### Repo with a flake

```nix
inputs.githooks = {
  url = "github:zettlrobert/githooks";
  inputs.nixpkgs.follows = "nixpkgs";
};
# devShell:
packages = [ inputs.githooks.packages.${system}.default ];
shellHook = ''githooks-install'';
```

Commit this `lefthook.yml`:

```yaml
# Shared hooks from github:zettlrobert/githooks. .githooks is a symlink into the nix store, made by
# githooks-install (run it once per clone and per worktree). Repo-specific jobs below merge with the base.
extends: [".githooks/share/githooks/lefthook.yml"]

pre-commit:
  jobs:
    - name: githooks-present
      run: >-
        test -f .githooks/share/githooks/lefthook.yml
        || { echo "githooks: .githooks is missing or dangling, run githooks-install" >&2; exit 1; }

pre-push:
  jobs:
    - name: githooks-present
      run: >-
        test -f .githooks/share/githooks/lefthook.yml
        || { echo "githooks: .githooks is missing or dangling, run githooks-install" >&2; exit 1; }
```

The `githooks-present` guard exists because lefthook silently ignores a missing `extends` target, so without
it a missing or dangling `.githooks` lets every commit through.

Add to `.gitignore`:

```gitignore
.githooks
lefthook-local.yml
```

Add the `lint` recipe to the `justfile`:

```just
# every hook job on every tracked file, a full secret scan, and the coverage summary
lint:
    lefthook run pre-commit --all-files --no-stage-fixed
    gitleaks dir . -c .githooks/share/githooks/gitleaks.toml
    githooks-coverage --summary
```

Then run `nix develop` once per clone and once per git worktree (`.githooks` lives in the worktree).
`githooks-install` links `.githooks` into the nix store, registered as a GC root so garbage collection keeps
it, and runs `lefthook install`. Every commit from then on runs the hooks, with or without the shell. It
refuses to run outside a git repo or without a `lefthook.yml`. With `CI` set it only makes the symlink: CI
calls `lefthook run` directly and needs no stubs.

### Repo without a flake

```bash
nix profile add github:zettlrobert/githooks # once per machine
cd <repo> && githooks-install               # once per clone and per worktree
```

Same `lefthook.yml`, `.gitignore` and `justfile` lines. Tool versions follow the profile instead of a repo
pin.

## What runs

On `git commit`, in parallel on the staged files:

| Files | Job | Tools | Mode |
|---|---|---|---|
| `*.sh` | shell | shfmt, then shellcheck | fix, check |
| `*.py` | python | ruff format, ruff check --fix | fix, check |
| `*.nix` | nix | nixfmt, deadnix, statix | fix, check, check |
| `*.yml`, `*.yaml` | yaml | yamllint | check |
| `*.md` | markdown | markdownlint-cli2 --fix | fix, check |
| `*.toml` | toml | taplo fmt, taplo check | fix, check |
| `Dockerfile`, `Dockerfile.*`, `*.Dockerfile` in any directory | dockerfile | hadolint, blocks at warning level, info rules print only | check |
| `.forgejo/workflows/*.{yml,yaml}`, `.github/workflows/*.{yml,yaml}` | actions | actionlint | check |
| every staged change | secrets | gitleaks, verbose | check |
| `*.{js,mjs,cjs,ts,tsx,json,jsonc}` | biome, opt-in only | biome check --write | fix, check |

On the commit message: the `conventions` job (`commit-msg.sh`). On `git push`: the `branch-and-junk-guard`
job (`pre-push.sh`). Both are described under [Conventions](#conventions).

A job whose glob matches no staged file is skipped, so a repo never declares which linters it needs. The base
sets `assert_lefthook_installed: true`, so a missing lefthook fails the commit instead of passing it.

On demand: `just lint` in a consuming repo runs `lefthook run pre-commit --all-files --no-stage-fixed`, then
`gitleaks dir .`, then `githooks-coverage --summary`. Formatters fix files in the working tree;
`--no-stage-fixed` keeps the index untouched. CI runs the same recipe and then `git diff --exit-code HEAD`,
so a file a formatter would change fails the run:

```bash
nix develop --command just lint && git diff --exit-code HEAD
```

### Coverage

Lefthook ignores files that match no glob, so nothing warns when a repo gains a file type without a job.
`githooks-coverage` lists the tracked extensions with file counts and a status; `githooks-coverage --summary`
prints one line, which `just lint` shows at the end. It is advisory and always exits 0.

| Status | Meaning |
|---|---|
| `base` | a job in the base `lefthook.yml` covers it |
| `opt-in` | covered only if the repo extends `jobs/biome.yml` |
| `uncovered: <tool>` | no job; names the standard tool when one is known |

Images, archives, lock files and plain text are skipped. Known gap: scripts without an extension (for example
`bin/foo`) are not listed by the report and not matched by the `*.sh` glob. A repo with such scripts adds
its own shellcheck job for them or names them `.sh`.

## Conventions

Commit subject: `type(scope)!: description`, scope and `!` optional. The description starts with a lowercase
letter or digit, has at least 5 characters and no trailing period; the whole subject is at most 120
characters. Types: build chore ci devops docs feat fix junk perf refactor revert stash style test.

| Valid | Invalid | Why |
|---|---|---|
| `feat(caddy): add the paperless route` | `Feat: Add route` | type and description are lowercase |
| `fix: resolve the dns lookup (pi-hole)` | `fix: resolve dns.` | no trailing period |
| `refactor!: drop the v1 api` | `update: drop v1` | unknown type |

`junk:` is dirty work on a branch that gets squashed or rebased away before merge. `stash:` is a WIP
snapshot committed instead of `git stash`, so it survives branch switches and can be pushed to a backup
branch. The pre-push hook refuses both on `main` and `master`.

Any line attributing an AI tool is rejected: `Co-Authored-By` naming one, `noreply@anthropic.com`,
`Generated with ...` naming one, `Claude-Session:`, the robot emoji. Bare product names stay legal. Comment
lines and everything below a `git commit -v` scissors line are ignored.

Git's own subjects pass: `Merge ...`, `Revert "..."`, `Reapply "..."`, `fixup!`, `squash!`, `amend!`.
Commands that never run the commit-msg hook: `git revert` and `git cherry-pick` without an editor,
`git stash`, server-side commits.

Branch: `<type>/<optional number>/<slug>` with the commit types plus `renovate` and `wip`, for example
`feat/123/add-thing` or `devops/lint-flake`. `main` and `master` are always allowed. The pre-push hook judges
the remote ref being pushed, not the checked-out branch, and ignores tags and deletions.

## Configure

Every linter's rules live in this package next to the job that references them (`configs/`, installed to
`.githooks/share/githooks/`). A repo that wants different rules for one linter writes its own job under the
`extends` line of its `lefthook.yml` and disables the shared one by name:

```yaml
extends: [".githooks/share/githooks/lefthook.yml"]

pre-commit:
  jobs:
    - name: markdown
      skip: true
    - name: markdown-strict
      glob: "*.md"
      run: markdownlint-cli2 --fix --config .markdownlint.yaml {staged_files}
      stage_fixed: true
```

Repo-specific jobs go in the same place and merge with the base. Keep the `githooks-present` guard jobs.

Opt in to biome:

```yaml
extends: [".githooks/share/githooks/lefthook.yml", ".githooks/share/githooks/jobs/biome.yml"]
```

## Bump

In a flake repo: `nix flake update githooks`, then `nix develop`, which reruns `githooks-install`: it relinks
`.githooks` and re-renders the stubs. Global: `nix profile upgrade githooks`, then `githooks-install` in each
repo that uses the profile. Moving the source to the Forgejo instance later is one line:
`url = "git+https://forgejo.<domain>/zettlrobert/githooks?ref=main"`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| commits go through without any hook output | stubs not installed: run `githooks-install` (or `nix develop`) in the repo |
| `githooks: .githooks is missing or dangling, run githooks-install` | fresh clone, new worktree or wiped store: run `githooks-install` |
| old tool versions or store path errors after a bump | `.githooks` or the stubs are stale: run `githooks-install` |
| hooks run in the terminal but not from a GUI git client | the stub sources `.githooks/share/githooks/lefthookrc` to find the tools, so `.githooks` is stale: run `githooks-install` |
| a job fails in CI but not locally | CI runs `--all-files`; run `just lint` locally, it fixes files in place |
| `githooks-install: no lefthook.yml` | commit the `lefthook.yml` from [Install](#install) first |
| need to commit anyway | `LEFTHOOK=0 git commit ...`, once and consciously |

## Development

```bash
just test  # fixture tests for the hook scripts, no build
just check # nix flake check: fixtures plus the end-to-end test in the sandbox
just build # the package into ./result
just lint  # this repo's own hooks on every file, plus shellcheck and shfmt on the bin/ scripts
```

This repo's `just lint` lints `bin/*` explicitly because those scripts have no extension: the coverage gap
above, applied to itself.

Layout: `flake.nix` (package, checks, dev shell), `lefthook.yml` (the base), `jobs/` (opt-in jobs),
`configs/` (linter rules), `hooks/` (commit-msg and pre-push), `bin/` (`githooks-install`,
`githooks-coverage`), `tests/` (fixtures and `integration.sh`, whose consumer `lefthook.yml` is the canonical
template).

Design record with the decisions and rejected alternatives: [`docs/design.md`](docs/design.md).
