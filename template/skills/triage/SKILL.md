---
name: triage
description: Turn a feature idea into at most 3 small GitHub issues — or push back if it is scope creep. Use when someone proposes a feature or asks to plan or split work.
argument-hint: "<feature idea>"
context: fork
agent: scope-guard
background: false
allowed-tools:
  - Bash(bash .claude/hackmode/hooks/context.sh *)
  - Bash(echo *)
---
Hackathon context right now:
!`bash .claude/hackmode/hooks/context.sh brief 2>/dev/null || echo "(no hackmode context: read .claude/hackmode/HACKATHON_STATE.md)"`

Feature request: "$ARGUMENTS"

1. Check `gh issue list --state open --limit 40` for duplicates.
2. If the feature does not directly serve a step of the demo script, or the phase is FREEZE/SUBMIT: push back in ≤ 3 lines and propose a 10× simpler alternative (hardcode, fake it, screenshot, static data slice). Create nothing.
3. Otherwise split it into at most 3 issues — Data/Mock · Logic · UI/Integration, skipping the ones not needed — and create them with `gh issue create --title "[P0|P1] <imperative title>" --body-file - <<'EOF' … EOF`. Body ≤ 6 lines in the team language: **What** · **Why judges care** (demo step #) · **Fastest way** (what is hardcoded vs. dynamic) · **Done when** (visible in the demo). Add `--assignee <login>` only if the state file names an owner for that area.
4. Return the issue URLs plus one line on what you cut or simplified.
