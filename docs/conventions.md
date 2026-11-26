# Conventions

`commit-msg` and `pre-push` enforce these rules:

| Rule | Valid | Invalid |
|---|---|---|
| Subject `type(scope)!: description`, lowercase, no trailing period, max 120 chars | `feat(caddy): add the paperless route` | `Fix: Thing.` |
| Types: build chore ci devops docs feat fix junk perf refactor revert stash style test | `refactor!: drop the v1 api` | `feature: add x` |
| Description at least 5 characters | `fix: retry the dns lookup` | `fix: dns` |
| Branch `<type>/<optional number>/<slug>`, types above plus `renovate` and `wip` | `devops/123/lint-flake` | `feature/Lint` |
| No AI attribution lines (`Co-Authored-By`, `Generated with`, session trailers) | a body that mentions a tool by name | a `Co-Authored-By` bot trailer |

`junk:` is throwaway work to squash before merge. `stash:` is a WIP snapshot committed instead of `git stash`.
Neither may reach `main`.

Git's own subjects pass: `Merge`, `Revert "..."`, `fixup!`, `squash!`.

`commit-msg` never sees `git revert` or `git cherry-pick` without an editor, `git stash`, or commits made in the
forge's web UI.
