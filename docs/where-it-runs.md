# Where it runs

The package gets installed in three places. A host install puts the tools on PATH, but it hooks no repo. Each repo
still needs its `lefthook.yml` and `githooks-install`.

| Where | Installed through | Tool versions from | Used for |
|---|---|---|---|
| Repo with a flake | the dev shell, `shellHook = "githooks-install"` | the repo's `flake.lock` | commits and CI in that repo |
| NixOS host (yggdrasil, e.g. fenrir) | `environment.systemPackages = [ (inputs.githooks.lib.mkGithooks pkgs) ]` | the host's nixpkgs | the editor, repos without a flake |
| Non-NixOS host (yggdrasil profiles, e.g. midgard) | `ps.githooks` in the nix profile, or `nix profile add github:zettlrobert/githooks` | yggdrasil's `nixpkgs-unstable` pin | the editor, repos without a flake |

## Which version runs

The `.githooks` link in the repo decides, and it points at whichever package last ran `githooks-install`:

- In a flake repo, `nix develop` relinks it to the repo's pin every time.
- In a repo without a flake, it points at the host's install.

The pins may differ, so a repo and a host can run different linter versions. That's expected. In a flake repo the
dev shell version is the one that counts, because CI runs it.

## Why NixOS hosts use `mkGithooks`

`lib.mkGithooks pkgs` builds the package from the host's own nixpkgs. The host then carries one nixpkgs and one
glibc, not a second copy from this flake's pin. The `packages` output uses this flake's pin, which suits profiles
and repos.

## Related

- [Adopt it in a repo](adopt-a-repo.md) - the per-repo setup
- [Update](update.md) - how each of the three moves to new tool versions
- [Configure](configure.md#same-rules-in-the-editor-and-terminal) - point the editor at the host install
