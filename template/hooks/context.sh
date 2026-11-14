#!/usr/bin/env bash
# hackmode context hook — keeps Claude anchored to the hackathon clock and state.
#   context.sh session : SessionStart     → clock, role, phase focus + the full HACKATHON_STATE.md
#   context.sh prompt  : UserPromptSubmit → one-line clock + nudges (phase change, stale state, open scope)
#   context.sh brief   : skills/subagents → clock + phase focus + state (no nudges, doesn't read stdin)
# Plain stdout is added to Claude's context. Always exits 0, so it can never block a prompt.
HM_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$HM_HOME/hooks/lib.sh"

mode="${1:-prompt}"
case "$mode" in session|prompt) cat >/dev/null 2>&1 ;; esac   # drain the hook's JSON payload (unused)
hm_load_config || exit 0
hm_clock

STATE="$HM_HOME/HACKATHON_STATE.md"
age=0
[ -f "$STATE" ] && age=$(( HM_NOW - $(hm_mtime "$STATE") ))

print_state() {
  if [ -f "$STATE" ]; then
    printf '===== HACKATHON_STATE.md (last updated %s ago) =====\n' "$(hm_dur "$age")"
    head -c 8000 "$STATE"
    printf '\n===== end of state =====\n'
  else
    printf '(state file missing: %s — recreate it with /state)\n' "$STATE"
  fi
}

role_line() {
  local here main
  here="$(hm_normpath "${CLAUDE_PROJECT_DIR:-$PWD}")"
  main="$(hm_normpath "${HACK_MAIN_ROOT:-}")"
  [ -n "$main" ] || return 0
  if [ "$here" = "$main" ]; then
    if [ -d "$main-dev" ]; then
      printf 'Session role: LEAD (main checkout %s). A DEV session may be working in %s-dev — never switch branches there.\n' "$main" "$main"
    else
      printf 'Session role: LEAD (main checkout %s).\n' "$main"
    fi
  else
    printf 'Session role: DEV (worktree %s). The LEAD session owns the main checkout %s — never switch branches there.\n' "$here" "$main"
  fi
}

case "$mode" in
  session)
    printf '[HACKMODE ACTIVE] %s — hackathon mode is ON in this repo (doctrine: CLAUDE.local.md · output style: Hackathon · guard hook armed).\n' "${HACK_EVENT:-Hackathon}"
    hm_clock_line
    printf 'Phase focus: %s\n' "$HM_HINT"
    role_line
    printf 'Team language for issues/PR comments: %s. State anchor: .claude/hackmode/HACKATHON_STATE.md (%s) — keep it current with /state.\n' "${HACK_LANG:-en}" "$STATE"
    print_state
    ;;
  brief)
    hm_clock_line
    printf 'Phase focus: %s\n' "$HM_HINT"
    print_state
    ;;
  *)
    hm_clock_line
    last=""
    [ -f "$HM_HOME/.phase" ] && last="$(cat "$HM_HOME/.phase" 2>/dev/null)"
    if [ "$last" != "$HM_PHASE" ]; then
      printf '%s' "$HM_PHASE" > "$HM_HOME/.phase" 2>/dev/null
      [ -n "$last" ] && printf '⚠ PHASE CHANGE %s → %s: %s Tell the user and re-plan accordingly.\n' "$last" "$HM_PHASE" "$HM_HINT"
    fi
    case "$HM_PHASE" in
      PRE-START|OVER) ;;
      *)
        if [ -f "$STATE" ] && [ "$age" -ge 10800 ]; then
          printf '⚠ HACKATHON_STATE.md was last updated %s ago — after this task, record progress and decisions with /state.\n' "$(hm_dur "$age")"
        fi
        if [ "$HM_PHASE" != IDEATE ] && grep -Eq '^- \*\*(Challenge|Value prop[^*]*):\*\* \[TBD\]' "$STATE" 2>/dev/null; then
          printf '⚠ Challenge / value prop are still [TBD] — lock the scope now and record it with /state.\n'
        fi
        if [ "$HM_LEFT" -gt 0 ] && [ "$HM_LEFT" -lt 3600 ]; then
          printf '⏰ Less than 1 hour left: only submission-critical work.\n'
        fi
        ;;
    esac
    ;;
esac
exit 0
