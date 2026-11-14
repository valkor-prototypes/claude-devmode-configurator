---
name: data
description: Send a NASA dataset, API endpoint or local data file to the nasa-data-wrangler — it inspects it and saves a small, demo-ready static JSON/CSV slice with schema and provenance.
argument-hint: "<dataset URL | API endpoint | local file> [what the demo needs]"
context: fork
agent: nasa-data-wrangler
allowed-tools:
  - Bash(bash .claude/hackmode/hooks/context.sh *)
  - Bash(echo *)
---
Hackathon context right now (challenge, demo script, existing data):
!`bash .claude/hackmode/hooks/context.sh brief 2>/dev/null || echo "(no hackmode context available)"`

Source to wrangle and what the demo needs: $ARGUMENTS

Follow your procedure: inspect → pick the most demo-friendly slice → save it under `data/` with a provenance line → commit on your `claude/data-<slug>` branch.
Return only: file path(s), exact schema, 3 sample records, provenance, real vs. mocked.
