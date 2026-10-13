#!/bin/sh
# commit-msg hook: enforce the commit message conventions (docs/design.md, "Conventions").
#   <type>(<scope>)!: <description>   type from TYPES, scope optional, "!" optional
#   description: starts with a lowercase letter or digit, no trailing period, at least 5 characters
#   subject at most 120 characters; git's own subjects (Merge, Revert, Reapply, fixup!, squash!, amend!) pass
#   any line attributing an AI tool (Co-Authored-By ... Claude/Anthropic, "Generated with ...", robot emoji) fails
# Usage: commit-msg <path to COMMIT_EDITMSG>   (exit 0 = accept, 1 = reject with the rule on stderr)
# Portable sh, no sourcing, LC_ALL=C so [a-z] means ASCII and byte counts are stable.
export LC_ALL=C

TYPES='build|chore|ci|devops|docs|feat|fix|junk|perf|refactor|revert|stash|style|test'
SUBJECT_RE="^($TYPES)(\([a-z0-9._/-]+\))?!?: [a-z0-9][a-z0-9 _./,+:;=()'>-]*[a-z0-9)]\$"
# attribution forms only, not the bare product names: a commit about configuring a tool stays legal
AI_RE='^co-authored-by:.*(anthropic|claude|copilot|chatgpt|gemini|openai)|noreply@anthropic\.com|generated with.*(claude|copilot|chatgpt|gemini|anthropic)|^claude-session:|🤖'
MAX_LEN=120
MIN_DESC=5

msg_file="$1"
[ -r "$msg_file" ] || {
  echo "commit-msg: cannot read $msg_file" >&2
  exit 1
}

# strip comment lines (core.commentChar/commentString aware) and everything after a scissors line
cc=$(git config --get core.commentString 2>/dev/null || git config --get core.commentChar 2>/dev/null || echo '#')
[ -z "$cc" ] || [ "$cc" = auto ] && cc='#'
esc=$(printf '%s' "$cc" | sed 's/[][\/.*^$]/\\&/g')
msg=$(sed -n -e "/^$esc -* >8 -*\$/q" -e "/^$esc/!p" "$msg_file" | git stripspace)

# empty after stripping: git aborts the commit itself with its own message
[ -z "$msg" ] && exit 0

hit=$(printf '%s\n' "$msg" | grep -inE "$AI_RE" | head -n 1)
if [ -n "$hit" ]; then
  printf 'commit-msg: FAIL attribution of an AI tool is not allowed in commit messages (line %s)\n' "$hit" >&2
  exit 1
fi

subject=$(printf '%s\n' "$msg" | sed -n 1p)

# subjects git writes itself
case $subject in
"Merge "* | "Revert \""* | "Reapply \""* | "fixup! "* | "squash! "* | "amend! "*) exit 0 ;;
esac

if [ ${#subject} -gt $MAX_LEN ]; then
  printf 'commit-msg: FAIL subject is %s characters, maximum is %s\n' "${#subject}" "$MAX_LEN" >&2
  exit 1
fi

desc=${subject#*: } # shortest prefix match: stops at the first ": "
if [ ${#desc} -lt $MIN_DESC ]; then
  printf 'commit-msg: FAIL description is under %s characters, e.g. "fix: resolve the dns lookup"\n' "$MIN_DESC" >&2
  exit 1
fi

if ! printf '%s\n' "$subject" | grep -Eq "$SUBJECT_RE"; then
  printf 'commit-msg: FAIL subject must be "<type>(<scope>)!: <lowercase description>", no trailing period\n' >&2
  printf '  types: %s\n  example: feat(caddy): add the paperless route\n  got: %s\n' "$(printf '%s' "$TYPES" | tr '|' ' ')" "$subject" >&2
  exit 1
fi

exit 0
