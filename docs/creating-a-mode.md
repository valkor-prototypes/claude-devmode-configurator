# Creating a mode

A mode answers six questions for one kind of work: how Claude thinks and talks, what the rules are, what the situation is right now, who does specialised work, what must never happen, and what the human sees. The hackathon mode is one set of answers. This guide covers designing another one and wiring it in.

## 1. Engine vs. mode content

| Engine (reusable mechanism) | Mode content (what you write per mode) |
|---|---|
| install/remove lifecycle: manifest, backups, exclude block, doctrine block | output style (persona) |
| hook runtime: config loading, clock math, state injection, guard core, status line | doctrine (rules, phases, delegation table) |
| tmux war room, dev worktree, Remote Control flags | state template (the anchor's fields) |
| baseline safety rules (sudo, `rm -rf /`, force-push, `.env`, secrets…) | agents and skills |
| | allowlist for the mode's stack, extra deny/guard rules |
| | phase model and hints, labels, defaults |

In v1 the split isn't clean. These hackathon-specific bits still live in engine files:

| Where | What |
|---|---|
| `template/hooks/lib.sh` → `hm_clock`, `hm_clock_line` | phase names, thresholds (10/55/80/92 %), hints, the `[HACKMODE]` label |
| `template/hooks/context.sh` | the `[HACKMODE ACTIVE]` header, the `[TBD]` nudge (knows the state file's field names), the "Team language" line |
| `template/hooks/statusline.sh` | phase colours, the `HACKMODE` label |
| `template/settings.local.json` | `"outputStyle": "Hackathon"`, NASA data tools in the allowlist |
| `hackmode.sh` / `hackmode.bat` | default event, tmux session `spaceapps`, the `hackathon.md` style name, help text |
| `lib/hackmode-win.ps1` → `status` | a second copy of the phase model |

The proposed refactor in §4 moves all of these into the mode.

## 2. Design checklist (answer these before writing files)

1. **Who is the user, and what does success look like?** (a demo in 48 h · a client sign-off · understanding a topic · a stable hotfix)
2. **What should Claude stop doing?** This is the default behaviour you're turning off (nitpicks, over-engineering, handing out full solutions, wide refactors…).
3. **What must never happen?** These become guard rules and deny rules, not doctrine.
4. **What is the anchor?** A deadline with phases, milestones, a checklist, an incident timeline, or none. Which fields belong in the state file?
5. **Which recurring commands deserve a skill?** Skills are what you type from your phone.
6. **Which bulky or specialised work deserves a subagent?** Name its tools, model, `maxTurns` and return format.
7. **What may run without asking?** That's the allowlist for the mode's stack.
8. **Language rules:** which text is for whom.

## 3. Writing each piece well

**Output style (persona).** It's part of the system prompt and reaches the main session only; subagents run their own prompt. Keep it to *how to think and talk*, in about 15 bullets. Keep `keep-coding-instructions: true` unless the mode is not about writing code.

**Doctrine (`CLAUDE.local.md` block).** It's loaded every session, so every line costs tokens on every turn. Aim for ≤ ~100 lines of concrete rules and tables. State the git policy, the phases/anchor, the delegation table, and the language rules. Mention the guard without restating its rules ("if blocked, take the safer path or ask").

**Anchor.**
- Pick a type: `deadline` (phases as % elapsed), `milestones` (date list), `checklist` or `none`.
- Give the state template short fields with `[TBD]` placeholders the prompt hook can detect.
- Keep a newest-first decision log with a cap, and a field naming the GitHub issue it mirrors to.
- Nudges should be rare and actionable; at most 2–3 lines per prompt.

**Agents (`.claude/agents/*.md`).**
- One job each. Start `description` with "Use proactively when…", because that's how the main session decides to delegate.
- Least privilege: reviewers get no `Write`/`Edit`. Leave `Agent` out of `tools` unless nesting is intended (subagents can otherwise spawn up to three levels).
- Always set `maxTurns`. Use `model: sonnet` for most agents and `haiku` for cheap triage.
- Restate the 2–3 rules that matter, because the output style doesn't reach subagents.
- Define the return format: the main session only sees the final message.

**Skills (`.claude/skills/<name>/SKILL.md`).**
- Make one skill per command you'd type.
- Use `context: fork` + `agent: <name>` when the work is bulky or noisy. A forked skill doesn't see the chat, so inject context with `` !`bash .claude/hackmode/hooks/context.sh brief 2>/dev/null || echo "(no context)"` `` and list both commands in `allowed-tools`.
- Use `background: false` when the user waits for the answer.
- `$ARGUMENTS` is everything typed; `$0` is the first word.
- Keep `description` specific: it's truncated at 1,536 characters in the skill list.

**Permissions.**
- The allowlist holds what the mode needs to run without prompts (stack CLIs, data tools).
- Deny rules are the cheap first line for the worst cases. Use `Read(...)`/`Edit(...)` for paths; `Write(...)` path rules don't match.
- `auto`/`bypassPermissions` can't come from project settings; pass them as CLI flags.

**Guard rules.**
- Add a rule in `check_rules`: `rule "$CB"'<regex>'"$E" "<reason>" "<what to do instead>"`. `CB` anchors to command position, so arguments and prose don't trigger it.
- For anything structural (branches, paths, files), write a function like `check_push`/`check_paths` instead of a regex.
- Add both an allow case and a block case to `tests/guard_test.sh`. Every rule needs a "do instead", or the model will hunt for a workaround.

## 4. Two ways to ship a new mode

### Today: fork and edit
Works with v1 as-is. It's fine for a one-off.
1. Copy the repo (or the `template/` folder plus the scripts) to a new name.
2. Rewrite the content: `doctrine.md`, `output-styles/*.md` (rename it and update `outputStyle` in `settings.local.json`), `HACKATHON_STATE.md`, `agents/`, `skills/`, and the allowlist.
3. Adjust the engine strings listed in §1 (phases/hints in `lib.sh`, labels, the `[TBD]` nudge, defaults).
4. Optionally rename `.claude/hackmode` → `.claude/<mode>` everywhere (installers, hooks, skills, guard, tests), so two modes can't collide in one repo.
5. Run the tests and the checklist in §6.

### Recommended next: one engine, many modes (proposed, not implemented)
```
claude-devmode-configurator/
├── devmode.sh / devmode.bat        thin entry points (see roadmap.md: Python CLI behind them)
├── engine/
│   ├── settings.base.json          hooks wiring, status line, baseline deny rules
│   └── hooks/                      lib · context · guard · statusline: no mode-specific strings
└── modes/
    ├── hackathon/
    │   ├── mode.json               metadata, defaults, anchor, labels, extra permissions
    │   ├── doctrine.md · output-style.md · STATE.md
    │   ├── agents/*.md
    │   └── skills/*/SKILL.md
    └── <next-mode>/ …
```
`devmode on <repo> --mode hackathon` would merge `settings.base.json` with the mode's permissions, render the templates, and write `.claude/devmode/config` with `MODE=hackathon`. The hooks would read labels, phases and hints from the installed `mode.json` instead of hardcoding them. Sketch of `mode.json`:

```json
{
  "name": "hackathon",
  "label": "HACKMODE",
  "outputStyle": "Hackathon",
  "defaults": { "hours": 48, "lang": "pt-BR", "autonomy": "allowlist", "event": "NASA Space Apps Challenge" },
  "anchor": {
    "type": "deadline",
    "stateTemplate": "STATE.md",
    "staleAfterHours": 3,
    "tbdFields": ["Challenge", "Value prop"],
    "phases": [
      { "name": "IDEATE",    "until": 10,  "hint": "Pick ONE challenge, a 3-step demo script, the dataset…" },
      { "name": "BUILD",     "until": 55,  "hint": "Vertical slice first on mocks…" },
      { "name": "INTEGRATE", "until": 80,  "hint": "Everything on the demo path…" },
      { "name": "FREEZE",    "until": 92,  "hint": "Demo-path fixes only; record the video…" },
      { "name": "SUBMIT",    "until": 100, "hint": "Submit now…" }
    ]
  },
  "permissions": { "allow": ["Bash(gdalinfo *)", "Bash(ncdump *)"], "deny": [] },
  "guard": { "protectedBranches": ["main", "master"], "workBranchPrefix": "claude/" },
  "tmux": { "session": "spaceapps", "devWorktree": true }
}
```

## 5. Mode ideas

| Mode | Anchor | Persona | Agents | Extra guardrails |
|---|---|---|---|---|
| `client` (freelance/agency delivery) | milestones from the SOW + an hours budget | scope-aware; explains changes in client language | scope-checker (vs. the SOW), weekly-report/changelog writer | no prod deploys, no new dependencies without asking |
| `learning` (studying a stack) | a learning-goals checklist | Socratic: explains, asks *you* to write the code, never hands over full solutions | quiz-maker, explain-my-error reviewer | `Edit(src/**)` set to *ask*: you type the code |
| `incident` (production hotfix) | incident timeline + severity | cautious, smallest diff, verifies everything | log-analyst, rollback-planner | tests required before commit, no migrations, release branches protected |
| `oss-maintainer` | release milestones | courteous, follows CONTRIBUTING.md | triager, contribution-guide reviewer, release-notes writer | never push tags, never close issues without a comment |

## 6. Testing a new mode

1. `bash -n` on every script; YAML frontmatter parses (`python3 -c "import yaml…"`, or open the files in the Claude Code `/agents` menu).
2. `bash tests/guard_test.sh` (with your new cases) and `bash tests/e2e_test.sh`.
3. Install into a scratch repo and run `claude doctor`. It must report no settings problems, and it shows how many allow entries it recognised.
4. Live smoke test, capped:
   `claude -p --model haiku --max-budget-usd 0.25 "Quote the line starting with [<LABEL>]; then run <a command your guard must block>"`
   plus `"/<your-skill> smoke test only"` for each forked skill.
5. Run `off`, then confirm `git status` is exactly as before the install.
