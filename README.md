# githooks

Shared git hooks for my repos, as one nix package: [lefthook](https://lefthook.dev), the formatters and
linters, their rules, and the commit and branch conventions. Same checks on commit, in `just lint` and in CI.
Nothing is downloaded at commit time.

## How it works

Lefthook runs jobs on git hooks. A job is a command plus a glob; on commit it gets the staged files that
match, formatters re-stage what they fix, and any failing job blocks the commit. A repo commits a small
`lefthook.yml` that extends the shared base through `.githooks`, a gitignored symlink into the nix store.

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

Optional `justfile` recipe, also what CI runs (followed by `git diff --exit-code HEAD`):

```just
lint:
    lefthook run pre-commit --all-files --no-stage-fixed
    gitleaks dir . -c .githooks/share/githooks/gitleaks.toml
    githooks-coverage --summary
```

## What runs

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

Jobs whose glob matches nothing are skipped. `githooks-coverage` lists the repo's file types and flags those
without a job. Scripts without an extension are not matched; name them `.sh` or add a job.

## Conventions

| Rule                                                                                  | Example                                |
| ------------------------------------------------------------------------------------- | -------------------------------------- |
| Subject `type(scope)!: description`, lowercase, no trailing period, max 120 chars     | `feat(caddy): add the paperless route` |
| Types: build chore ci devops docs feat fix junk perf refactor revert stash style test | `refactor!: drop the v1 api`           |
| Branch `<type>/<optional number>/<slug>`, types above plus `renovate` and `wip`       | `devops/123/lint-flake`                |
| No AI attribution lines (`Co-Authored-By`, `Generated with`, session trailers)        |                                        |

`junk:` is throwaway work to squash before merge; `stash:` is a WIP snapshot committed instead of
`git stash`. Neither may reach `main`. Git's own subjects (`Merge`, `Revert "..."`, `fixup!`, `squash!`) pass.

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

Opt in to biome by adding `.githooks/share/githooks/jobs/biome.yml` to the `extends` list. Shared rules live
in [`configs/`](configs/).

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
| old tools after an update, or hooks fail from a GUI client | `githooks-install` relinks `.githooks` and re-renders the stubs |
| CI fails on `git diff`                                     | run `just lint` locally and commit the result                   |
| must commit anyway                                         | `LEFTHOOK=0 git commit ...`                                     |

## Development

`just test` runs the hook fixtures, `just check` runs them plus an end-to-end test in the nix sandbox,
`just lint` runs this repo's own hooks. Decisions and rejected alternatives: [`docs/design.md`](docs/design.md).
