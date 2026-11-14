# Roadmap

## Should hackmode move from bash to Python?

**Short answer:** it can, and once you want several modes it should. Port the installer first, the hooks second, and only after the hackathon. Rewriting a tested safety component mid-event is exactly what the doctrine forbids.

Bash was the right call for v1. It runs everywhere hackmode runs with zero installs: Linux, macOS, and Git Bash on Windows, which Claude Code already needs for hooks. The bash hooks are tested end to end. Its costs show up as the project grows:
- the installer exists twice (bash, and batch + PowerShell), and the Windows copy has never run;
- JSON and shell quoting are approximated with regexes;
- modes can't be described as data.

### Comparison

| | bash (v1) | Python (stdlib only) |
|---|---|---|
| Available out of the box | Linux/macOS: always. Windows: via Git Bash | Linux: almost always (`python3`). macOS: via Xcode tools. **Windows: no**, and `python3` may be a Microsoft Store stub |
| Windows installer | second implementation (batch + PowerShell helper), never executed | same code path as Linux, testable in CI |
| JSON | regex extraction (`json_str`); `settings.local.json` is replaced, not merged | `json`: exact parsing; real merges keep your "always allow" approvals |
| Shell tokenization in the guard | `read -ra` ignores quotes; `bash -c "…"` content only partly inspected | `shlex.split` handles POSIX quoting and can recurse into `-c` strings |
| Dates | GNU `date` vs. BSD `date` vs. PowerShell | `datetime` everywhere |
| Modes as data | no JSON parser → engine strings hardcoded | `mode.json` → one engine, many modes |
| Tests | custom harness (needs `python3` anyway) | `pytest` + a CI matrix (Ubuntu, macOS, Windows) |
| Hook latency, Linux (measured) | guard 18–37 ms, context hook 13 ms | interpreter start 21 ms; JSON + shlex + one `git` call ≈ 36 ms |
| Hook latency, Windows | unmeasured: each `$(…)`, `grep` and `sed` is a slow Git Bash process spawn, and the guard spawns 10+ | one process + `git` |
| Failure mode | `bash` is always there | if the pinned interpreter disappears, hooks error, so it must be designed fail-closed |
| Readability | regex-heavy; `set -e` and `BASH_REMATCH` pitfalls | clearer, and the same language as the team's agentkit |

### Plan

1. **Now:** freeze v1 for the event.
2. **Port the installer** to a stdlib-only `devmode.py` (Python ≥ 3.9).
   - Keep `hackmode.sh` / `hackmode.bat` as ~10-line shims. They find Python (`python3`, `py -3`, `python`, skipping the Store stub) or print an install hint. This keeps the bash + batch entry points.
   - Delete the batch logic and `hackmode-win.ps1`.
   - Merge `settings.local.json` with `json` instead of backup/replace.
   - Introduce `modes/<name>/mode.json` ([creating-a-mode.md](creating-a-mode.md) §4).
3. **Port the hooks** to stdlib-only Python.
   - Run them through the interpreter path pinned at install time (`sys.executable`, written into the settings), so "is Python installed?" is answered once by the installer.
   - The phase model lives in one module shared with the CLI.
   - Make the guard fail-closed: `"<python>" guard.py || exit 2`. A missing interpreter or a crash then blocks with a visible error instead of silently allowing.
4. **Port the tests.** The 160-case table becomes a parametrised `pytest` data file. Add a GitHub Actions matrix including `windows-latest`, which closes the "Windows never executed" gap for good.

### Why not Node, Go or PowerShell 7?
- **Node** isn't installed by Claude Code's native installer.
- **Go** gives a zero-dependency binary, but needs a build and release pipeline; that's overkill for templates plus small scripts.
- **PowerShell 7** is rarely installed on Linux servers.

## Known limitations of v1

| Priority | Limitation | Planned fix |
|---|---|---|
| P1 | `hackmode.bat` and its helper were never executed | Python port + Windows CI (or a manual run on a scratch repo) |
| P1 | `settings.local.json` is replaced: approvals clicked during the event are lost on re-run/`off` | JSON merge |
| P2 | the guard's tokenizer ignores quotes (paths with spaces split; `bash -c` strings partly inspected) | `shlex` |
| P2 | hooks fail **open** if `bash` or the hook file is missing (any exit code other than 2 is non-blocking) | `… \|\| exit 2` (fail-closed) |
| P2 | mode-specific strings live in engine files | `mode.json` refactor |
| P3 | dev worktree is Linux-only (directory symlink) | Windows: directory junction (`mklink /J`) |
| P3 | `/build` (isolation worktree), `/state` creating/pinning a real issue, and `auto`/`yolo` autonomy weren't exercised live | sandbox GitHub repo test run |
| P3 | broad allowlist (`curl`, `python`, `rm`): the guard is the real safety net | per-mode allowlists |
| P3 | the phase model is duplicated in `hackmode-win.ps1` | single source (Python) |

## Ideas
- **`devmode doctor`**: checks claude and gh login, folder trust, `claude doctor`, the hook interpreter and the Git Bash path in one command.
- **Modes as Claude Code plugins.** A plugin bundles agents, skills, hooks and output styles, and namespaces commands (`/hackmode:state`), so they can't collide with a team's own skills. The installer would only write config and state and enable the plugin. Evaluate support across Claude Code versions first.
- **Two-way state sync:** pull edits teammates make in the pinned issue back into `HACKATHON_STATE.md`.
- **Subagent clock:** inject the clock into every subagent automatically if a subagent-start hook can add context, instead of relying on each agent running `context.sh brief`.
