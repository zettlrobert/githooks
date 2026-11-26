# Configure

## Change one rule

Three tools read a repo file on top of the shared rules:

| Tool | Repo file | Example |
|---|---|---|
| markdownlint | `.markdownlint-cli2.yaml` | `config: { MD013: false }` for a notes repo |
| shellcheck | `.shellcheckrc` | `disable=SC2312` |
| prettier | `.prettierignore` | a generated file the `yaml` job must leave alone |

Use `.markdownlint-cli2.yaml`, not `.markdownlint.yaml`: the second replaces the shared rules instead of
merging with them. Either file also works in a subdirectory and applies only there.

## Replace a job

The other tools take the shared config by flag. Override the job by name in the repo's `lefthook.yml`: jobs with
the same `name` merge, so `skip: true` turns the shared one off.

```yaml
pre-commit:
  jobs:
    - name: yaml
      skip: true
    - name: yaml-strict
      glob: '*.{yml,yaml}'
      run: yamllint -c .yamllint.yaml {staged_files}
```

## Opt-in jobs

Add the job file to the `extends` list:

```yaml
extends:
  - '.githooks/share/githooks/lefthook.yml'
  - '.githooks/share/githooks/jobs/biome.yml'      # JavaScript, TypeScript, JSON
  - '.githooks/share/githooks/jobs/prettier.yml'   # CSS, SCSS
```

Skip the prettier job in a repo with its own Prettier setup: the job passes `--config`, so the repo's
`printWidth` and other options are ignored.

The shared Prettier rules are 2 spaces, 120 columns and single quotes, with double quotes for YAML. `tofu fmt` has
no config: its style is fixed.

## Same rules in the editor and terminal

With the package in your profile, link the tools' user configs to it. Each tool reads its user config only when the
repo has none, so repo files still win:

```bash
mkdir -p ~/.config/yamllint
ln -s ~/.nix-profile/share/githooks/yamllint.yaml ~/.config/yamllint/config
ln -s ~/.nix-profile/share/githooks/hadolint.yaml ~/.config/hadolint.yaml
ln -s ~/.nix-profile/share/githooks/shellcheckrc ~/.config/shellcheckrc
```

markdownlint-cli2 and prettier have no user config: point the editor at
`--config ~/.nix-profile/share/githooks/markdownlint.yaml` and `--config ~/.nix-profile/share/githooks/prettier.json`.

On a NixOS host, `environment.systemPackages` links only some `share` paths into the system profile. Add
`environment.pathsToLink = [ "/share/githooks" ];` to the host, then use `/run/current-system/sw/share/githooks/`
in place of `~/.nix-profile/share/githooks/`.
