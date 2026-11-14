# claude-devmode-configurator · `hackmode`

One command switches Claude Code into **NASA Space Apps hackathon mode** for a repo: deadline-aware, demo-first, no nitpicking, specialised subagents, hard guardrails. `off` puts the repo back exactly as it was.

Built for Claude running on a home server over SSH (tmux + Remote Control). Teammates on Windows get the same mode with `hackmode.bat`.

## What the mode is

| Layer | What it does |
|---|---|
| **Output style `Hackathon`** | System-prompt layer: clock first, demo first, terse, no nitpicks, bias to action |
| **Doctrine** (`CLAUDE.local.md`) | Phases, rules of engagement, git policy, delegation table, language rules. A team `CLAUDE.md` is never touched |
| **Clock + state anchor** | Every prompt gets `[HACKMODE] T-31h28m to deadline · 34% elapsed · phase BUILD`. Each session starts with `HACKATHON_STATE.md` (challenge, demo script, NASA data, owners, mocks, cuts, decisions). `/state` updates it and mirrors it to a pinned GitHub issue. Phase changes and stale state trigger nudges |
| **5 subagents** (hard `maxTurns` budgets) | `scope-guard` plan/triage/velocity, read-only · `crash-reviewer` PR/diff review for crashes, secrets and broken contracts only · `nasa-data-wrangler` datasets → small mock JSON · `feature-builder` one issue → PR in an isolated worktree · `pitch-writer` submission text, 30 s video script, slides, README |
| **7 skills** | `/pivot-check` · `/triage <idea>` · `/review-pr <n>` · `/build <issue#>` · `/data <source>` · `/pitch` · `/state [change]` |
| **Guardrails** | Edits auto-approved but never on `main`; deterministic guard hook; allow/deny rules ([details](#guardrails)) |
| **Status line** | `🛰 HACKMODE │ ⏳ 31h28m left (34%) │ BUILD → INTEGRATE in 9h40m │ ⎇ claude/12-map │ ctx 23%` |

Phases, by % of the event elapsed: **IDEATE** 0–10 · **BUILD** 10–55 · **INTEGRATE** 55–80 · **FREEZE** 80–92 · **SUBMIT** 92–100.

## Requirements
- Claude Code signed in with your claude.ai account (needed for Remote Control), `git`, and `gh` signed in as Claude's GitHub account.
- Linux: bash and tmux. Windows: Git for Windows (Claude Code runs the hooks with its Git Bash) and PowerShell (built in).

## Quick start: home server (Linux)
```bash
git clone https://github.com/valkor-prototypes/claude-devmode-configurator ~/hackmode-kit
~/hackmode-kit/hackmode.sh install        # optional: puts `hackmode` on your PATH
claude auth login && gh auth login        # fresh sign-ins before the event

git clone <team-repo-url> ~/spaceapps
hackmode on ~/spaceapps --start "2026-11-14 09:00" --hours 48
hackmode tmux ~/spaceapps
```
`tmux` opens session `spaceapps` with three windows:
- **lead**: Claude in the main checkout.
- **dev**: Claude in the sibling worktree `~/spaceapps-dev` (branch `claude/dev`).
- **ops**: a shell showing `hackmode status`.

Both Claude windows start with Remote Control, so you can drive them from claude.ai/code or the Claude app. **Accept the folder-trust prompt once in each window**: the allowlist only applies to trusted folders. Detach with `Ctrl-b d` and re-attach with `tmux attach -t spaceapps`.

Then anchor the project in Claude:
```
/state challenge: <name>; value prop: <1 sentence>; demo: 1) … 2) … 3) …; team: @a front-end, @b data
```

## Quick start: Windows
```bat
git clone https://github.com/valkor-prototypes/claude-devmode-configurator C:\hackmode-kit
C:\hackmode-kit\hackmode.bat on C:\code\spaceapps --start "2026-11-14 09:00" --hours 48
C:\hackmode-kit\hackmode.bat claude C:\code\spaceapps
```
Same mode, hooks and guardrails. tmux and the dev worktree are Linux-only.

## Commands
`hackmode.sh` / `hackmode.bat` `<command> [repo-path] [options]` (repo-path defaults to the current directory)

| Command | What it does |
|---|---|
| `on` | Enable. Safe to re-run: refreshes the templates and keeps state + clock |
| `off [--force]` | Disable and restore. State + guard log are archived to `~/.hackmode/archive/` |
| `status` | Clock, phase, state freshness, guard blocks (Linux also: dev worktree, tmux, gh login) |
| `clock` | Show or move the clock: `clock --deadline "2026-11-15 18:00"` (keeps the start) |
| `state [--edit]` | Print (or, on Linux, edit) `HACKATHON_STATE.md` |
| `claude [-- args]` | Start Claude in the repo with the configured autonomy |
| `tmux [--no-dev]` | The war room (Linux only) |

Options: `--start "YYYY-MM-DD HH:MM"` (default now) · `--hours N` (48) · `--deadline "YYYY-MM-DD HH:MM"` · `--event NAME` · `--lang pt-BR` (language for issues and PR comments; judge-facing text is always English) · `--autonomy allowlist|auto|yolo`

## Guardrails
- **Branch rule:** edits are auto-approved (`acceptEdits`), but never while `main`, `master` or the default branch is checked out. Claude works on `claude/<issue>-<slug>`, pushes, opens a PR, and never merges.
- **Guard hook:** a deterministic PreToolUse hook that the model can't talk its way past, and that also covers subagents. It blocks:
  - `sudo`/`su`
  - `rm` on `/`, `~`, `.`, `..`, `.git` or anything outside the project (except `/tmp`)
  - disk and power commands, fork bombs, `curl … | sh`
  - force-push, pushes to protected branches, deleting other people's remote branches
  - `reset --hard`, `clean -f`, history rewrites, `git add -A` / `git add .`, commits or merges on protected branches
  - `gh pr merge`, repo deletion or edits, `gh auth token`, API `DELETE`, docker prune, package publishing
  - reading, sourcing or staging `.env`, credential files, dumping environment variables
  - hardcoded secrets in commands or in written files
  - edits to hackmode's own files

  Every block is logged to `.claude/hackmode/guard.log`.
- **Permission rules:** a broad allowlist (npm/pnpm/yarn/bun, python/pip/uv, node, git, gh, curl, GDAL/NetCDF/HDF5 tools…) runs without prompts, anything else asks, and deny rules duplicate the worst cases.
- **Autonomy:**
  - `allowlist` (default): the rules above.
  - `auto`: Claude Code's auto-mode classifier.
  - `yolo`: `--dangerously-skip-permissions`; only the guard hook protects you.

  `auto` and `yolo` can't be set from project settings, so launch with `hackmode claude` or `hackmode tmux`.

## What gets written
Everything is local and git-excluded (`.git/info/exclude`), and existing files are backed up and restored by `off`.
```
CLAUDE.local.md                     managed doctrine block (your own content in the file is kept)
.claude/settings.local.json         output style, permissions, hooks, status line
.claude/agents/*.md                 5 subagents
.claude/skills/*/SKILL.md           7 skills
.claude/output-styles/hackathon.md
.claude/hackmode/                   config (clock), HACKATHON_STATE.md, hooks/, guard.log, backups
```
To customise, edit `template/` and re-run `hackmode on`.

## Tips
- Claude Code sign-ins can expire mid-weekend, so run `claude auth login` on the server right before the event.
- Ubuntu's apt `gh` is too old for `gh issue pin`. `/state` falls back to the GraphQL API, but a newer `gh` is better.
- After changing the guard or the scripts, run `bash tests/guard_test.sh` (160 allow/block cases) and `bash tests/e2e_test.sh` (full on → tmux → off cycle).
- Ideas borrowed from the team's [agentkit](https://github.com/GuiAlvesor/agentkit): a deterministic guard hook next to agent judgement, a managed `CLAUDE.md` block, and bounded review loops.
