#!/bin/sh
# End-to-end: a consuming repo with the guarded lefthook.yml, .githooks linked to the package given as $1.
# Proves: stubs install, a formatter fix lands in the commit, a linter finding (also an optional shellcheck
# check) and a bad subject are rejected, a repo .markdownlint-cli2.yaml overrides one shared rule
# and keeps the rest (the --all-files run re-checks c.md under MD024 siblings_only),
# --all-files works, a missing .githooks link blocks the commit. It also proves what the shared rules cannot show
# alone: prettier's yaml output passes yamllint with nothing to report, and each new job fixes, re-stages and skips as the
# base rules promise. Hook output goes to $TMP/log, shown on failure.
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
# logs <description> <pattern> <command...>: the command must succeed and its output must match the pattern,
# so a skipped job is proven skipped, not merely absent from a passing run
logs() {
  d=$1
  pat=$2
  shift 2
  if ! "$@" >"$LOG" 2>&1; then nok "$d"; elif grep -q "$pat" "$LOG"; then ok "$d"; else nok "$d (no '$pat')"; fi
}
# same <description> <a> <b>: two strings must be equal
same() {
  printf 'want: %s\ngot:  %s\n' "$3" "$2" >"$LOG"
  if [ "$2" = "$3" ]; then ok "$1"; else nok "$1"; fi
}
# committed <description> <rev:path> <want>: a blob must have exactly this content
committed() {
  got=$(git show "$2")
  same "$1" "$got" "$3"
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
expect "editorconfig template shipped" test -f .githooks/share/githooks/editorconfig
git add lefthook.yml .gitignore
expect "bootstrap commit accepted" git commit -q -m "chore: bootstrap hooks"

printf '#!/bin/sh\necho   "x"\n' >a.sh && git add a.sh
expect "commit with a formatter fix" git commit -q -m "feat: add a script"
committed=$(git show HEAD:a.sh | sed -n 2p)
expect "fixed content is what got committed" test "$committed" = 'echo "x"'
status=$(git status --porcelain)
expect "tree clean after the fix" test -z "$status"

# shellcheck disable=SC2016 # the literal $(ls) is the point: an unused variable, SC2034
printf '#!/bin/sh\nfoo=$(ls)\n' >b.sh && git add b.sh
refuse "shellcheck finding blocks the commit" SC2034 git commit -q -m "feat: add b"
git reset -q b.sh && rm -f b.sh

# shellcheck disable=SC2016 # the literal is the point: a masked exit code, an optional check (SC2312)
printf '#!/bin/sh\necho "$(false | wc -l)"\n' >e.sh && git add e.sh
refuse "optional shellcheck check blocks the commit" SC2312 git commit -q -m "feat: add e"
git reset -q e.sh && rm -f e.sh

printf 'mode: 0644\n' >f.yml && git add f.yml
refuse "implicit octal in yaml blocks the commit" octal-values git commit -q -m "feat: add f"
git reset -q f.yml && rm -f f.yml

printf 'FROM alpine:3.20\nRUN apk add --no-cache curl\n' >Dockerfile && git add Dockerfile
expect "unpinned apk add is accepted" git commit -q -m "feat: add a dockerfile"
printf 'FROM alpine:3.20\nRUN cd /tmp && apk add --no-cache curl\n' >Dockerfile && git add Dockerfile
refuse "hadolint warning blocks the commit" DL3003 git commit -q -m "fix: change the dockerfile"
git reset -q Dockerfile && git checkout -q Dockerfile

printf '# T\n\n## A\n\n### Verify\n\nx\n\n## B\n\n### Verify\n\ny\n' >c.md && git add c.md
refuse "bad subject rejected" "commit-msg: FAIL subject" git commit -q -m "Docs: Add Title"
expect "good subject accepted, sibling duplicate headings pass" git commit -q -m "docs: add title"

cat >n.md <<'MD'
# Notes

One paragraph per line, the way Obsidian writes notes: lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor.
MD
git add n.md
refuse "markdown line over 120 blocks the commit" MD013 git commit -q -m "docs: add notes"
# .markdownlint-cli2.yaml merges with the shared rules; a .markdownlint.yaml would replace them (MD024 back)
printf 'config:\n  MD013: false\n' >.markdownlint-cli2.yaml && git add .markdownlint-cli2.yaml
expect "a repo .markdownlint-cli2.yaml overrides one shared rule" git commit -q -m "docs: add notes without a line limit"

# yaml: comments, a leading --- and a `>` scalar all stay, and yamllint has nothing to say
cat >y.yml <<'YML'
---
# a head comment
a:   1
list:
- x   # a line comment


- y
fold: >
  one
  two

  three
YML
git add y.yml
expect "bad yaml is formatted and committed" git commit -q -m "feat: add yaml"
want=$(printf -- '---\n# a head comment\na: 1\nlist:\n  - x # a line comment\n\n  - y\nfold: >\n  one\n  two\n\n  three')
committed "the committed yaml is the formatted yaml" HEAD:y.yml "$want"
status=$(git status --porcelain)
same "tree clean after the yaml fix" "$status" ""
lint=$("$PKG/bin/yamllint" -c .githooks/share/githooks/yamllint.yaml y.yml 2>&1)
same "yamllint reports nothing on formatted yaml" "$lint" ""
# the shapes that make yamlfmt change a value come through as written; quoted strings end up double quoted
cat >v.yml <<'YML'
kept: |+
  x


doubled: |
  x


  y
quoted: 'a

  b'
last: |
  one

  three
YML
want=$(sed "s/'/\"/g" v.yml)
git add v.yml
expect "yaml with tricky scalars commits" git commit -q -m "feat: add v"
committed "block and quoted scalars keep their values" HEAD:v.yml "$want"
git rm -q -f v.yml && git commit -q -m "chore: drop v"

printf 'a:   1\n' >pnpm-lock.yaml && cp pnpm-lock.yaml control.yaml && git add pnpm-lock.yaml control.yaml
expect "a lockfile commit is accepted" git commit -q -m "chore: add a lockfile"
committed "pnpm-lock.yaml is left alone" HEAD:pnpm-lock.yaml "a:   1"
committed "the same content elsewhere is formatted" HEAD:control.yaml "a: 1"
printf 'a:   2\n' >pnpm-lock.yaml && git add pnpm-lock.yaml
expect "a commit with only the lockfile is accepted" git commit -q -m "chore: bump the lockfile"
git rm -q -f pnpm-lock.yaml control.yaml && git commit -q -m "chore: drop the lockfile"

printf 'a:   1\n' >own.yml && printf 'own.yml\n' >.prettierignore && git add own.yml .prettierignore
expect "a repo .prettierignore commits" git commit -q -m "feat: add own"
committed "a repo .prettierignore keeps a file out of the yaml job" HEAD:own.yml "a:   1"
git rm -q -f own.yml .prettierignore && git commit -q -m "chore: drop own"

printf 'mode:   0644\n' >h.yml && git add h.yml
refuse "yamllint blocks after yamlfmt ran" octal-values git commit -q -m "feat: add h"
committed "a blocked commit leaves the fix unstaged" :h.yml "mode:   0644"
got=$(cat h.yml)
same "and the fix in the worktree" "$got" "mode: 0644"
git reset -q h.yml && rm -f h.yml

printf 'a: 1\nb: 2\nc: 3\n' >p.yml && git add p.yml && git commit -q -m "feat: add p"
printf 'a:   9\nb: 2\nc: 3\n' >p.yml && git add p.yml
printf 'a:   9\nb: 2\nc: 7\n' >p.yml
expect "partly staged yaml commits" git commit -q -m "feat: change p"
want=$(printf 'a: 9\nb: 2\nc: 3')
committed "only the staged hunk is committed, formatted" HEAD:p.yml "$want"
if grep -q '^c: 7$' p.yml; then kept=yes; else kept=no; fi
same "the unstaged hunk survives the formatter" "$kept" yes
git checkout -q p.yml

printf 'a:   1\n' >u.yml
echo more >>c.md && git add c.md
logs "an unrelated commit skips the yaml job" 'yaml.*skip' git commit -q -m "docs: extend title"
got=$(cat u.yml)
same "and leaves an unstaged yaml file alone" "$got" "a:   1"
rm -f u.yml

mkdir sub && printf 'resource "a" "b" {\n  x=1\n}\n' >m.tf && printf 'a=1\n' >sub/v.tfvars && git add m.tf sub/v.tfvars
expect "bad terraform is formatted and committed" git commit -q -m "feat: add terraform"
want=$(printf 'resource "a" "b" {\n  x = 1\n}')
committed "the committed .tf is the formatted one" HEAD:m.tf "$want"
committed "the committed .tfvars is the formatted one" HEAD:sub/v.tfvars "a = 1"
printf 'a=2\n' >u.tf
echo more >>c.md && git add c.md
logs "an unrelated commit skips the terraform job" 'terraform.*skip' git commit -q -m "docs: extend title again"
got=$(cat u.tf)
same "and leaves an unstaged .tf file alone" "$got" "a=2"
rm -f u.tf
git rm -q -r -f m.tf sub && git commit -q -m "chore: drop terraform"

# the local copy of what blckbrd-inventory carries today, plus the variants it missed
for f in Containerfile sub/Containerfile Containerfile.dev sub/Containerfile.dev app.Containerfile; do
  mkdir -p sub && printf 'FROM alpine:3.20\nRUN cd /tmp && apk add --no-cache curl\n' >"$f" && git add "$f"
  refuse "hadolint blocks $f" DL3003 git commit -q -m "feat: add a containerfile"
  git reset -q "$f" && rm -f "$f"
done
rmdir sub
printf 'FROM alpine:3.20\nRUN apk add --no-cache curl\n' >Containerfile && git add Containerfile
expect "a clean Containerfile is accepted" git commit -q -m "feat: add a containerfile"
git rm -q -f Containerfile && git commit -q -m "chore: drop the containerfile"

expect "all-files run" env PATH="$PKG/bin:$PATH" "$PKG/bin/lefthook" run pre-commit --all-files --no-stage-fixed

# editor and terminal: shellcheck reads the shipped shellcheckrc through ~/.config, a repo .shellcheckrc wins
mkdir -p "$TMP/xdg" && ln -s "$PKG/share/githooks/shellcheckrc" "$TMP/xdg/shellcheckrc"
# shellcheck disable=SC2016 # the literal is the point: a masked exit code (SC2312)
printf '#!/bin/sh\nprintf "%%s\\n" "$(false | wc -l)"\n' >g.sh
refuse "a linked XDG shellcheckrc enables the optional checks" SC2312 env HOME="$TMP" XDG_CONFIG_HOME="$TMP/xdg" "$PKG/bin/shellcheck" g.sh
expect "without it they stay off" env HOME="$TMP" XDG_CONFIG_HOME="$TMP/none" "$PKG/bin/shellcheck" g.sh
printf 'disable=SC2312\n' >.shellcheckrc
expect "a repo .shellcheckrc takes precedence" env HOME="$TMP" XDG_CONFIG_HOME="$TMP/xdg" "$PKG/bin/shellcheck" g.sh
rm -f g.sh .shellcheckrc

rm .githooks && echo x >d.md && git add d.md
refuse "missing .githooks blocks the commit" "githooks: .githooks is missing" git commit -q -m "docs: add d"
ln -s "$PKG" .githooks
git rm -q -f --cached d.md && rm -f d.md

printf '%s of %s integration checks passed\n' "$((n - fail))" "$n"
[ "$fail" -eq 0 ]
