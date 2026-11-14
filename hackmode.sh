#!/usr/bin/env bash
# hackmode — switch Claude Code into "NASA Space Apps hackathon mode" for one git repo (Linux/macOS).
# Everything it writes is local to that repo and git-excluded; `hackmode off` restores the repo.
# Run `hackmode.sh help` for usage.
set -euo pipefail

HM_VERSION="1.0.0"
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
KIT="$(cd "$(dirname "$SELF")" && pwd)"
TPL="$KIT/template"
SESSION="${HACKMODE_TMUX_SESSION:-spaceapps}"
CLAUDE_BIN="${HACKMODE_CLAUDE:-claude}"
EX_BEGIN="# >>> hackmode (local-only files; removed by 'hackmode off') >>>"
EX_END="# <<< hackmode <<<"

if [ -t 1 ]; then B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' D=$'\e[2m' N=$'\e[0m'; else B="" G="" Y="" R="" D="" N=""; fi
ok()   { printf '%s[+]%s %s\n' "$G" "$N" "$*"; }
info() { printf '%s[*]%s %s\n' "$D" "$N" "$*"; }
warn() { printf '%s[!]%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
${B}hackmode${N} v$HM_VERSION — NASA Space Apps hackathon mode for Claude Code

${B}Usage:${N} hackmode.sh <command> [repo-path] [options]      (repo-path defaults to .)

${B}Commands${N}
  on        Enable hackathon mode in the repo (safe to re-run: refreshes files, keeps state + clock)
  off       Disable it and restore the repo (state + guard log archived to ~/.hackmode/archive)
  status    Mode, clock, phase, state file, dev worktree, tmux, guard blocks, gh login
  tmux      War room: tmux session '$SESSION' with Claude 'lead' (main checkout), Claude 'dev'
            (sibling worktree <repo>-dev) and an 'ops' shell — Claude starts with Remote Control
  clock     Show the clock, or move it: clock --deadline "2026-11-15 18:00"
  state     Print HACKATHON_STATE.md (--edit opens \$EDITOR)
  claude    Start Claude in the repo with the configured autonomy (extra claude args after --)
  install   Symlink this script to ~/.local/bin/hackmode

${B}Options${N} (on / clock)
  --start "YYYY-MM-DD HH:MM"     event start, local time          (default: now)
  --hours N                      event length in hours            (default: 48)
  --deadline "YYYY-MM-DD HH:MM"  submission deadline              (overrides start + hours)
  --event "NAME"                 default: NASA Space Apps Challenge
  --lang CODE                    team language for issues/PR comments (default: pt-BR)
  --autonomy MODE                allowlist (default) | auto | yolo
${B}Options${N} (tmux)  --no-dev   only the lead + ops windows
${B}Options${N} (off)   --force    also remove a dev worktree that has uncommitted changes

${B}Examples${N}
  hackmode.sh on ~/spaceapps --start "2026-11-14 09:00" --hours 48
  hackmode.sh tmux ~/spaceapps
  hackmode.sh clock ~/spaceapps --deadline "2026-11-15 18:00"
EOF
}

# ------------------------------------------------------------------ options
TARGET="."; O_START=""; O_HOURS=""; O_DEADLINE=""; O_EVENT=""; O_LANG=""; O_AUTONOMY=""
O_NODEV=0; O_FORCE=0; O_EDIT=0; PASS=()
parse_opts() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --*=*) local k="${1%%=*}" v="${1#*=}"; shift; set -- "$k" "$v" "$@"; continue ;;
      --start) O_START="${2:?--start needs a value}"; shift 2 ;;
      --hours) O_HOURS="${2:?--hours needs a value}"; shift 2 ;;
      --deadline) O_DEADLINE="${2:?--deadline needs a value}"; shift 2 ;;
      --event) O_EVENT="${2:?--event needs a value}"; shift 2 ;;
      --lang) O_LANG="${2:?--lang needs a value}"; shift 2 ;;
      --autonomy) O_AUTONOMY="${2:?--autonomy needs a value}"; shift 2 ;;
      --no-dev) O_NODEV=1; shift ;;
      --force) O_FORCE=1; shift ;;
      --edit) O_EDIT=1; shift ;;
      --) shift; PASS=("$@"); break ;;
      -h|--help) usage; exit 0 ;;
      -*) die "unknown option: $1 (see: hackmode.sh help)" ;;
      *) TARGET="$1"; shift ;;
    esac
  done
  if [ -n "$O_HOURS" ] && ! [[ $O_HOURS =~ ^[0-9]+$ && $O_HOURS -gt 0 ]]; then die "--hours must be a positive integer"; fi
  case "${O_AUTONOMY:-allowlist}" in allowlist|auto|yolo) ;; *) die "--autonomy must be allowlist, auto or yolo" ;; esac
  for v in "$O_EVENT" "$O_LANG"; do
    case "$v" in *$'\n'*|*=*) die "--event/--lang must be a single line without '='" ;; esac
  done
}

# ------------------------------------------------------------------ repo + config
resolve_repo() {
  [ -d "$TARGET" ] || die "no such directory: $TARGET"
  local top gcd
  top="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)" || die "$TARGET is not inside a git repository (clone the team repo first, or run 'git init')"
  ROOT="$(git -C "$top" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  [ -n "$ROOT" ] || ROOT="$top"
  [ "$top" = "$ROOT" ] || info "inside a linked worktree — using the main checkout $ROOT"
  case "$ROOT" in *[\'\"\\\#\&]*) die "the repo path contains a quote, backslash, # or & — move it to a plain path" ;; esac
  gcd="$(git -C "$ROOT" rev-parse --git-common-dir)"
  case "$gcd" in /*) ;; *) gcd="$ROOT/$gcd" ;; esac
  EXCLUDE="$(cd "$gcd" && pwd)/info/exclude"
  HM="$ROOT/.claude/hackmode"
  REPO="$(basename "$ROOT")"
  DEV="$(dirname "$ROOT")/$REPO-dev"
  HM_HOME="$HM"
  # shellcheck source=template/hooks/lib.sh
  . "$TPL/hooks/lib.sh"
}
load_cfg() { [ -f "$HM/config" ] && hm_load_config; }

to_epoch() {
  local e
  e="$(date -d "$1" +%s 2>/dev/null)" || e="$(date -j -f '%Y-%m-%d %H:%M' "$1" +%s 2>/dev/null)" \
    || die "can't parse date '$1' — use \"YYYY-MM-DD HH:MM\" (local time)"
  printf '%s' "$e"
}
human_time() { LC_ALL=C date -d "@$1" '+%a %d %b %H:%M %z' 2>/dev/null || LC_ALL=C date -r "$1" '+%a %d %b %H:%M %z'; }

# Sets C_START / C_END from the options, keeping the existing clock when no timing option is given.
#   --deadline D [--start S | --hours H]  → end = D; start = S, or D-H, or the existing start, or now
#   --start S [--hours H]                 → end = S + H (H defaults to the current length, else 48)
#   --hours H                             → keeps the start, end = start + H
compute_clock() {
  local now hours; now="$(date +%s)"
  hours="${O_HOURS:-}"
  if [ -z "$hours" ]; then
    if [ -n "${HACK_START:-}" ] && [ -n "${HACK_END:-}" ]; then hours=$(( (HACK_END - HACK_START + 1800) / 3600 )); else hours=48; fi
  fi
  if [ -n "$O_DEADLINE" ]; then
    C_END="$(to_epoch "$O_DEADLINE")"
    if [ -n "$O_START" ]; then C_START="$(to_epoch "$O_START")"
    elif [ -n "$O_HOURS" ]; then C_START=$(( C_END - O_HOURS * 3600 ))
    else C_START="${HACK_START:-$now}"; fi
  elif [ -n "$O_START" ]; then
    C_START="$(to_epoch "$O_START")"; C_END=$(( C_START + hours * 3600 ))
  elif [ -n "$O_HOURS" ]; then
    C_START="${HACK_START:-$now}"; C_END=$(( C_START + hours * 3600 ))
  else
    C_START="${HACK_START:-$now}"; C_END="${HACK_END:-$(( C_START + hours * 3600 ))}"
  fi
  (( C_END > C_START )) || die "the deadline must be after the start"
  C_HOURS=$(( (C_END - C_START + 1800) / 3600 ))
}

default_branch() {
  local b
  if b="$(git -C "$ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"; then printf '%s' "${b#origin/}"; return; fi
  for b in main master; do git -C "$ROOT" show-ref -q --verify "refs/remotes/origin/$b" && { printf '%s' "$b"; return; }; done
  for b in main master; do git -C "$ROOT" show-ref -q --verify "refs/heads/$b" && { printf '%s' "$b"; return; }; done
  printf 'main'
}

write_config() {
  cat > "$HM/config" <<EOF
HACK_VERSION=$HM_VERSION
HACK_EVENT=$EVENT
HACK_START=$C_START
HACK_END=$C_END
HACK_END_HUMAN=$(human_time "$C_END")
HACK_HOURS=$C_HOURS
HACK_LANG=$LANGV
HACK_AUTONOMY=$AUTONOMY
HACK_PROTECTED_BRANCHES=$PROTECTED
HACK_MAIN_ROOT=$ROOT
EOF
}

sed_esc() { printf '%s' "$1" | sed -e 's/[#&\\]/\\&/g'; }
render_state() {
  sed -e "s#__EVENT__#$(sed_esc "$EVENT")#g" -e "s#__DEADLINE__#$(sed_esc "$(human_time "$C_END")")#g" \
      -e "s#__HOURS__#$C_HOURS#g" -e "s#__LANG__#$(sed_esc "$LANGV")#g" \
      -e "s#__NOW__#$(LC_ALL=C date '+%a %d %b %H:%M')#g" "$TPL/HACKATHON_STATE.md"
}
update_state_deadline() {
  local f="$HM/HACKATHON_STATE.md" line
  [ -f "$f" ] || return 0
  line="- **Deadline:** $(human_time "$C_END") (${C_HOURS}h event)"
  sed -i.hmbak "s#^- \*\*Deadline:\*\* .*#$(sed_esc "$line")#" "$f" && rm -f "$f.hmbak"
}

# ------------------------------------------------------------------ installing files
# put SRC DST — copy a template file into place; on the first 'on', back up anything already there.
put() {
  local src="$1" dst="$2" key
  mkdir -p "$(dirname "$dst")"
  if [ "$ACTIVE" = 0 ] && [ -e "$dst" ]; then
    key="$(printf '%s' "$dst" | sed 's#[/:\\]#%#g')"
    if [ ! -e "$HM/backup/$key" ]; then
      cp -p "$dst" "$HM/backup/$key"
      printf '%s\t%s\n' "$key" "$dst" >> "$HM/backup/index"
      warn "backed up your existing ${dst#"$ROOT"/} (restored by 'hackmode off')"
    fi
  fi
  cp "$src" "$dst"
  grep -Fxq -- "$dst" "$HM/manifest" 2>/dev/null || printf '%s\n' "$dst" >> "$HM/manifest"
}

strip_block() { sed '/<!-- hackmode:start/,/<!-- hackmode:end -->/d'; }
write_doctrine() { # CLAUDE.local.md: our managed block on top, the user's own content (if any) kept below
  local f="$1" rest=""
  [ -f "$f" ] && rest="$(strip_block < "$f" | sed '/./,$!d')"
  { cat "$TPL/doctrine.md"; if [ -n "${rest//[[:space:]]/}" ]; then printf '\n%s\n' "$rest"; fi; } > "$f.hmtmp"
  mv "$f.hmtmp" "$f"
}
unwrite_doctrine() {
  local f="$1" rest
  [ -f "$f" ] || return 0
  rest="$(strip_block < "$f" | sed '/./,$!d')"
  if [ -z "${rest//[[:space:]]/}" ]; then rm -f -- "$f"; else printf '%s\n' "$rest" > "$f"; fi
}

# install_into CHECKOUT ADDITIONAL_DIRS_JSON — agents, skills, output style, settings, doctrine
install_into() {
  local dst="$1" add="$2" f n tmp
  for f in "$TPL"/agents/*.md; do put "$f" "$dst/.claude/agents/${f##*/}"; done
  for f in "$TPL"/skills/*/SKILL.md; do n="$(basename "$(dirname "$f")")"; put "$f" "$dst/.claude/skills/$n/SKILL.md"; done
  put "$TPL/output-styles/hackathon.md" "$dst/.claude/output-styles/hackathon.md"
  tmp="$(mktemp)"
  sed -e "s#__HOOKS__#$HM/hooks#g" -e "s#__ADDITIONAL_DIRS__#$add#g" "$TPL/settings.local.json" > "$tmp"
  put "$tmp" "$dst/.claude/settings.local.json"
  rm -f "$tmp"
  write_doctrine "$dst/CLAUDE.local.md"
}

strip_exclude() {
  [ -f "$EXCLUDE" ] || return 0
  sed -i.hmbak '/^# >>> hackmode/,/^# <<< hackmode/d' "$EXCLUDE" && rm -f "$EXCLUDE.hmbak"
}
write_exclude() {
  local f
  mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"
  strip_exclude
  if [ -s "$EXCLUDE" ] && [ -n "$(tail -c1 "$EXCLUDE")" ]; then echo >> "$EXCLUDE"; fi
  {
    printf '%s\n' "$EX_BEGIN" "/CLAUDE.local.md" "/.claude/hackmode" "/.claude/settings.local.json" \
      "/.claude/output-styles/hackathon.md" "/.claude/worktrees/"
    for f in "$TPL"/agents/*.md; do printf '/.claude/agents/%s\n' "${f##*/}"; done
    for f in "$TPL"/skills/*/; do printf '/.claude/skills/%s/\n' "$(basename "$f")"; done
    printf '%s\n' "$EX_END"
  } >> "$EXCLUDE"
}

# ------------------------------------------------------------------ commands
cmd_on() {
  resolve_repo
  [ -f "$TPL/doctrine.md" ] || die "template/ not found next to $SELF"
  ACTIVE=0; load_cfg && ACTIVE=1
  EVENT="${O_EVENT:-${HACK_EVENT:-NASA Space Apps Challenge}}"
  LANGV="${O_LANG:-${HACK_LANG:-pt-BR}}"
  AUTONOMY="${O_AUTONOMY:-${HACK_AUTONOMY:-allowlist}}"
  PROTECTED="$(printf '%s\n' main master "$(default_branch)" | awk 'NF && !seen[$0]++' | paste -sd' ' -)"
  compute_clock
  mkdir -p "$HM/hooks" "$HM/backup"
  cp "$TPL"/hooks/*.sh "$HM/hooks/"
  chmod +x "$HM"/hooks/*.sh
  write_config
  if [ ! -f "$HM/HACKATHON_STATE.md" ]; then
    render_state > "$HM/HACKATHON_STATE.md"
  else
    update_state_deadline
  fi
  install_into "$ROOT" "[]"
  [ -L "$DEV/.claude/hackmode" ] && install_into "$DEV" "[\"$HM\"]"
  write_exclude
  load_cfg; hm_clock

  printf '\n'
  ok "Hackathon mode ${B}ON${N} in $ROOT"
  printf '    %-9s %s → %s (%sh) · %s\n' clock "$(human_time "$C_START")" "$(human_time "$C_END")" "$C_HOURS" "$(hm_clock_line | sed 's/^\[HACKMODE\] [^|]*| //')"
  printf '    %-9s %s\n' autonomy "$AUTONOMY $(autonomy_note)"
  printf '    %-9s %s for issues / PR comments · English for judge-facing text\n' language "$LANGV"
  printf '    %-9s %s\n' protected "$PROTECTED (no edits, commits or pushes)"
  printf '    %-9s CLAUDE.local.md · .claude/{settings.local.json, agents, skills, output-styles, hackmode/} — all git-excluded\n' files
  preflight
  printf '\n%sNext%s\n' "$B" "$N"
  printf '  %s tmux %s        # war room: lead + dev Claude, Remote Control on\n' "$(self_name)" "$ROOT"
  printf '  or: cd %s && claude\n' "$ROOT"
  printf '  then in Claude: /state challenge: …; value prop: …; demo: 1) … 2) … 3) …\n'
}

autonomy_note() {
  case "$AUTONOMY" in
    auto) printf '(Claude Code auto mode — start Claude via "hackmode tmux/claude" so the flag is passed)' ;;
    yolo) printf '(no permission prompts — only the guard hook protects you; start via "hackmode tmux/claude")' ;;
    *) printf '(edits auto-approved off main; pre-approved dev commands; anything else asks)' ;;
  esac
}
self_name() { if command -v hackmode >/dev/null 2>&1; then printf 'hackmode'; else printf '%s' "$SELF"; fi; }

preflight() {
  command -v "$CLAUDE_BIN" >/dev/null 2>&1 || warn "claude CLI not found on PATH — install: curl -fsSL https://claude.ai/install.sh | bash"
  if command -v gh >/dev/null 2>&1; then
    gh auth status >/dev/null 2>&1 || warn "gh is not logged in — run: gh auth login (as Claude's GitHub account)"
  else
    warn "gh (GitHub CLI) not found — issues, PR reviews and the pinned state issue need it"
  fi
  git -C "$ROOT" remote get-url origin >/dev/null 2>&1 || warn "no 'origin' remote — pushes/PRs won't work until you add one"
  [ -n "$(git -C "$ROOT" config user.email 2>/dev/null)" ] || warn "git user.email not set — run: git config --global user.email <claude-account-email>"
}

cmd_off() {
  resolve_repo
  load_cfg || true
  # 1) dev worktree (only if it's ours: it has the hackmode symlink)
  if [ -L "$DEV/.claude/hackmode" ]; then
    remove_installed "$DEV"; unwrite_doctrine "$DEV/CLAUDE.local.md"; rm -f -- "$DEV/.claude/hackmode"; rmdir_empty "$DEV"
    if git -C "$ROOT" worktree remove "$DEV" 2>/dev/null; then
      ok "removed dev worktree $DEV (branch claude/dev kept)"
    elif [ "$O_FORCE" = 1 ]; then
      git -C "$ROOT" worktree remove --force "$DEV" && warn "force-removed dev worktree $DEV"
    else
      warn "dev worktree $DEV has uncommitted work — kept. Commit/push it, then: git worktree remove $DEV (or re-run with --force)"
    fi
  fi
  # 2) archive the state anchor + guard log
  if [ -f "$HM/HACKATHON_STATE.md" ]; then
    local arch; arch="$HOME/.hackmode/archive/$REPO-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$arch"; cp "$HM/HACKATHON_STATE.md" "$arch/"; [ -f "$HM/guard.log" ] && cp "$HM/guard.log" "$arch/"
    ok "archived state + guard log to $arch"
  fi
  # 3) remove installed files, restore backups, strip the doctrine block
  remove_installed "$ROOT"
  if [ -f "$HM/backup/index" ]; then
    local key orig
    while IFS=$'\t' read -r key orig; do
      [ -n "$key" ] && [ -f "$HM/backup/$key" ] || continue
      mkdir -p "$(dirname "$orig")"; cp -p "$HM/backup/$key" "$orig" && ok "restored ${orig#"$ROOT"/}"
    done < "$HM/backup/index"
  fi
  unwrite_doctrine "$ROOT/CLAUDE.local.md"
  case "$HM" in */.claude/hackmode) rm -rf -- "$HM" ;; esac
  rmdir_empty "$ROOT"
  strip_exclude
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$SESSION" 2>/dev/null; then
    info "tmux session '$SESSION' is still running — close it when you're done: tmux kill-session -t $SESSION"
  fi
  ok "Hackathon mode ${B}OFF${N} — Claude is back to normal in $ROOT"
}
remove_installed() { # delete the manifest entries that live under $1
  local root="$1" p
  [ -f "$HM/manifest" ] || return 0
  while IFS= read -r p; do
    case "$p" in "$root"/.claude/*) rm -f -- "$p" ;; esac
  done < "$HM/manifest"
}
rmdir_empty() {
  local r="$1" d
  for d in "$r"/.claude/skills/*/; do if [ -d "$d" ]; then rmdir "$d" 2>/dev/null || true; fi; done
  rmdir "$r/.claude/skills" "$r/.claude/agents" "$r/.claude/output-styles" 2>/dev/null || true
  rmdir "$r/.claude" 2>/dev/null || true
}

cmd_status() {
  resolve_repo
  if ! load_cfg; then printf 'hackmode: %sOFF%s in %s\n' "$Y" "$N" "$ROOT"; return 0; fi
  hm_clock
  local st="$HM/HACKATHON_STATE.md" age issue blocks last br
  age=$(( HM_NOW - $(hm_mtime "$st") ))
  issue="$(grep -oE 'State issue:\*\* *#[0-9]+' "$st" 2>/dev/null | grep -oE '#[0-9]+' || true)"
  br="$(git -C "$ROOT" symbolic-ref --short -q HEAD 2>/dev/null || echo detached)"
  printf 'hackmode %sON%s in %s (v%s)\n' "$G" "$N" "$ROOT" "${HACK_VERSION:-?}"
  printf '  %-9s %s\n' event "$HACK_EVENT"
  printf '  %-9s %s\n' clock "$(hm_clock_line | sed 's/^\[HACKMODE\] //')"
  printf '  %-9s %s\n' focus "$HM_HINT"
  printf '  %-9s %s · team language %s\n' autonomy "$HACK_AUTONOMY" "$HACK_LANG"
  printf '  %-9s .claude/hackmode/HACKATHON_STATE.md · updated %s ago · issue %s\n' state "$(hm_dur "$age")" "${issue:-not created yet}"
  printf '  %-9s %s (protected: %s)\n' branch "$br" "$HACK_PROTECTED_BRANCHES"
  if [ -d "$DEV" ]; then
    printf '  %-9s %s (%s)\n' dev "$DEV" "$(git -C "$DEV" symbolic-ref --short -q HEAD 2>/dev/null || echo '?')"
  else
    printf '  %-9s none (created by: hackmode tmux)\n' dev
  fi
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$SESSION" 2>/dev/null; then
    printf '  %-9s session %s running — attach: tmux attach -t %s\n' tmux "$SESSION" "$SESSION"
  else
    printf '  %-9s not running\n' tmux
  fi
  blocks=0; [ -f "$HM/guard.log" ] && blocks="$(wc -l < "$HM/guard.log" | tr -d ' ')"
  last=""; [ -f "$HM/guard.log" ] && last="$(tail -n 1 "$HM/guard.log" | cut -f1,3 | tr '\t' ' ' | cut -c1-110)"
  printf '  %-9s %s block(s)%s\n' guard "$blocks" "${last:+ · last: $last}"
  if command -v gh >/dev/null 2>&1; then
    local who; who="$(gh api user --jq .login 2>/dev/null || true)"
    printf '  %-9s %s\n' github "${who:+logged in as $who}${who:-not logged in (gh auth login)}"
  fi
}

cmd_clock() {
  resolve_repo
  load_cfg || die "hackmode is off in $ROOT — run: hackmode.sh on $ROOT"
  if [ -n "$O_START$O_HOURS$O_DEADLINE" ]; then
    EVENT="$HACK_EVENT"; LANGV="$HACK_LANG"; AUTONOMY="$HACK_AUTONOMY"; PROTECTED="$HACK_PROTECTED_BRANCHES"
    compute_clock; write_config; update_state_deadline; load_cfg
    ok "clock updated: $(human_time "$C_START") → $(human_time "$C_END") (${C_HOURS}h)"
  fi
  hm_clock; hm_clock_line; printf 'Phase focus: %s\n' "$HM_HINT"
}

cmd_state() {
  resolve_repo
  [ -f "$HM/HACKATHON_STATE.md" ] || die "no state file — run: hackmode.sh on $ROOT"
  if [ "$O_EDIT" = 1 ]; then "${EDITOR:-nano}" "$HM/HACKATHON_STATE.md"; else cat "$HM/HACKATHON_STATE.md"; fi
}

# Claude command line for the configured autonomy (+ Remote Control when the CLI supports it).
claude_args() { # $1 = remote-control session name ("" = none)
  local help
  CLAUDE_ARGS=("$CLAUDE_BIN")
  case "${HACK_AUTONOMY:-allowlist}" in
    auto) CLAUDE_ARGS+=(--permission-mode auto) ;;
    yolo) CLAUDE_ARGS+=(--dangerously-skip-permissions) ;;
    *) CLAUDE_ARGS+=(--permission-mode acceptEdits) ;;
  esac
  if [ -n "$1" ]; then
    help="$("$CLAUDE_BIN" --help 2>/dev/null || true)"
    if [[ $help == *--remote-control* ]]; then CLAUDE_ARGS+=(--remote-control "$1"); else warn "this claude version has no --remote-control flag — starting without it"; fi
  fi
}

cmd_claude() {
  resolve_repo
  load_cfg || die "hackmode is off in $ROOT — run: hackmode.sh on $ROOT"
  claude_args ""
  cd "$ROOT"
  exec "${CLAUDE_ARGS[@]}" ${PASS[@]+"${PASS[@]}"}
}

setup_dev() {
  if [ ! -d "$DEV" ]; then
    git -C "$ROOT" rev-parse -q --verify HEAD >/dev/null || { warn "the repo has no commits yet — skipping the dev worktree"; return 1; }
    git -C "$ROOT" fetch -q origin 2>/dev/null || warn "git fetch failed — the dev worktree starts from local refs"
    local def base; def="$(default_branch)"
    if git -C "$ROOT" show-ref -q --verify "refs/remotes/origin/$def"; then base="origin/$def"; else base="HEAD"; fi
    if git -C "$ROOT" show-ref -q --verify refs/heads/claude/dev; then
      git -C "$ROOT" worktree add -q "$DEV" claude/dev || { warn "could not create the dev worktree at $DEV"; return 1; }
    else
      git -C "$ROOT" worktree add -q -b claude/dev "$DEV" "$base" || { warn "could not create the dev worktree at $DEV"; return 1; }
    fi
    ok "created dev worktree $DEV (branch claude/dev from $base)"
  fi
  mkdir -p "$DEV/.claude" || return 1
  if [ ! -e "$DEV/.claude/hackmode" ]; then ln -s "$HM" "$DEV/.claude/hackmode" || return 1; fi
  ACTIVE=1 install_into "$DEV" "[\"$HM\"]"
}

cmd_tmux() {
  command -v tmux >/dev/null 2>&1 || die "tmux is not installed (sudo apt install tmux)"
  resolve_repo
  if ! load_cfg; then warn "hackmode is off here — enabling it with defaults (clock starts now, 48h)"; cmd_on; fi
  load_cfg
  if tmux has-session -t "$SESSION" 2>/dev/null; then info "attaching to the running session '$SESSION'"; tmux_attach; return; fi
  local dev_ok=0 wins="lead"
  if [ "$O_NODEV" = 0 ] && setup_dev; then dev_ok=1; wins+=" · dev"; fi
  tmux new-session -d -s "$SESSION" -n lead -c "$ROOT"
  claude_args "$REPO-lead"; tmux send-keys -t "$SESSION:lead" "$(printf '%q ' "${CLAUDE_ARGS[@]}")" C-m
  if [ "$dev_ok" = 1 ]; then
    tmux new-window -t "$SESSION" -n dev -c "$DEV"
    claude_args "$REPO-dev"; tmux send-keys -t "$SESSION:dev" "$(printf '%q ' "${CLAUDE_ARGS[@]}")" C-m
  fi
  tmux new-window -t "$SESSION" -n ops -c "$ROOT"
  tmux send-keys -t "$SESSION:ops" "$(printf '%q' "$SELF") status" C-m
  tmux select-window -t "$SESSION:lead"
  ok "tmux session '$SESSION': $wins · ops (switch windows: Ctrl-b n, detach: Ctrl-b d)"
  tmux_attach
}
tmux_attach() {
  [ "${HACKMODE_NO_ATTACH:-0}" = 1 ] && return 0
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "$SESSION"; else tmux attach-session -t "$SESSION"; fi
}

cmd_install() {
  mkdir -p "$HOME/.local/bin"
  ln -sf "$SELF" "$HOME/.local/bin/hackmode"
  ok "installed: ~/.local/bin/hackmode → $SELF"
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "~/.local/bin is not on PATH — add to ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac
}

main() {
  local cmd="${1:-help}"
  [ $# -gt 0 ] && shift
  parse_opts "$@"
  case "$cmd" in
    on) cmd_on ;; off) cmd_off ;; status) cmd_status ;; tmux) cmd_tmux ;; clock) cmd_clock ;;
    state) cmd_state ;; claude) cmd_claude ;; install) cmd_install ;;
    help|-h|--help) usage ;;
    *) usage; die "unknown command: $cmd" ;;
  esac
}
main "$@"
