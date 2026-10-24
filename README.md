# githooks

Shared git hooks for my repos, as one nix package: [lefthook](https://lefthook.dev), the formatters and
linters, their rules, and the commit and branch conventions. The same checks run on commit, in `just lint` and in
CI, with tool versions pinned by the repo's `flake.lock`. Nothing is downloaded at commit time.

Needs nix with flakes. Builds for `x86_64-linux`, `aarch64-linux` and `aarch64-darwin`.

## What you get

One package (`packages.<system>.default`), used from a dev shell or a nix profile:

| Part                                         | What it is                                                                  |
| -------------------------------------------- | --------------------------------------------------------------------------- |
| `bin/lefthook`                               | the hook runner                                                             |
| `bin/` linters                               | shellcheck, shfmt, ruff, nixfmt, deadnix, statix, yamllint, markdownlint-cli2, taplo, hadolint, actionlint, gitleaks, biome |
| `bin/githooks-install`                       | links a repo to this package and installs the git hook stubs               |
| `bin/githooks-coverage`                      | lists the repo's file types and flags those no job checks                   |
| `share/githooks/lefthook.yml`                | the shared base config every repo extends                                   |
| `share/githooks/jobs/biome.yml`              | opt-in JavaScript, TypeScript and JSON job                                  |
| `share/githooks/commit-msg.sh`, `pre-push.sh` | the commit message and branch convention checks                            |
| `share/githooks/*.yaml`, `*.toml`, `*.json`  | the linter rules, one file per tool, from [`configs/`](configs/)            |
| `share/githooks/shellcheckrc`, `editorconfig` | defaults for the editor and the terminal                                   |

## Lefthook in a minute

Lefthook is a runner, not a linter. `lefthook.yml` lists git hooks (`pre-commit`, `commit-msg`, `pre-push`) and
their jobs. A job is a command plus a `glob`: on commit it receives the staged files that match, and a job whose
glob matches nothing is skipped. `lefthook install` writes small stubs into `.git/hooks` that call lefthook.
Jobs with `stage_fixed: true` are formatters: they rewrite the files and re-stage them. Any other failing job
blocks the commit. `extends` merges another config into the repo's own, and jobs with the same `name` merge.

```bash
lefthook run pre-commit --all-files   # run the commit checks on every tracked file
LEFTHOOK=0 git commit ...             # skip the hooks once
```

## Adopt it in a repo

1. Add the flake input and the package to the dev shell:

   ```nix
   inputs.githooks = {
     url = "github:zettlrobert/githooks";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   # in mkShell
   packages = [ inputs.githooks.packages.${system}.default ];
   shellHook = "githooks-install";
   ```

2. Commit `lefthook.yml`. The guard jobs make a missing `.githooks` fail loudly, because lefthook silently
   skips a missing `extends` target:

   ```yaml
   extends: ['.githooks/share/githooks/lefthook.yml']

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

3. Add `.githooks` and `lefthook-local.yml` to `.gitignore`, and copy the editor defaults:
   `cp .githooks/share/githooks/editorconfig .editorconfig` (lefthook cannot extend it, so each repo commits a copy).

4. Run `nix develop` once per clone and per worktree. From then on every commit runs the hooks.

Without a flake: `nix profile add github:zettlrobert/githooks` once, then `githooks-install` in the repo.

Optional `justfile` recipe, also what CI runs inside `nix develop` (followed by `git diff --exit-code HEAD`, so
an unformatted file fails the run):

```just
lint:
    lefthook run pre-commit --all-files --no-stage-fixed
    gitleaks dir . -c .githooks/share/githooks/gitleaks.toml
    githooks-coverage --summary
```

## What runs

On `pre-commit`, in parallel, on the staged files:

| Files                                         | Tools                   | Mode       |
| --------------------------------------------- | ----------------------- | ---------- |
| `*.sh`                                        | shfmt, shellcheck (1)   | fix, check |
| `*.py`                                        | ruff format, ruff check | fix, check |
| `*.nix`                                       | nixfmt, deadnix, statix | fix, check |
| `*.yml`, `*.yaml`                             | yamllint                | check      |
| `*.md`                                        | markdownlint-cli2       | fix, check |
| `*.toml`                                      | taplo                   | fix, check |
| `Dockerfile`, `Dockerfile.*`, `*.Dockerfile`  | hadolint                | check      |
| `.forgejo/workflows/*`, `.github/workflows/*` | actionlint              | check      |
| every staged change                           | gitleaks                | check      |
| `*.js`, `*.ts`, `*.json` and friends          | biome, opt-in           | fix, check |

(1) Plus the optional checks that catch bugs: masked exit codes, `set -e` lost in conditions, `[ ]` in bash,
`case` without a default, unquoted `$?`.

On `commit-msg`, `commit-msg.sh` checks the message. On `pre-push`, `pre-push.sh` checks the branch name and keeps
`junk` and `stash` commits off `main`. Both print the rule that failed and a valid example. Scripts without an
extension are not matched by any job: name them `.sh` or add a job.

## Commands

| Command                       | What it does                                                                       |
| ----------------------------- | ---------------------------------------------------------------------------------- |
| `githooks-install`            | links `.githooks` to the package (a nix GC root) and runs `lefthook install`. Idempotent. Rerun after a fresh clone, a new worktree or an update. With `CI` set it only makes the link. |
| `githooks-coverage`           | table of the tracked file types: `base`, `opt-in` or `uncovered: <suggested tool>` |
| `githooks-coverage --summary` | one line, for the end of `just lint`. Always exits 0.                              |

Output in this repo:

```text
extension     files  status
msg              36  uncovered: none known
yaml              4  base
sh                4  base
yml               3  base
toml              2  base
md                2  base
nix               1  base
json              1  opt-in (if the repo extends jobs/biome.yml)
in                1  uncovered: none known
githooks-coverage: 2 uncovered types: msg (36) in (1)
```

## Conventions

| Rule                                                                                  | Valid                                  | Invalid                        |
| ------------------------------------------------------------------------------------- | -------------------------------------- | ------------------------------ |
| Subject `type(scope)!: description`, lowercase, no trailing period, max 120 chars     | `feat(caddy): add the paperless route` | `Fix: Thing.`                  |
| Types: build chore ci devops docs feat fix junk perf refactor revert stash style test | `refactor!: drop the v1 api`           | `feature: add x`               |
| Description at least 5 characters                                                     | `fix: retry the dns lookup`            | `fix: dns`                     |
| Branch `<type>/<optional number>/<slug>`, types above plus `renovate` and `wip`       | `devops/123/lint-flake`                | `feature/Lint`                 |
| No AI attribution lines (`Co-Authored-By`, `Generated with`, session trailers)        | a body that mentions a tool by name    | a `Co-Authored-By` bot trailer |

`junk:` is throwaway work to squash before merge; `stash:` is a WIP snapshot committed instead of
`git stash`. Neither may reach `main`. Git's own subjects (`Merge`, `Revert "..."`, `fixup!`, `squash!`) pass.
`commit-msg` never sees `git revert` or `git cherry-pick` without an editor, `git stash`, or commits made in the
forge's web UI.

## Configure

Two tools read a repo file on top of the shared rules, so one rule can change without touching the job:

| Tool         | Repo file                 | Example                                         |
| ------------ | ------------------------- | ----------------------------------------------- |
| markdownlint | `.markdownlint-cli2.yaml` | `config: { MD013: false }` for a notes repo     |
| shellcheck   | `.shellcheckrc`           | `disable=SC2312`                                |

Use `.markdownlint-cli2.yaml`, not `.markdownlint.yaml`: the second replaces the shared rules instead of
merging with them. Either file also works in a subdirectory and applies only there.

The other tools take the shared config by flag. Override those jobs by name in the repo's `lefthook.yml`:

```yaml
pre-commit:
  jobs:
    - name: yaml
      skip: true
    - name: yaml-strict
      glob: '*.{yml,yaml}'
      run: yamllint -c .yamllint.yaml {staged_files}
```

Opt in to biome by adding `.githooks/share/githooks/jobs/biome.yml` to the `extends` list. A repo-specific job
(such as `docker compose config -q`) goes in the repo's `lefthook.yml` next to the guard jobs.

### Same rules in the editor and terminal

With the package in your profile, link the tools' user configs to it. Each tool reads its user config only when the
repo has none, so repo files still win:

```bash
mkdir -p ~/.config/yamllint
ln -s ~/.nix-profile/share/githooks/yamllint.yaml ~/.config/yamllint/config
ln -s ~/.nix-profile/share/githooks/hadolint.yaml ~/.config/hadolint.yaml
ln -s ~/.nix-profile/share/githooks/shellcheckrc ~/.config/shellcheckrc
```

markdownlint-cli2 has no user config: point the editor at
`--config ~/.nix-profile/share/githooks/markdownlint.yaml`.

## Update

`nix flake update githooks && nix develop` in the repo, or `nix profile upgrade githooks` and
`githooks-install` for the profile install.

## Troubleshooting

| Symptom                                                    | Fix                                                             |
| ---------------------------------------------------------- | --------------------------------------------------------------- |
| `githooks: .githooks is missing or dangling`               | `githooks-install` (fresh clone, new worktree, wiped store)     |
| commits pass with no hook output                           | stubs not installed: `githooks-install`                         |
| `Can't find lefthook in PATH`                              | `githooks-install`, which re-renders the stubs with the package path |
| old tools after an update, or hooks fail from a GUI client | `githooks-install` relinks `.githooks` and re-renders the stubs |
| `just lint` cannot find a linter                           | run it inside `nix develop`; only git-invoked hooks get the package `PATH` |
| CI fails on `git diff`                                     | run `just lint` locally and commit the result                   |
| must commit anyway                                         | `LEFTHOOK=0 git commit ...`                                     |

## Development

| Recipe       | Runs                                                                                |
| ------------ | ----------------------------------------------------------------------------------- |
| `just test`  | the hook fixtures and the config drift checks (fast, no build)                      |
| `just check` | `nix flake check`: the same tests plus an end-to-end consumer repo, in the sandbox  |
| `just lint`  | this repo's own hooks on every file, plus shellcheck and shfmt on the extensionless scripts |
| `just build` | the package into `./result`                                                         |

```text
bin/       githooks-install (nix substitutes the package path), githooks-coverage
configs/   one rule file per linter, shipped as share/githooks/*
hooks/     commit-msg.sh, pre-push.sh
jobs/      opt-in job files
tests/     run.sh (fixtures, drift checks), integration.sh (end-to-end), commit-msg/{pass,fail}/*.msg
docs/      design.md: decisions and rejected alternatives
```

CI (`.forgejo/workflows/check.yml`) runs `just check` and `just lint` on every pull request and every push to
`main`. Decisions and rejected alternatives live in [`docs/design.md`](docs/design.md).
