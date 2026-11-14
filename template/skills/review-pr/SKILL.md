---
name: review-pr
description: Crash-focused hackathon review of a pull request — flags only demo-breaking bugs, leaked secrets and broken contracts, then posts the verdict as a PR comment. Without a number, audits the current branch instead (no comment).
argument-hint: "<PR number>"
context: fork
agent: crash-reviewer
background: false
---
Review target: PR #$ARGUMENTS

1. If a PR number was given: `gh pr view $ARGUMENTS` and `gh pr diff $ARGUMENTS`. If none was given: review `git diff origin/main...HEAD` plus uncommitted changes, and do not post anything.
2. Apply your crash-review checklist; ignore everything else.
3. For a PR, post the verdict with `gh pr comment $ARGUMENTS --body-file - <<'EOF' … EOF` — max 10 lines, in the team language (see the `Team language` line of `.claude/hackmode/HACKATHON_STATE.md`), first line `✅ SAFE TO MERGE` or `⛔ BLOCKED`, exact copy-paste fixes with `file:line`.
4. Return the same verdict here. Never merge, approve or push.

BUDGET: max 20 tool calls.
