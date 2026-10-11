#!/bin/sh
# pre-push hook: branch naming and the junk/stash guard (docs/design.md, "Conventions").
#   branch: <type>/<optional number>/<slug>, type from TYPES (commit types plus renovate and wip), or main/master
#   main/master: refuse the push if the pushed range contains a commit of type junk or stash
# git calls it as: pre-push <remote name> <remote url>, with one line per ref on stdin:
#   <local ref> <local sha> <remote ref> <remote sha>   (all-zero sha = delete or new ref)
export LC_ALL=C

TYPES='build|chore|ci|devops|docs|feat|fix|junk|perf|refactor|revert|stash|style|test|renovate|wip'
BRANCH_RE="^($TYPES)/([0-9]+/)?[a-z0-9._-]+\$"
remote="$1"
rc=0

is_zero() { case $1 in *[!0]*) return 1 ;; *) return 0 ;; esac; }

while read -r _ lsha rref rsha; do   # local ref unused
  [ -n "$rref" ] || continue
  is_zero "$lsha" && continue                      # deleting a remote ref
  case $rref in refs/heads/*) ;; *) continue ;; esac   # tags, notes
  branch=${rref#refs/heads/}
  case $branch in
    main|master)
      if is_zero "$rsha" || ! git rev-parse -q --verify "$rsha^{commit}" >/dev/null 2>&1; then
        range="$lsha --not --remotes=$remote"      # remote branch is new or not fetched
      else
        range="$rsha..$lsha"
      fi
      # shellcheck disable=SC2086  # $range is intentionally word-split
      bad=$(git log --format='%h %s' $range | grep -E '^[0-9a-f]+ (junk|stash)(\(|!|:)')
      if [ -n "$bad" ]; then
        printf 'pre-push: FAIL %s would receive junk/stash commits; rebase them away first:\n%s\n' "$branch" "$bad" >&2
        rc=1
      fi
      ;;
    *)
      if ! printf '%s' "$branch" | grep -Eq "$BRANCH_RE"; then
        printf 'pre-push: FAIL branch "%s" must be <type>/<optional number>/<slug>, e.g. feat/123/add-thing\n  types: %s\n  rename with: git branch -m <new name>\n' "$branch" "$(printf '%s' "$TYPES" | tr '|' ' ')" >&2
        rc=1
      fi
      ;;
  esac
done

exit $rc
