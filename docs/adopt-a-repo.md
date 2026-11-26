# Adopt it in a repo

Every repo needs the same three things: a `lefthook.yml` that extends the shared base, a `.githooks` link to the
package, and the hook stubs. `githooks-install` makes the last two.

## Repo with a flake

Follow the [quickstart](../README.md#quickstart). The dev shell runs `githooks-install` on every `nix develop`, so
the repo's `flake.lock` pins the tools. `inputs.nixpkgs.follows = "nixpkgs"` keeps one nixpkgs per repo, so the
tools share the store closure with the rest of the dev shell.

## Repo without a flake

```bash
nix profile add github:zettlrobert/githooks   # once per machine, or use the host install
githooks-install                               # in the repo, once per clone and per worktree
```

The `lefthook.yml` and `.gitignore` lines are the same as in the quickstart. The tools come from the host's
install, see [Where it runs](where-it-runs.md).

## `just lint`

Run the hooks on every tracked file from the terminal:

```just
lint:
    lefthook run pre-commit --all-files --no-stage-fixed
    gitleaks dir . -c .githooks/share/githooks/gitleaks.toml
    githooks-coverage --summary
```

`--no-stage-fixed` keeps lefthook from `git add`ing your unrelated edits. The `gitleaks dir` line is needed because
the staged-mode `secrets` job sees nothing under `--all-files`. Run it inside `nix develop`: only git-invoked hooks
get the package `PATH`.

## CI

Run `just lint` inside the dev shell, then fail on any diff, so an unformatted file fails the run:

```yaml
- name: just lint
  run: nix develop --command just lint && git diff --exit-code HEAD
```

With `CI` set, `githooks-install` only makes the link: `lefthook run` needs no stubs, and a persisted CI store
must not collect one GC root per run.

## Repo-specific jobs

A job only one repo needs (such as `docker compose config -q`) goes in that repo's `lefthook.yml`, next to the
guard jobs. To change a shared job, see [Configure](configure.md).
