#!/usr/bin/env bash
# hackmode status line — countdown · phase · branch · context usage · model.
HM_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$HM_HOME/hooks/lib.sh"

INPUT="$(cat 2>/dev/null)"
hm_load_config || { echo "hackmode: no config"; exit 0; }
hm_clock

dir="$(json_str current_dir)"; [ -n "$dir" ] || dir="$PWD"
br="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
ctx=""
[[ $INPUT =~ \"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && ctx="${BASH_REMATCH[1]}%"
model="$(json_str display_name)"

R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' M=$'\e[35m' C=$'\e[36m' B=$'\e[1m' D=$'\e[2m' N=$'\e[0m'
case "$HM_PHASE" in
  IDEATE) pc=$C ;; BUILD) pc=$G ;; INTEGRATE) pc=$Y ;; FREEZE) pc=$M ;; SUBMIT|OVER) pc=$R ;; *) pc=$D ;;
esac
case "$HM_PHASE" in
  PRE-START) clock="starts in $(hm_dur $(( HACK_START - HM_NOW )))" ;;
  OVER)      clock="${R}${B}deadline passed${N}" ;;
  *)         clock="⏳ ${B}$(hm_dur "$HM_LEFT")${N} left ${D}(${HM_PCT}%)${N}" ;;
esac

line="🛰 HACKMODE │ $clock │ ${pc}${B}${HM_PHASE}${N}"
[ -n "$HM_NEXT" ] && line+="${D} → ${HM_NEXT} in $(hm_dur $(( HM_NEXT_AT - HM_NOW )))${N}"
if [ -n "$br" ]; then
  if [[ " ${HACK_PROTECTED_BRANCHES:-main master} " == *" $br "* ]]; then
    line+=" │ ${R}⎇ $br (no edits)${N}"
  else
    line+=" │ ⎇ $br"
  fi
fi
[ -n "$ctx" ] && line+=" │ ctx $ctx"
[ -n "$model" ] && line+=" │ ${D}${model}${N}"
printf '%s\n' "$line"
