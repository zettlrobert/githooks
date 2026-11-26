# Update

Tool versions come from nixpkgs, so updating means moving a nixpkgs pin. Each place in
[Where it runs](where-it-runs.md) has its own pin.

| What | Command |
|---|---|
| a repo with a flake | `nix flake update githooks && nix develop` |
| a nix profile install | `nix profile upgrade githooks`, then `githooks-install` in each repo without a flake |
| yggdrasil profile hosts | `./update-flakes.sh profiles` in yggdrasil (moves `nixpkgs-unstable` and `githooks`) |
| yggdrasil NixOS hosts | the configs and scripts move with the `githooks` input; the tools move with the host's nixpkgs |

A consumer's update can change formatter output. Run `just lint` and commit the result, or CI fails on the diff.

## This repo

This repo's tool versions move with its own `flake.lock`. Renovate (the homelab workflow) opens a weekly PR that
refreshes it, and one per workflow action. Don't merge either before the check workflow is green.

By hand:

```bash
nix flake update
just check
```

## When biome needs a migration

The check fails on `biome.json loads without migration notes` when the new biome deprecates something in
`configs/biome.json` or moves past its `$schema` version. Fix it on the update branch:

```bash
nix develop --command biome migrate --write --config-path configs/biome.json
```

Then set `linter.rules.preset` back to `"recommended"`: the migration writes `"none"`, which turns every lint rule
off. `just check` passes again when both biome checks are green.
