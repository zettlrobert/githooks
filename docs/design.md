# Design: shared git hooks and linters as a nix flake

Date: 2026-10-11. Status: approved; reviewed by three fresh-eyes reviews the same day (lefthook lab, scripts, nix),
findings folded in. Hooks and tests implemented, flake pending. Scope: personal repos and own orgs (zettlrobert,
blckbrd-org, zerodev-solutions, luminaria-life). Work repos keep their own tooling. Adoption is opt-in per
repo; `homelab` goes first.

## Goal

One setup, maintained in this repo, that gives every adopting repo the same formatters, linters, commit-message
and branch-name rules, runnable identically from a git hook, from `just lint`, and in Forgejo Actions. No
network at hook time. Tool versions pinned through nix, not through a second version list.

## Decisions

| Decision | Alternative rejected | Reason |
|---|---|---|
| lefthook as the hook runner | prek/pre-commit, git-hooks.nix alone, hk | Only lefthook has fix-and-restage of staged files (`stage_fixed`), parallel jobs and glob filtering in plain YAML. prek and git-hooks.nix fail the commit on a formatting change instead of fixing it. hk has the best mechanics but is a year old with a breaking v2 last month and a Pkl config. |
| Tools and config delivered as one nix package from this repo | lefthook `remotes` (git clone at install), pre-commit hook repos (clone and build per hook) | Store paths: fetched once when the input is locked, offline afterwards, pinned in the consumer's `flake.lock`. Two consumers pin it: each repo's dev shell (CI) and `nix-profiles` core-packages (global PATH). |
| `extends` a path inside the repo (`.githooks/...`) | `LEFTHOOK_CONFIG`, remotes | `.githooks` is a symlink to the store path, created by `githooks-install` and registered as a GC root, so garbage collection cannot dangle it. A fresh clone, a new worktree or a wiped store still can, and lefthook silently ignores a missing `extends` target, so the per-repo file carries a guard job that fails the commit until `githooks-install` has run. |
| `rc` file with the package's `bin` baked in, referenced by the relative path `.githooks/share/githooks/lefthookrc` | relying on the dev shell or the global profile being active | GUI git and plain terminals run hooks without either: the installed stub sources `rc` before it looks for lefthook. Verified in the lab. `rc` applies to git-invoked hooks only, not to `lefthook run`, so `just lint` runs inside the dev shell. |
| `symlinkJoin` plus `postBuild` for the package | `buildEnv`, `substituteAll` | `$out` is in scope in `postBuild`, so the rc file and the base config get the real store path; `substituteAll` is deprecated. No `git` or `coreutils` in the package: hooks run from a git process that already has them, and `bin/git` would collide with nix-profiles core. Closure about 350 MiB, dominated by node (markdownlint-cli2) and python (yamllint, actionlint). |
| Consumers set `inputs.githooks.inputs.nixpkgs.follows = "nixpkgs"` | this flake's own nixpkgs pin everywhere | One toolchain closure and one nixpkgs source per repo (CI's persisted store would otherwise carry a second ~400 MiB closure). A consumer's nixpkgs bump can change formatter output; the PR check shows it. This flake keeps its own pin for `nix flake check`. |
| `bin/githooks-install` in the package, called by the shell hook | shell hook logic inline in nix | One script, with the store path baked in, serves flake repos (shell hook calls it) and repos without a flake (`nix profile add github:zettlrobert/githooks && githooks-install`). `extends: ~/.nix-profile/...` does not work: lefthook expands neither `~` nor env variables. |
| One tool set for all languages, jobs filtered by `glob` | per-language sub-packages chosen per repo | A job whose glob matches no staged file is skipped, so a repo never declares which linters it needs. Cost is disk, once, in the store. Repos can still disable a base job by name with `skip: true`. |
| Biome is opt-in: shipped as `jobs/biome.yml`, not in the base | biome in the base with a per-repo opt-out | The idiomatic choice for JavaScript repos is the toolchain the repo already declares (eslint, prettier). A repo that wants biome adds the file to its `extends` list. The binary stays in the package. |
| Keep `junk` and `stash` as distinct temporary types | one `wip` type | Same enforcement (pre-push keeps both off `main`), different intent: `junk` is dirty work on a branch to be squashed or rebased away before merge; `stash` is a WIP snapshot committed instead of `git stash`, so it survives branch switches and can be pushed to a backup branch. Git's own stash never runs the commit-msg hook, so the two never collide. `wip` stays a branch prefix only. |
| markdownlint-cli2 | rumdl | The standard tool and config format; rumdl is faster but at 0.2.x. Swap later if commit time suffers. |
| nixfmt (RFC 166) | alejandra, nixpkgs-fmt | The formatter nixpkgs enforces. nixpkgs-fmt is archived. |
| gitleaks in the hook, nothing else for secrets | trufflehog | MIT, static, offline; trufflehog verifies secrets over the network and is AGPL. |
| Conventions: 14 commit types, lowercase, 120 chars, `<type>/<slug>` branches | commitlint `config-conventional` as is | Matches Conventional Commits; adds `devops`, `junk`, `stash` (throwaway types, blocked from `main` by pre-push) and `revert`. 120 instead of 100 is a solo-workflow choice. |
| `just lint` = `lefthook run pre-commit --all-files --no-stage-fixed` plus `gitleaks dir .`; CI runs `lefthook run pre-commit --all-files --no-stage-fixed --fail-on-changes` and then `git diff --exit-code HEAD` | a second check-only hook | One job list for hook, terminal and CI. `--no-stage-fixed` because `stage_fixed` otherwise `git add`s every matched tracked file, including a developer's unrelated pending edits (verified). The staged-mode gitleaks job sees nothing under `--all-files`, hence the directory scan. In CI a formatter change fails twice over. |

## Package layout (`githooks` flake)

```text
flake.nix                        # packages.<system>.default (symlinkJoin + postBuild), devShell, checks
lefthook.yml                     # shared base: hooks, jobs, globs, rc, assert_lefthook_installed
jobs/biome.yml                   # opt-in job file: a repo adds it to its extends list
bin/githooks-install.in          # link .githooks as a GC root, lefthook install; skips in CI; @out@ substituted
bin/githooks-coverage            # advisory: tracked file types vs base and opt-in jobs, names the tool for uncovered ones
hooks/commit-msg.sh              # conventions, see below (done)
hooks/pre-push.sh                # branch pattern, junk/stash guard (done)
configs/.markdownlint-cli2.yaml  # line length 120, tables and code blocks exempt
configs/.yamllint.yaml           # relaxed base, line length 120, document-start off
configs/actionlint.yaml          # self-hosted-runner labels: [docker], else "label docker is unknown"
configs/gitleaks.toml            # default rules plus the pass/placeholder allowlist
configs/biome.json               # format + recommended lint
configs/taplo.toml
tests/run.sh, tests/commit-msg/  # fixture tests for the two scripts (49 checks, done); extends/merge lab proven
docs/design.md                   # this file
README.md                        # the project README, see outline below
```

Installed as `$out/bin/*` (lefthook, every linter, `githooks-install`) and `$out/share/githooks/` (configs,
scripts, the base `lefthook.yml`, the generated `lefthookrc` with `PATH=$out/bin:$PATH`).

Tool set (nixpkgs pin at build): lefthook, shellcheck, shfmt, ruff, nixfmt, statix, deadnix, yamllint,
markdownlint-cli2, taplo, hadolint, actionlint, biome, gitleaks. No git, no coreutils (see Decisions).

## Per-repo contract

1. `flake.nix`: input `githooks` with `inputs.nixpkgs.follows = "nixpkgs"`, the package in the dev shell
   packages, and `githooks-install` appended to the existing `shellHook`. The script runs
   `nix-store --realise <pkg> --add-root .githooks` (one command: symlink plus GC root; `--indirect` is a
   no-op on current nix) and `lefthook install` (idempotent; re-renders the stubs when the merged config
   changes). It does nothing when `CI` is set or `.git` is missing: `lefthook run` needs no stubs, and the
   persisted CI store must not collect a GC root per run. Each git worktree needs its own `.githooks`.
2. `lefthook.yml`, committed (the canonical consumer file):

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

   The guard is there because lefthook silently ignores a missing `extends` target: without it a dangling or
   missing `.githooks` (fresh clone, new worktree, store wiped) lets every commit through. `githooks-install`
   must run once per git worktree, since `.githooks` lives in the worktree.
   Repo-specific jobs go under it and merge with the base. Opt-out of a base job: same job name with `skip: true`.
   Opt-in to biome: `extends: [".githooks/share/githooks/lefthook.yml", ".githooks/share/githooks/jobs/biome.yml"]`.
3. `.gitignore`: `.githooks`, `lefthook-local.yml`.
4. `justfile`: `lint` recipe = `lefthook run pre-commit --all-files --no-stage-fixed`, then
   `gitleaks dir . -c .githooks/share/githooks/gitleaks.toml`, then `githooks-coverage --summary`.
5. CI: `nix develop --command just lint && git diff --exit-code HEAD` as a step after the existing checks.
6. Without a flake (JavaScript repos with only `package.json`): `nix profile add github:zettlrobert/githooks`,
   then `githooks-install` in the repo; same `lefthook.yml` and `.gitignore` lines.

Bump: `nix flake update githooks` in the repo; the same in `nix-profiles`. The two pins may drift; each
consumer has its own complete copy.

## Hook jobs (base `lefthook.yml`)

pre-commit, `parallel: true`, `{staged_files}` filtered by glob, formatters with `stage_fixed: true`:

| Glob | Command | Mode |
|---|---|---|
| `*.sh` | `shfmt -w`, then `shellcheck` (one piped group, so the check sees the formatted file under `parallel: true`) | fix, check |
| `*.py` | `ruff format`, `ruff check --fix` | fix, check |
| `*.nix` | `nixfmt`, `statix check`, `deadnix --fail` | fix, check, check |
| `*.{yml,yaml}` | `yamllint -c <config>` | check |
| `*.md` | `markdownlint-cli2 --fix --config <config>` | fix |
| `*.toml` | `taplo fmt`, `taplo check` | fix, check |
| `Dockerfile*`, `*.Dockerfile` | `hadolint` | check |
| `.forgejo/workflows/*.y*ml`, `.github/workflows/*.y*ml` | `actionlint -config-file <config>` | check |
| `*.{js,mjs,cjs,ts,tsx,json,jsonc}` | `biome check --write --config-path <config>` | fix, check; opt-in via `jobs/biome.yml`, not in the base |
| all staged | `gitleaks git --pre-commit --staged --no-banner -c <config>` | check |

commit-msg: `hooks/commit-msg.sh`. pre-push: `hooks/pre-push.sh`. `assert_lefthook_installed: true` so a
missing runner fails the commit instead of letting it through (verified: without it the stub exits 0). It only
applies once the base config is loaded; the `githooks-present` guard job in the per-repo file covers the
missing-base case. CI runs the hook with `--fail-on-changes` and follows it with `git diff --exit-code HEAD`,
so a formatter change fails the run.

Not in hooks: vale (style sync needs network), trufflehog, tests, `docker compose config` (repo-specific job in
homelab, needs the docker CLI from that repo's shell).

## Coverage report (`githooks-coverage`)

Lefthook ignores files that match no glob, so nothing says when a repo gains a file type without a job.
`githooks-coverage` lists the tracked extensions (`git ls-files`) with counts and marks each one: covered by
a base job, covered by an opt-in file (`jobs/biome.yml`), or uncovered. For uncovered types it names the
standard tool when the script knows one (go: golangci-lint, rust: rustfmt and clippy, css/html: biome,
terraform: tofu fmt, dockerfile already covered). Always exits 0; `--summary` prints one line, which `just lint`
shows at the end. It is a report for the developer and the maintenance signal for this package: a type that
keeps showing up uncovered across repos gets a job and a config here. About 40 lines of sh; the known-types
table lives in the script, the base config stays the only list of what runs.

## Conventions (the two scripts)

commit-msg, first line:

- `type(scope)!: description`; scope `[a-z0-9._/-]+` optional, `!` optional.
- type in: build chore ci devops docs feat fix junk perf refactor revert stash style test.
- description: starts with a lowercase letter or digit, then `a-z 0-9 space _ / . , + : ; = ( ) ' > -`, ends
  with a letter, digit or `)`, so no trailing period; at least 5 characters. Whole subject at most 120
  characters. The spec's first character set rejected 34 of 150 real homelab subjects (parentheses, colons);
  this one accepts all conventional ones and still rejects Renovate's `Update … Docker tag` form.
- Accepted as is: `Merge …`, `Revert "…"`, `Reapply "…"`, `fixup! …`, `squash! …`, `amend! …`.
- Comment lines are stripped first (`core.commentChar`/`commentString` aware) and everything after a
  `git commit -v` scissors line is ignored; an empty message exits 0 and lets git abort with its own message.
- Any remaining line: reject attribution of an AI tool: `Co-Authored-By` naming Anthropic, Claude, Copilot,
  ChatGPT, Gemini or OpenAI; `noreply@anthropic.com`; `Generated with …` naming one of them;
  `Claude-Session:`; the robot emoji. Checked before the git-subject shortcut, so a merge cannot smuggle a
  trailer. Bare product names stay legal: a commit about the Claude Code dotfiles passes.

pre-push:

- Reads git's stdin lines (`<local ref> <local sha> <remote ref> <remote sha>`), so `git push origin
  other-branch` and `HEAD:refs/heads/x` are judged by the remote ref; deletions (all-zero local sha) and tags
  are ignored. The old script used the checked-out branch and was wrong for both.
- Branch: `^(build|chore|ci|devops|docs|feat|fix|junk|perf|refactor|revert|stash|style|test|renovate|wip)/([0-9]+/)?[a-z0-9._-]+$`,
  or `main`/`master`.
- When pushing to `main`/`master`: refuse if any commit in `<remote sha>..<local sha>` has type `junk` or
  `stash`; for a new or unfetched remote branch the range is `<local sha> --not --remotes=<remote>`.

Both scripts print the rule that failed and an example of a valid value.

## README outline

The README is the manual usage guide and the front page. Sections, in this order: what it is and why (three
sentences, no history); lefthook in a nutshell for readers who have never used it (a runner, not a linter:
`lefthook.yml` lists hooks and jobs, a job is a command plus a `glob`, `lefthook install` writes stubs into
`.git/hooks`, jobs run in parallel on the staged files, `stage_fixed` re-adds formatted files, `extends`
merges the shared base, `lefthook run pre-commit --all-files` by hand, `LEFTHOOK=0 git commit` skips once);
install in a flake repo and in a repo without a flake (the exact lines, copy-paste
ready); what runs on commit (the job table above, with fix/check), what `just lint` and CI run; the
conventions with one valid and one invalid example each, the meaning of `junk` and `stash`, and which git
commands never run the hook (revert and cherry-pick without an editor, stash, server-side commits);
how linter rules are configured (every config file lives in the package next to the job that references
it; a repo with its own rules writes its own job instead of extending the shared one); opt-in
biome and per-repo jobs; bump the tools and rules; troubleshooting (hook not running, `Can't find lefthook`,
`.githooks` dangling, stubs stale after a bump, GUI git); development (`just test`, `nix flake check`, layout);
link to `docs/design.md`. Moving the source to the Forgejo instance later is one documented line
(`git+https://forgejo.<domain>/zettlrobert/githooks?ref=main`).

## Verification

- `tests/run.sh` (done): 36 commit-msg fixtures and 13 pre-push cases, 49 checks, run by `just test` and
  by `nix flake check` (sandbox: git in `nativeBuildInputs`, `HOME=$TMPDIR`, no network).
- Lefthook behaviour proven in a scratch lab on 2026-10-11 (lefthook 2.1.14): relative `extends` resolves
  against the repo root from any subdirectory through a symlink outside the repo; `rc` from the extended file
  is sourced by the installed stub; jobs merge by name and `skip: true` disables a base job; `stage_fixed`
  lands fixes in the commit and a failing check keeps them staged; `--all-files` means `git ls-files`
  (untracked files are not inspected); `lefthook install` makes no network calls without `remotes`.
- homelab after integration: `just lint` clean after the baseline commit; a commit with a deliberately
  unformatted `.sh` file gets fixed and re-staged; a commit titled `Fix: Thing` is rejected; `check.yml`
  green with the new step; a run with an unformatted file goes red at `git diff --exit-code`.
- Timing target: a typical commit (one or two files) under 2 s; measured and recorded in the README.

## Rollout

1. This repo: implement, test, README, push to GitHub and Forgejo.
2. homelab: contract, `docker compose config -q` job, `just lint`, CI step, baseline commit of auto-fixes,
   `docs/linting.md` (how to run, what runs, how to bump, troubleshooting).
3. nix-profiles: add the package to core-packages (global PATH for GUI git and plain terminals; no `bin/git`
   collision because the package ships none).
4. Vault: recipe "Add the shared git hooks to a repo", concept note on hooks-from-the-store; update the
   git-conventions rule in the configurations repo (it still says the hook runs trunk).
5. Other repos: opt in when touched, using the recipe.

## Settled (2026-10-11, lab and lefthook source)

All three former open points resolved in favour of the design; no fallback is needed. Two behaviours to
document for users: `rc` is sourced by git-invoked hooks only, so `just lint` runs inside the dev shell; the
installed stubs bake the rc path, and `lefthook install` re-renders them on a bump, so a GUI commit between a
bump and the next `nix develop` runs the previous, GC-rooted package. `assert_lefthook_installed` guards the
runner, not the base config: lefthook ignores a missing `extends` target, so the per-repo guard job is what
catches a missing `.githooks`.
