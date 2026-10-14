#!/bin/sh
# End-to-end: a consuming repo with the guarded lefthook.yml, .githooks linked to the package given as $1.
# Proves: stubs install, a formatter fix lands in the commit, a linter finding and a bad subject are rejected,
# --all-files works, a missing .githooks link blocks the commit. Hook output goes to $TMP/log, shown on failure.
set -eu
PKG=${1:?usage: tests/integration.sh <githooks package path>}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LOG=$TMP/log
fail=0
n=0
ok() {
  n=$((n + 1))
  printf 'ok   %s\n' "$1"
}
nok() {
  n=$((n + 1))
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1"
  sed 's/^/     /' "$LOG"
}
# expect <description> <command...>: the command must succeed
expect() {
  d=$1
  shift
  if "$@" >"$LOG" 2>&1; then ok "$d"; else nok "$d"; fi
}
# refuse <description> <pattern> <command...>: the command must fail and its output must match the pattern,
# so a check passes only when the intended hook did the blocking
refuse() {
  d=$1
  pat=$2
  shift 2
  if "$@" >"$LOG" 2>&1; then nok "$d"; elif grep -q "$pat" "$LOG"; then ok "$d"; else nok "$d (no '$pat')"; fi
}

git init -q "$TMP/repo" && cd "$TMP/repo"
git config user.email t@t && git config user.name t && git config commit.gpgsign false
cat >lefthook.yml <<'YML'
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
YML
printf '.githooks\nlefthook-local.yml\n' >.gitignore
ln -s "$PKG" .githooks
expect "lefthook install" "$PKG/bin/lefthook" install
expect "stubs installed" test -x .git/hooks/pre-commit
git add lefthook.yml .gitignore
expect "bootstrap commit accepted" git commit -q -m "chore: bootstrap hooks"

printf '#!/bin/sh\necho   "x"\n' >a.sh && git add a.sh
expect "commit with a formatter fix" git commit -q -m "feat: add a script"
expect "fixed content is what got committed" test "$(git show HEAD:a.sh | sed -n 2p)" = 'echo "x"'
expect "tree clean after the fix" test -z "$(git status --porcelain)"

# shellcheck disable=SC2016 # the literal $(ls) is the point: an unused variable, SC2034
printf '#!/bin/sh\nfoo=$(ls)\n' >b.sh && git add b.sh
refuse "shellcheck finding blocks the commit" SC2034 git commit -q -m "feat: add b"
git reset -q b.sh && rm -f b.sh

echo "# Title" >c.md && git add c.md
refuse "bad subject rejected" "commit-msg: FAIL subject" git commit -q -m "Docs: Add Title"
expect "good subject accepted" git commit -q -m "docs: add title"

expect "all-files run" env PATH="$PKG/bin:$PATH" "$PKG/bin/lefthook" run pre-commit --all-files --no-stage-fixed

rm .githooks && echo x >d.md && git add d.md
refuse "missing .githooks blocks the commit" "githooks: .githooks is missing" git commit -q -m "docs: add d"
ln -s "$PKG" .githooks

printf '%s of %s integration checks passed\n' "$((n - fail))" "$n"
[ "$fail" -eq 0 ]
