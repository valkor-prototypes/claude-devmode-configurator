---
name: pitch
description: Draft the judge-facing material — Space Apps submission text, ≤30 s demo video script, ≤7-slide outline, live-demo script, README — via the pitch-writer subagent. Use in the FREEZE/SUBMIT phases or whenever the story needs sharpening.
argument-hint: "[submission | video | slides | demo | readme]"
context: fork
agent: pitch-writer
allowed-tools:
  - Bash(bash .claude/hackmode/hooks/context.sh *)
  - Bash(echo *)
---
Hackathon context right now:
!`bash .claude/hackmode/hooks/context.sh brief 2>/dev/null || echo "(no hackmode context available)"`

Requested deliverable(s): $ARGUMENTS (if empty: all of them).

Follow your pitch procedure. Base every claim on the state file, the README, the git log and the code; list mocks honestly.
Return the file list, the 2-sentence summary and any claim you could not verify.
