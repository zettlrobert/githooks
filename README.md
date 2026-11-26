# githooks

Shared git hooks for my repos, as one nix package: [lefthook](https://lefthook.dev), the formatters and
linters, their rules, and the commit and branch conventions. The same checks run on commit, in `just lint` and in
CI, with tool versions pinned by nix. Nothing is downloaded at commit time.

Needs nix with flakes. Builds for `x86_64-linux`, `aarch64-linux` and `aarch64-darwin`.

## How it works

- The package holds lefthook, every linter, one rule file per linter, and a shared base `lefthook.yml`.
- A repo commits its own `lefthook.yml` that extends the shared one.
- `githooks-install` links `.githooks` in the repo to one package and installs the git hook stubs.
- On commit, lefthook runs each job on the staged files its `glob` matches. Formatters fix and re-stage the
  files. A failing linter blocks the commit.
- The `.githooks` link decides which tool versions run. In a flake repo, the dev shell sets it on every
  `nix develop`, so the repo's `flake.lock` picks the versions.

```bash
lefthook run pre-commit --all-files   # run the commit checks on every tracked file
LEFTHOOK=0 git commit ...             # skip the hooks once
```

## Quickstart

In a repo with a flake:

1. Add the input and the package to the dev shell:

   ```nix
   inputs.githooks = {
     url = "github:zettlrobert/githooks";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   # in mkShell
   packages = [ inputs.githooks.packages.${system}.default ];
   shellHook = "githooks-install";
   ```

2. Commit a `lefthook.yml`. The guard jobs fail loudly when `.githooks` is missing, because lefthook skips a
   missing `extends` target without a word:

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

3. Ignore the link and copy the editor defaults:

   ```bash
   printf '.githooks\nlefthook-local.yml\n' >> .gitignore
   nix develop --command cp .githooks/share/githooks/editorconfig .editorconfig
   ```

   The dev shell runs `githooks-install` first, which makes `.githooks`. Lefthook cannot extend
   `.editorconfig`, so each repo commits its own copy.

You're done when `git commit` prints the lefthook summary. Run `nix develop` once per clone and per worktree.

Repos without a flake, `just lint` and CI: see [Adopt it in a repo](docs/adopt-a-repo.md).

## Docs

| Doc | What it covers |
|---|---|
| [Adopt it in a repo](docs/adopt-a-repo.md) | flake and non-flake repos, the `just lint` recipe, CI |
| [Where it runs](docs/where-it-runs.md) | repo dev shells, NixOS hosts and nix profiles, and which version wins |
| [What runs](docs/what-runs.md) | the jobs per file type, the hooks, `githooks-install` and `githooks-coverage` |
| [Conventions](docs/conventions.md) | the commit message and branch name rules |
| [Configure](docs/configure.md) | repo overrides, opt-in jobs, the same rules in the editor |
| [Update](docs/update.md) | bump the tools in a repo, on hosts and in this repo (Renovate) |
| [Troubleshooting](docs/troubleshooting.md) | symptoms and fixes |
| [Development](docs/development.md) | work on this repo: recipes, layout, tests, CI |
| [Design](docs/design.md) | decisions and the alternatives rejected |
