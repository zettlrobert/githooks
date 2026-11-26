# What runs

## On `pre-commit`

In parallel, on the staged files:

| Files | Tools | Mode |
|---|---|---|
| `*.sh` | shfmt, shellcheck (1) | fix, check |
| `*.py` | ruff format, ruff check | fix, check |
| `*.nix` | nixfmt, deadnix, statix | fix, check |
| `*.yml`, `*.yaml` | prettier, yamllint | fix, check |
| `*.md` | markdownlint-cli2 | fix, check |
| `*.toml` | taplo | fix, check |
| `*.tf`, `*.tfvars` | tofu fmt | fix |
| `Dockerfile`, `Dockerfile.*`, `*.Dockerfile` | hadolint | check |
| `Containerfile`, `Containerfile.*`, `*.Containerfile` | hadolint | check |
| `.forgejo/workflows/*`, `.github/workflows/*` | actionlint | check |
| every staged change | gitleaks | check |
| `*.js`, `*.ts`, `*.json` and friends | biome, opt-in | fix, check |
| `*.css`, `*.scss` | prettier, opt-in | fix |

(1) Plus the optional checks that catch bugs: masked exit codes, `set -e` lost in conditions, `[ ]` in bash,
`case` without a default, unquoted `$?`.

Scripts without an extension match no job: name them `.sh` or add a job. Opt-in jobs: see
[Configure](configure.md#opt-in-jobs).

## On `commit-msg` and `pre-push`

`commit-msg.sh` checks the message. `pre-push.sh` checks the branch name and keeps `junk` and `stash` commits off
`main`. Both print the rule that failed and a valid example. The rules are in [Conventions](conventions.md).

## Commands

| Command | What it does |
|---|---|
| `githooks-install` | links `.githooks` to the package (a nix GC root) and runs `lefthook install`. Idempotent. Rerun after a fresh clone, a new worktree or an update. With `CI` set it only makes the link. |
| `githooks-coverage` | table of the tracked file types: `base`, `opt-in` or `uncovered: <suggested tool>` |
| `githooks-coverage --summary` | one line, for the end of `just lint`. Always exits 0. |

Output in this repo:

```text
extension     files  status
msg              36  uncovered: none known
md                7  base
yml               4  base
yaml              4  base
sh                4  base
json              3  opt-in (if the repo extends jobs/biome.yml)
toml              2  base
nix               1  base
in                1  uncovered: none known
githooks-coverage: 2 uncovered types: msg (36) in (1)
```

## What the package holds

| Part | What it is |
|---|---|
| `bin/lefthook` | the hook runner |
| `bin/` linters | shellcheck, shfmt, ruff, nixfmt, deadnix, statix, yamllint, markdownlint-cli2, taplo, hadolint, actionlint, gitleaks, biome, prettier, tofu |
| `bin/githooks-install`, `bin/githooks-coverage` | the two commands above |
| `share/githooks/lefthook.yml` | the shared base config every repo extends |
| `share/githooks/jobs/biome.yml`, `jobs/prettier.yml` | the opt-in jobs |
| `share/githooks/commit-msg.sh`, `pre-push.sh` | the convention checks |
| `share/githooks/*.yaml`, `*.toml`, `*.json` | the linter rules, one file per tool, from [`configs/`](../configs/) |
| `share/githooks/prettierignore` | files the `yaml` job never formats: `pnpm-lock.yaml` |
| `share/githooks/shellcheckrc`, `editorconfig` | defaults for the editor and the terminal |
