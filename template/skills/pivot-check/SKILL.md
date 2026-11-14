---
name: pivot-check
description: Reality check of team velocity against the hackathon clock — what to cut, what to mock, and the single critical path for the next 3 hours. Use when asked "are we on track?", "what should we cut?", or every few hours.
argument-hint: "[optional focus]"
context: fork
agent: scope-guard
background: false
allowed-tools:
  - Bash(bash .claude/hackmode/hooks/context.sh *)
  - Bash(echo *)
---
Hackathon context right now:
!`bash .claude/hackmode/hooks/context.sh brief 2>/dev/null || echo "(no hackmode context: read .claude/hackmode/HACKATHON_STATE.md)"`

Run a pivot check for the team. Extra focus from the lead (may be empty): $ARGUMENTS

1. Gather in one Bash call: `gh issue list --state open --limit 40; gh pr list --state open; git log --all --since="4 hours ago" --oneline | head -40`.
2. **Reality check:** compare the last 4 hours of commits/PRs with the open P0 issues. Are we stuck on plumbing instead of the visible demo path?
3. **Guillotine:** name the 1–2 open items with the worst demo-impact-to-effort ratio and say "cut" or "mock it by <how>".
4. **Critical path:** the single thing that must work in the next 3 hours for a functional vertical slice, and who owns it.
5. **Phase check:** given the time left, what must the team stop doing right now?

Output: max 12 blunt lines in the team language from the state file. Recommend only — don't create or close issues; the lead session records decisions with /state.
