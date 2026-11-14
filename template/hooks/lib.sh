# hackmode hook library — sourced by context.sh, guard.sh, statusline.sh and hackmode.sh.
# Pure bash (3.2+) + coreutils + git, so it runs on Linux, macOS and Git Bash on Windows
# (Claude Code runs hooks through Git Bash there). No jq/python needed.
# Callers set HM_HOME = the .claude/hackmode directory (config, HACKATHON_STATE.md, hooks/).

case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) HM_WIN=1 ;; *) HM_WIN=0 ;; esac

# Read .claude/hackmode/config (KEY=VALUE lines, never eval'd). Returns 1 if missing/invalid.
hm_load_config() {
  local f="$HM_HOME/config" k v
  [ -f "$f" ] || return 1
  while IFS='=' read -r k v || [ -n "$k" ]; do
    v="${v%$'\r'}"
    case "$k" in
      HACK_VERSION|HACK_EVENT|HACK_START|HACK_END|HACK_END_HUMAN|HACK_HOURS|HACK_LANG|HACK_AUTONOMY|HACK_PROTECTED_BRANCHES|HACK_MAIN_ROOT)
        printf -v "$k" '%s' "$v" ;;
    esac
  done < "$f"
  [[ ${HACK_START:-} =~ ^[0-9]+$ && ${HACK_END:-} =~ ^[0-9]+$ ]]
}

# Seconds → "31h05m" / "45m" (negative values keep their sign).
hm_dur() {
  local s="$1" sign=""
  if (( s < 0 )); then sign="-"; s=$(( -s )); fi
  local h=$(( s / 3600 )) m=$(( s % 3600 / 60 ))
  if (( h > 0 )); then printf '%s%dh%02dm' "$sign" "$h" "$m"; else printf '%s%dm' "$sign" "$m"; fi
}

# Phase model (% of the event elapsed): IDEATE <10 · BUILD <55 · INTEGRATE <80 · FREEZE <92 · SUBMIT <100.
# Sets HM_NOW HM_LEFT HM_PCT HM_PHASE HM_HINT HM_NEXT HM_NEXT_AT.
hm_clock() {
  HM_NOW=$(date +%s)
  local total=$(( HACK_END - HACK_START ))
  (( total > 0 )) || total=1
  local elapsed=$(( HM_NOW - HACK_START ))
  HM_LEFT=$(( HACK_END - HM_NOW ))
  HM_PCT=$(( elapsed * 100 / total ))
  local b1=$(( HACK_START + total * 10 / 100 )) b2=$(( HACK_START + total * 55 / 100 ))
  local b3=$(( HACK_START + total * 80 / 100 )) b4=$(( HACK_START + total * 92 / 100 ))
  HM_NEXT=""; HM_NEXT_AT=0
  if (( elapsed < 0 )); then
    HM_PHASE=PRE-START; HM_NEXT=IDEATE; HM_NEXT_AT=$HACK_START
    HM_HINT="Event not started: set up tools, accounts, the repo and data access only."
  elif (( HM_NOW < b1 )); then
    HM_PHASE=IDEATE; HM_NEXT=BUILD; HM_NEXT_AT=$b1
    HM_HINT="Pick ONE challenge, a 1-sentence value prop, a 3-step demo script, the NASA dataset and the mock data schema. Lock scope before BUILD."
  elif (( HM_NOW < b2 )); then
    HM_PHASE=BUILD; HM_NEXT=INTEGRATE; HM_NEXT_AT=$b2
    HM_HINT="Vertical slice first: data -> logic -> UI end-to-end on mocks, then real NASA data where cheap. Small PRs, merged often."
  elif (( HM_NOW < b3 )); then
    HM_PHASE=INTEGRATE; HM_NEXT=FREEZE; HM_NEXT_AT=$b3
    HM_HINT="Wire everything into the demo path, one command to run it, polish only what judges see. No features outside the demo script."
  elif (( HM_NOW < b4 )); then
    HM_PHASE=FREEZE; HM_NEXT=SUBMIT; HM_NEXT_AT=$b4
    HM_HINT="FEATURE FREEZE: demo-path bug fixes only. Record the demo video and write the submission (/pitch)."
  elif (( HM_LEFT > 0 )); then
    HM_PHASE=SUBMIT; HM_NEXT=""; HM_NEXT_AT=$HACK_END
    HM_HINT="SUBMIT NOW: submission form, public video/slides links, final README, tag a release. No risky merges."
  else
    HM_PHASE=OVER
    HM_HINT="The deadline has passed: only submission fixes, if the form still allows them."
  fi
}

# One-line clock, e.g. "[HACKMODE] Sat 14 Nov 10:32 | T-31h28m to deadline (Sun 15 Nov 18:00 -0300) | 34% elapsed | phase BUILD (INTEGRATE in 9h40m)"
hm_clock_line() {
  local line
  line="[HACKMODE] $(LC_ALL=C date '+%a %d %b %H:%M') | "
  case "$HM_PHASE" in
    PRE-START) line+="event starts in $(hm_dur $(( HACK_START - HM_NOW ))) | deadline ${HACK_END_HUMAN:-?}" ;;
    OVER)      line+="DEADLINE PASSED $(hm_dur $(( -HM_LEFT ))) ago (${HACK_END_HUMAN:-?})" ;;
    *)         line+="T-$(hm_dur "$HM_LEFT") to deadline (${HACK_END_HUMAN:-?}) | ${HM_PCT}% elapsed" ;;
  esac
  line+=" | phase $HM_PHASE"
  [ -n "$HM_NEXT" ] && line+=" ($HM_NEXT in $(hm_dur $(( HM_NEXT_AT - HM_NOW ))))"
  printf '%s\n' "$line"
}

hm_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || date +%s; }

# Normalise a path for comparisons: backslashes → slashes, /c/x → c:/x (Git Bash), lowercase drive letter.
hm_normpath() {
  local p="${1//\\//}" d
  if [ "$HM_WIN" = 1 ] && [[ $p =~ ^/([a-zA-Z])/(.*)$ ]]; then p="${BASH_REMATCH[1]}:/${BASH_REMATCH[2]}"; fi
  if [[ $p =~ ^([A-Za-z]):(.*)$ ]]; then
    d="$(printf '%s' "${BASH_REMATCH[1]}" | tr 'A-Z' 'a-z')"; p="$d:${BASH_REMATCH[2]}"
  fi
  while [ "${#p}" -gt 1 ] && [[ $p == */ ]] && ! [[ $p =~ ^[a-z]:/$ ]]; do p="${p%/}"; done
  printf '%s' "$p"
}

# First JSON string value of "$1" in $INPUT, unescaped. Good enough for Claude Code's hook payloads.
json_str() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\"" v
  [[ $INPUT =~ $re ]] || return 0
  v="${BASH_REMATCH[1]}"
  local bs='\' q='"' nl=$'\n' tab=$'\t' sl='/' ph=$'\001'
  v="${v//\\\\/$ph}"
  v="${v//\\\"/$q}"
  v="${v//\\n/$nl}"
  v="${v//\\t/$tab}"
  v="${v//\\\//$sl}"
  v="${v//$ph/$bs}"
  printf '%s' "$v"
}
