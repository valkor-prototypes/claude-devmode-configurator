# How it was built: decisions, trade-offs, gotchas

## The brief, and where each requirement landed

| Requirement | Implementation |
|---|---|
| Strict "system prompt" rules for a 48 h deadline, without the usual nitpicking | Output style **Hackathon** (actually part of the system prompt) + doctrine in `CLAUDE.local.md` (phases, rules of engagement, git policy) + the per-prompt clock |
| Agents for specific tasks, saving time, tokens and context | 5 subagents with least-privilege `tools` and a hard `maxTurns` budget; 7 skills that fork straight into them; a delegation table in the doctrine |
| Guardrails: edit without confirmation, but only on a separate branch; block extreme commands | `defaultMode: acceptEdits` + a dev-command allowlist + deny rules + a deterministic `PreToolUse` guard (branch rule, destructive commands, secrets) |
| Anchor the project's state and the remaining time | `config` epochs → clock/phase injected on every prompt; `HACKATHON_STATE.md` injected at session start, kept fresh by nudges, mirrored to a pinned issue by `/state` |
| Linux (bash) and Windows (batch) scripts | `hackmode.sh`; `hackmode.bat` + a PowerShell helper; one bash hook implementation for both OSes |
| Ready right after the server boots, used over SSH | `hackmode tmux`: lead + dev Claude sessions with Remote Control, plus an ops shell |

## How the work went

1. **Inputs.** Your prototypes (the two `hackathon-claude-mode` scripts, the delegation rules, the review-PR command) gave the shape: inject files, git-exclude them, tmux plus a worktree, three agents. The team's [agentkit](https://github.com/GuiAlvesor/agentkit) contributed three ideas:
   - a deterministic guard hook alongside agent judgement ("the hook can't be convinced");
   - a managed block in the memory file instead of overwriting it;
   - bounded review→fix loops.
2. **Verify before building.** Every Claude Code behaviour the design relies on was checked against the official docs and the installed CLI (`claude --help`, `claude remote-control --help`), not recalled from memory. The table below lists them.
3. **Four questions** to you settled the parts that are taste, not engineering: autonomy (allowlist), state sharing (local + pinned issue), team language (pt-BR), extra agents (pitch-writer, feature-builder).
4. **Build order:** templates (content) → hooks (runtime) → `hackmode.sh` → `hackmode.bat`. The guard got a table-driven test harness *before* the installer existed.
5. **Test, fix, repeat:** 160 guard cases, the e2e lifecycle, `claude doctor` for settings validity, then two capped live `claude -p` runs: the clock reached the model, the guard blocked a commit on `main`, and `/pivot-check` forked into `scope-guard`.

## Claude Code facts the design depends on

| Fact | Consequence |
|---|---|
| `CLAUDE.local.md` is a supported memory file, loaded with `CLAUDE.md` from the cwd and its parents | the doctrine never touches the team's `CLAUDE.md` |
| Output styles live in `.claude/output-styles/`, are selected with `"outputStyle"` (allowed in `settings.local.json`), and `keep-coding-instructions: true` keeps the software-engineering part of the system prompt | the persona is additive, not a replacement |
| Plain stdout of `SessionStart` / `UserPromptSubmit` hooks becomes context (10 000-character cap) | the anchor is pure bash `echo`, and the state is capped at 8 000 bytes |
| `PreToolUse` exit code 2 blocks the call and returns stderr to the model; it beats allow rules and also runs inside subagents | the guard is the hard floor |
| Hook commands run via `sh -c` on Linux/macOS and **Git Bash on Windows** (PowerShell only without Git Bash) | one bash hook implementation for both OSes |
| Permission precedence: deny → ask → allow; `Edit(...)` rules also cover Write/MultiEdit/NotebookEdit, while `Write(...)` path rules don't match | deny rules use `Read(...)`/`Edit(...)` only. (agentkit's `Write(.env)` rules are a trap) |
| `auto` and `bypassPermissions` don't take effect from project or local settings | those autonomy levels are passed as CLI flags by `hackmode claude` / `hackmode tmux` |
| Allow rules from project settings are ignored until the workspace trust dialog is accepted (reported by `claude doctor`, which reads settings without prompting) | README: accept trust once per window; `claude doctor` is the validity check |
| Subagent frontmatter: `maxTurns` (stops with partial output), `isolation: worktree`, `color`, `model`; unknown fields are ignored | budgets are enforced, not just requested; feature-builder runs in its own worktree |
| Skills: `context: fork` + `agent: <name>` runs the skill inside that subagent; `` !`cmd` `` output is inlined before the prompt is sent (permission-checked; a non-zero exit aborts) | `/pivot-check` etc. go straight to the right agent with clock + state pre-loaded; the injected command always exits 0 |
| `claude --remote-control <name>` = interactive session that is also reachable from claude.ai/mobile; `claude remote-control` = a server that spawns sessions | tmux runs interactive sessions with Remote Control, so they're visible locally and remotely |

## Decisions and trade-offs

| Decision | Why | Rejected alternative |
|---|---|---|
| Doctrine in `CLAUDE.local.md` as a marked block | never clobbers or commits into the team's `CLAUDE.md`; no pull conflicts; your own notes survive | overwriting `CLAUDE.md` (prototype): destroys team content, and an untracked `CLAUDE.md` breaks `git pull` once a teammate commits one |
| Git-exclude via `.git/info/exclude`, one precise path per installed file | invisible to `git status`, shared by all worktrees, never committed | `.gitignore` (a tracked change); excluding all of `.claude/` (would hide the team's own new files) |
| Back up and replace `settings.local.json` | simple and fully reversible | JSON merge (needs jq/Python, unavailable on the server). Cost: "always allow" clicks during the event are dropped on `off` |
| Absolute hook paths, single-quoted, forward slashes | work the same from any cwd, in both checkouts, in Git Bash and in PowerShell | `$CLAUDE_PROJECT_DIR` (bash-only syntax; also wrong for the dev worktree, which must use the main hooks) |
| Dependency-free bash hooks (no jq/Python) | jq is missing on stock Ubuntu and Git Bash; Python is missing on stock Windows | PowerShell hooks for Windows (a second implementation, untestable here); Python hooks (see [roadmap.md](roadmap.md)) |
| Two enforcement layers (permission rules + guard) | rules are cheap and work even if a hook breaks; the guard understands context (current branch, path inside/outside the project, `.example` files) | rules only: prefix matching is easy to sidestep (`rm -rf /` vs `rm -fr /`) |
| Guard matches command **position** (`CB`), scrubs commit messages and heredoc bodies | `git commit -m "handle shutdown"` and READMEs written via heredoc stopped triggering false blocks | matching words anywhere |
| Recursive deletes allowed only inside the project or `/tmp` | `rm -rf node_modules` stays frictionless; `cd / && rm -rf usr` is caught via `cd` tracking | a blanket ban on `rm -rf` (constant friction) |
| State file in `.claude/hackmode/`, injected by hooks | one canonical copy for every session; survives `/clear` and compaction | `@import` from CLAUDE.md (external-import prompt in the worktree; loaded only at start) |
| Directory symlink for the dev worktree | atomic rewrites can't break it; relative paths work in both checkouts | per-file symlinks or hardlinks (break on rename-style writes); copies (diverge) |
| Phases as % of the event | the same model fits 24 h or 48 h events | fixed hour marks |
| `--deadline` keeps the start | moving the deadline shouldn't move the past | keeping the duration (first draft; the e2e test caught it) |
| `LC_ALL=C` for every date | identical English output on pt-BR servers | locale dates (the first e2e run printed "sáb 14 nov") |
| Budgets through `maxTurns` *and* a `BUDGET:` line | `maxTurns` is enforced; the line tells the agent to wrap up gracefully | prose only |
| `off` never force-deletes a dirty worktree and doesn't kill tmux | no lost work | the prototype's `worktree remove --force` / `rm -rf` and `kill-session` |

## Bugs the tests caught

- **A failed `=~` clears `BASH_REMATCH`.** The heredoc stripper read the delimiter *after* a second, failing regex test, so heredoc bodies were never stripped. Capture match groups immediately.
- **Quoted parts of a `[[ $x =~ … ]]` pattern match literally.** Build every regex in a variable and use it unquoted.
- **`set -e` traps:** `cond && cmd` as the last command makes a function fail when `cmd` fails (`rmdir` of a non-empty dir aborted `off`), and functions called inside `if` run with errexit silently disabled (so `setup_dev` now returns explicitly).
- **Classification order matters.** A repo under `/tmp` was classified as "tmp" before "project root", so `rm -rf <repo>` was allowed. Check the project root first.
- **Performance:** ten separate `grep` passes made a 1.5 MB write take 1.3 s. One combined pass, plus scanning `Write` payloads raw, brought it to 0.3 s without missing a secret at the end of the file.
- **Locale:** `date` follows `LANG`, hence `LC_ALL=C`.
- **Old `gh`:** Ubuntu's apt build (2.4.0) has no `gh issue pin`, so `/state` falls back to the GraphQL `pinIssue` mutation.
- **Line endings:** `.bat` must be CRLF and the hooks must stay LF (Git Bash), so both are pinned in `.gitattributes`. PowerShell 5.1 reads BOM-less scripts as ANSI, so the helper is kept ASCII-only.

## Verified vs. not verified

| Verified | How |
|---|---|
| Guard decisions | 160 table cases (`tests/guard_test.sh`) |
| `on`/re-run/`clock`/`tmux`/`status`/`off`, backups, exclude, dev worktree | 32 checks (`tests/e2e_test.sh`) with a fake `claude` and a real tmux |
| Clock nudges across all phases | scripted configs (IDEATE → BUILD → FREEZE → SUBMIT → OVER) |
| Claude Code accepts the settings | `claude doctor` (113 allow entries recognised) |
| End to end inside Claude | 2 live `claude -p` runs (Haiku, capped budgets) |
| **Not verified:** `hackmode.bat`, `lib/hackmode-win.ps1`, hooks under Git Bash on Windows | No Windows/PowerShell here. The files were reviewed by hand (parenthesis balance, CRLF, ASCII) |
| **Not verified:** `/build` with `isolation: worktree`, `/state` creating/pinning a real issue, auto/yolo autonomy | They need a GitHub remote and are side-effectful, so they weren't run in the sandbox |
