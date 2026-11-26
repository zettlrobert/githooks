# Troubleshooting

| Symptom | Fix |
|---|---|
| `githooks: .githooks is missing or dangling` | `githooks-install` (fresh clone, new worktree, wiped store) |
| commits pass with no hook output | stubs not installed: `githooks-install` |
| `Can't find lefthook in PATH` | `githooks-install`, which re-renders the stubs with the package path |
| old tools after an update, or hooks fail from a GUI client | `githooks-install` relinks `.githooks` and re-renders the stubs |
| `just lint` cannot find a linter | run it inside `nix develop`; only git-invoked hooks get the package `PATH` |
| CI fails on `git diff` | run `just lint` locally and commit the result |
| a repo runs other tool versions than the host | expected: the `.githooks` link decides, see [Where it runs](where-it-runs.md#which-version-runs) |
| must commit anyway | `LEFTHOOK=0 git commit ...` |
