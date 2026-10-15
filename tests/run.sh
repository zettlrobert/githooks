#!/bin/sh
# Fixture tests for hooks/commit-msg.sh and hooks/pre-push.sh. Run: tests/run.sh   (exit 0 = all pass)
# commit-msg: every tests/commit-msg/pass/*.msg must exit 0, every tests/commit-msg/fail/*.msg must exit 1.
# pre-push: stdin ref lines against a temp repo with a bare remote.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HOOKS="$HERE/../hooks"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
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
}

# --- commit-msg ---------------------------------------------------------------
git init -q "$TMP/cm" && cd "$TMP/cm" && git config user.email t@t && git config user.name t
for f in "$HERE"/commit-msg/pass/*.msg; do
  case $f in *commentchar-semicolon*) git config core.commentChar ';' ;; *) ;; esac
  if sh "$HOOKS/commit-msg.sh" "$f" 2>/dev/null; then ok "accept $(basename "$f")"; else nok "accept $(basename "$f")"; fi
  git config --unset core.commentChar 2>/dev/null || true
done
for f in "$HERE"/commit-msg/fail/*.msg; do
  if sh "$HOOKS/commit-msg.sh" "$f" 2>/dev/null; then nok "reject $(basename "$f")"; else ok "reject $(basename "$f")"; fi
done

# --- pre-push -----------------------------------------------------------------
git init -q --bare "$TMP/remote.git"
git init -q -b main "$TMP/pp" && cd "$TMP/pp" && git config user.email t@t && git config user.name t
git remote add origin "$TMP/remote.git"
echo a >a && git add a && git commit -q -m 'feat: base' && git push -q origin main
BASE=$(git rev-parse HEAD)
echo c >c && git add c && git commit -q -m 'feat: fine' && FINE=$(git rev-parse HEAD) # clean on top of BASE
git checkout -q -b feat/y && echo b >b && git add b && git commit -q -m 'junk: wip stuff' && JUNK=$(git rev-parse HEAD)
git checkout -q main
Z=0000000000000000000000000000000000000000
pp() { # $1 expected exit, $2 label, stdin = ref lines
  if printf '%s\n' "$3" | sh "$HOOKS/pre-push.sh" origin "$TMP/remote.git" >/dev/null 2>&1; then got=0; else got=1; fi
  if [ "$got" = "$1" ]; then ok "pre-push $2"; else nok "pre-push $2 (got $got, want $1)"; fi
}
pp 1 "junk commit onto main" "refs/heads/main $JUNK refs/heads/main $BASE"
pp 0 "junk commit onto a feature branch" "refs/heads/feat/y $JUNK refs/heads/feat/y $Z"
pp 1 "new main containing junk" "refs/heads/main $JUNK refs/heads/main $Z"
pp 0 "clean range onto main" "refs/heads/main $FINE refs/heads/main $BASE"
pp 0 "valid branch with number" "refs/heads/feat/123/add-thing $FINE refs/heads/feat/123/add-thing $Z"
pp 0 "valid devops branch" "refs/heads/devops/lint-flake $FINE refs/heads/devops/lint-flake $Z"
pp 0 "valid renovate branch" "refs/heads/renovate/docker-tags $FINE refs/heads/renovate/docker-tags $Z"
pp 1 "uppercase branch" "refs/heads/bad/Name $FINE refs/heads/bad/Name $Z"
pp 1 "old feature type" "refs/heads/feature/x $FINE refs/heads/feature/x $Z"
pp 1 "no slug" "refs/heads/feat/ $FINE refs/heads/feat/ $Z"
pp 0 "delete line" "(delete) $Z refs/heads/feat/y $FINE"
pp 0 "tag line" "refs/tags/v1 $FINE refs/tags/v1 $Z"
pp 0 "HEAD pushed to a valid branch" "HEAD $FINE refs/heads/junk/zz $Z"

# --- shared config drift ------------------------------------------------------
# the shell job's -o list and configs/shellcheckrc (the editor's copy) must name the same optional checks
job=$(sed -n 's/.*shellcheck -o \([a-z,-]*\).*/\1/p' "$HERE/../lefthook.yml" | tr ',' '\n' | sort)
rc=$(sed -n 's/^enable=//p' "$HERE/../configs/shellcheckrc" | sort)
if [ -n "$job" ] && [ "$job" = "$rc" ]; then ok "shellcheckrc matches the shell job's -o list"; else nok "shellcheckrc matches the shell job's -o list"; fi

printf '%s of %s checks passed\n' "$((n - fail))" "$n"
[ "$fail" -eq 0 ]
