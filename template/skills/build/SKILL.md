---
name: build
description: Hand one GitHub issue to the feature-builder subagent — it implements it in an isolated worktree on a claude/<issue>-<slug> branch, pushes and opens a PR while you keep working.
argument-hint: "<issue number> [notes]"
context: fork
agent: feature-builder
allowed-tools:
  - Bash(bash .claude/hackmode/hooks/context.sh *)
  - Bash(echo *)
---
Hackathon context right now (stack, run command, demo script, team language):
!`bash .claude/hackmode/hooks/context.sh brief 2>/dev/null || echo "(no hackmode context available)"`

Implement GitHub issue #$0 end-to-end. Notes from the lead (the first word is the issue number): $ARGUMENTS

Start with `gh issue view $0`. Follow your build procedure (branch → smallest change on the demo path → smoke check → commit → push → PR).
Return the PR URL, how to see it in the demo, what is mocked, and anything left undone.
