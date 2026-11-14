---
name: state
description: Show or update the hackathon anchor (.claude/hackmode/HACKATHON_STATE.md) and mirror it to the pinned GitHub issue. Use after any decision, cut, mock, blocker, owner change or phase change.
argument-hint: "[what changed]"
---
The hackathon state file is `.claude/hackmode/HACKATHON_STATE.md` (absolute path in the `[HACKMODE ACTIVE]` session context). It is the team's single source of truth, and the hackmode guard always lets you edit it, even on main.

Change requested (may be empty): $ARGUMENTS

**If nothing was requested:** print a brief of at most 8 lines — time left and phase (`bash .claude/hackmode/hooks/context.sh prompt`), challenge, demo-script status, now/next, top blocker, state issue link. Change nothing.

**Otherwise:**
1. Edit only the affected fields. Add one line at the top of the Decision log (`- <ddd HH:MM> — <what / why>`), keep at most 15 log lines and the file under ~80 lines. Write entries in the team language; facts only.
2. Mirror it to GitHub (if `gh` fails or there is no GitHub remote, skip this step and say so):
   - If the file has `State issue: #N` → `gh issue edit N --body-file .claude/hackmode/HACKATHON_STATE.md`
   - Otherwise create it: `gh issue create --title "📍 Hackathon State (auto-updated by Claude)" --body-file .claude/hackmode/HACKATHON_STATE.md`, write `#N` into the `State issue:` line, then pin it with `gh issue pin N`. Older gh versions lack `issue pin`; then use
     `gh api graphql -f query='mutation($id:ID!){pinIssue(input:{issueId:$id}){issue{number}}}' -f id="$(gh api repos/{owner}/{repo}/issues/N --jq .node_id)"`
     If pinning still fails, skip it. Finally run `gh issue edit N --body-file …` once so the issue shows its own number.
3. Reply with one line: what changed + the issue link.
