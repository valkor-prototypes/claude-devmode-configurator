#!/usr/bin/env bash
# hackmode guard — Claude Code PreToolUse hook for Bash | PowerShell | Edit | Write | MultiEdit | NotebookEdit.
# Deterministic last line of defence (the model can't talk its way past it):
#   exit 2 → the tool call is blocked and the reason (stderr) is shown to Claude
#   exit 0 → no objection (the normal permission rules still apply)
# Dependency-free on purpose (bash + grep + git) so it also runs in Git Bash on Windows.
# Every block is logged to .claude/hackmode/guard.log.
HM_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$HM_HOME/hooks/lib.sh"
hm_load_config >/dev/null 2>&1 || true

INPUT="$(cat)"
TOOL="$(json_str tool_name)"
CWD="$(hm_normpath "$(json_str cwd)")"
[ -n "$CWD" ] || CWD="$(hm_normpath "$PWD")"
ROOT="$(hm_normpath "${CLAUDE_PROJECT_DIR:-}")"
[ -n "$ROOT" ] || ROOT="$(hm_normpath "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)")"
PROTECTED=" ${HACK_PROTECTED_BRANCHES:-main master} "
PROT_RE="$(printf '%s' "${HACK_PROTECTED_BRANCHES:-main master}" | sed -e 's/[.]/\\./g' -e 's/  */|/g')"

block() { # $1 reason · $2 offending text (logged) · $3 what to do instead
  local snip
  snip="$(printf '%s' "${2:-}" | tr '\n\t' '  ' | cut -c1-200)"
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${TOOL:-?}" "$1" "$snip" >> "$HM_HOME/guard.log" 2>/dev/null
  printf 'hackmode guard BLOCKED this %s call: %s.\n' "${TOOL:-tool}" "$1" >&2
  [ -n "${3:-}" ] && printf 'Do instead: %s\n' "$3" >&2
  printf 'This is a deterministic safety hook: do not retry variants of this command; take the safer path or ask the human.\n' >&2
  exit 2
}

current_branch() { git -C "${1:-$CWD}" symbolic-ref --short -q HEAD 2>/dev/null; }
is_protected() { [ -n "$1" ] && [[ $PROTECTED == *" $1 "* ]]; }
strip_quotes() { local t="$1"; t="${t#\"}"; t="${t%\"}"; t="${t#\'}"; t="${t%\'}"; printf '%s' "$t"; }

# Split a command line into simple commands (one per line) on && || ; | & and newlines.
split_cmds() {
  local s="$1" nl=$'\n'
  s="${s//&&/$nl}"; s="${s//||/$nl}"; s="${s//;/$nl}"; s="${s//|/$nl}"; s="${s//&/$nl}"
  printf '%s\n' "$s"
}

# Classify a path token: ok tmp cwd root home parent git var outside
classify_path() {
  local t h td
  t="$(strip_quotes "$1")"
  case "$t" in
    "") echo ok; return ;;
    /|/\*|/.|//) echo root; return ;;
    '~'|'~/'|'~/*'|'$HOME'|'$HOME/'|'$HOME/*'|'${HOME}'|'${HOME}/'|'${HOME}/*') echo home; return ;;
    .|./|./\*|\*|.\*|\*.\*) echo cwd; return ;;
    ..|../|../\*) echo parent; return ;;
    .git|.git/|.git/\*|*/.git|*/.git/|*/.git/\*) echo git; return ;;
  esac
  if [[ $t =~ (^|/)\.\.(/|$) ]]; then echo parent; return; fi
  case "$t" in
    '~/'*) t="$HOME/${t#'~/'}" ;;
    '$HOME/'*) t="$HOME/${t#'$HOME/'}" ;;
    '${HOME}/'*) t="$HOME/${t#'${HOME}/'}" ;;
  esac
  case "$t" in \$*|*'$('*|*'`'*) echo var; return ;; esac
  t="$(hm_normpath "$t")"
  if [[ $t == /* || $t =~ ^[a-z]:/ ]]; then
    if [ -n "$ROOT" ]; then
      if [ "$t" = "$ROOT" ]; then echo cwd; return; fi
      case "$t" in
        "$ROOT"/.git|"$ROOT"/.git/*) echo git; return ;;
        "$ROOT"/*) echo ok; return ;;
      esac
    fi
    case "$t" in /tmp/?*|/var/tmp/?*) echo tmp; return ;; esac
    if [ -n "${TMPDIR:-}" ]; then
      td="$(hm_normpath "$TMPDIR")"
      if [[ $t == "$td"/?* ]]; then echo tmp; return; fi
    fi
    h="$(hm_normpath "$HOME")"
    if [ "$t" = "$h" ]; then echo home; return; fi
    echo outside; return
  fi
  echo ok
}
describe() {
  case "$1" in
    root) echo "the filesystem root" ;; home) echo "your home directory" ;; cwd) echo "the whole project/current directory" ;;
    parent) echo "a path outside the project (..)" ;; git) echo "git history (.git)" ;;
    var) echo "an unexpanded variable or subshell path" ;; outside) echo "a path outside the project" ;; *) echo "$1" ;;
  esac
}

# ---------------------------------------------------------------- shell commands
# Regex building blocks. CB = start of a simple command, after optional wrappers (env, nohup, timeout 30, FOO=1 …),
# so words inside arguments ("echo use sudo") don't trigger. B = any word boundary. E = end of a word.
B='(^|[;&|({`[:space:]]|\$\()'
CB='(^|[;&|({`]|\$\()[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*|env|nohup|time|exec|xargs|nice|command|builtin|timeout|[0-9]+[smhd]?|-[A-Za-z-]+)[[:space:]]+)*'
E='([[:space:]]|$|[;&|)])'
G="$CB"'git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+|[[:space:]]+--[a-z-]+(=[^[:space:]]+)?)*[[:space:]]+'

# Remove heredoc bodies (unless fed to a shell) so prose written into files can't trigger rules.
strip_heredocs() {
  local line t out="" delim="" nl=$'\n'
  local re='(^|[^<])<<-?[[:space:]]*["'"'"']?([A-Za-z_][A-Za-z0-9_]*)'
  local shre='(^|[;&|[:space:]])(ba|z|da|k)?sh([[:space:]]+-[a-z]+)*[[:space:]]*<<'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$delim" ]; then
      t="${line#"${line%%[![:space:]]*}"}"
      if [ "$t" = "$delim" ]; then delim=""; out+="$line$nl"; fi
      continue
    fi
    out+="$line$nl"
    if [[ $line =~ $re ]]; then
      t="${BASH_REMATCH[2]}"                 # read it before the next =~ resets BASH_REMATCH
      [[ $line =~ $shre ]] || delim="$t"
    fi
  done <<< "$1"
  printf '%s' "$out"
}
# Replace commit/PR/issue message arguments with MSG.
scrub_messages() {
  printf '%s' "$1" | sed -E \
    -e 's/(^|[[:space:]])(-m|--message|--title|--body|--notes)([[:space:]]+|=)"([^"\\]|\\.)*"/\1\2 MSG/g' \
    -e "s/(^|[[:space:]])(-m|--message|--title|--body|--notes)([[:space:]]+|=)'[^']*'/\1\2 MSG/g"
}

rule() { [[ $CMD_NORM =~ $1 ]] && block "$2" "$CMD" "${3:-}"; return 0; }

check_rules() {
  local Q='["'"'"']'
  # privilege, power, disks, processes
  rule "$CB"'(sudo|doas|pkexec)'"$E" "privilege escalation (sudo/doas)" "ask the human to run it in their own shell"
  rule "$CB"'su'"$E" "switching user (su)" "ask the human"
  rule '(^|[[:space:]])(-c|eval)[[:space:]]+'"$Q"'?[[:space:]]*(sudo|doas|su|mkfs|shutdown|reboot|poweroff|halt)'"$E" "privileged/power command inside a shell string" "ask the human"
  rule "$CB"'(mkfs(\.[a-z0-9]+)?|wipefs|fdisk|sfdisk|cfdisk|parted|gdisk|shred|diskutil|diskpart)'"$E" "a disk-level command" "ask the human"
  rule "$CB"'dd[[:space:]][^;&|]*of=/dev/' "dd onto a device"
  rule '>[[:space:]]*/dev/(sd|nvme|hd|vd|xvd|mmcblk|disk)' "writing to a raw disk device"
  rule "$CB"'(shutdown|reboot|poweroff|halt|init[[:space:]]+[06])'"$E" "changing the machine's power state" "ask the human"
  rule "$CB"'(systemctl|loginctl)[[:space:]]+(poweroff|reboot|halt|suspend|hibernate|kexec)' "changing the machine's power state" "ask the human"
  rule ':\(\)[[:space:]]*\{' "a fork bomb"
  rule "$CB"'kill[[:space:]]+([^;&|]*[[:space:]])?-1'"$E" "kill -1 (signals every process you own)" "kill specific PIDs (find them with: lsof -i :PORT)"
  rule "$CB"'(pkill|killall)[[:space:]]([^;&|]*[[:space:]])?-u[[:space:]]' "killing every process of a user" "kill specific PIDs"
  rule "$CB"'(chmod|chown|chgrp)[[:space:]]+([^;&|]*[[:space:]])?(-[A-Za-z]*R[A-Za-z]*|--recursive)[[:space:]]+([^;&|]*[[:space:]])?'"$Q"'?(/|~/?|\$HOME/?)'"$Q"'?'"$E" "a recursive permission change on / or ~"
  rule '(Format-Volume|Clear-Disk|Initialize-Disk|Remove-Partition|Stop-Computer|Restart-Computer)' "a PowerShell disk/power command" "ask the human"
  # remote code execution
  rule '(curl|wget|fetch|iwr|irm|Invoke-WebRequest|Invoke-RestMethod)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k|fi)?sh'"$E" "piping a download into a shell" "download the script, read it, and ask the human to run installers"
  rule '(curl|wget)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(python3?|node|perl|ruby|php)'"$E" "piping a download into an interpreter" "download to a file first and inspect it"
  rule '(ba|z)?sh[[:space:]]+(-c[[:space:]]+)?'"$Q"'?(<\(|\$\()[[:space:]]*(curl|wget)' "executing a downloaded script" "download the script, read it, and ask the human"
  rule '(iex|Invoke-Expression)[^;|]*(DownloadString|iwr|irm|Invoke-WebRequest|Invoke-RestMethod)|(DownloadString|iwr|irm|Invoke-WebRequest|Invoke-RestMethod)[^;]*\|[[:space:]]*(iex|Invoke-Expression)' "PowerShell download-and-execute" "ask the human"
  # git history & working tree destruction
  rule "$G"'reset[[:space:]]([^;&|]*[[:space:]])?--hard' "git reset --hard (destroys uncommitted work)" "git stash, or commit to a claude/* branch first"
  rule "$G"'clean[[:space:]]([^;&|]*[[:space:]])?(-[a-zA-Z]*[fxX][a-zA-Z]*|--force)'"$E" "git clean -f (deletes untracked files)" "delete specific files explicitly"
  rule "$G"'(filter-branch|filter-repo)'"$E" "rewriting git history"
  rule "$G"'reflog[[:space:]]+(expire|delete)' "destroying the reflog"
  rule "$G"'update-ref[[:space:]]+(-d|--delete)' "deleting git refs"
  rule "$G"'branch[[:space:]]([^;&|]*[[:space:]])?(-D|-d|--delete)[[:space:]]+([^;&|]*[[:space:]])?('"$PROT_RE"')'"$E" "deleting a protected branch"
  rule "$G"'add[[:space:]]+([^;&|]*[[:space:]])?(-A|--all|-f|--force|\.|:/|\*)'"$E" "a broad or forced 'git add' (could commit .env, data dumps or hackmode files)" "stage explicit paths: git add path/to/file1 path/to/file2"
  rule "$G"'commit[[:space:]]+([^;&|]*[[:space:]])?(-a|--all|-[b-zA-Z]*a[a-zA-Z]*)'"$E" "'git commit -a' (stages everything)" "git add <explicit paths> && git commit -m \"...\""
  # GitHub
  rule "$CB"'gh[[:space:]]+pr[[:space:]]+merge' "merging a PR (humans merge)" "leave the PR for a teammate to review and merge"
  rule "$CB"'gh[[:space:]]+repo[[:space:]]+(delete|archive|rename|edit)' "changing or deleting the GitHub repository"
  rule "$CB"'gh[[:space:]]+(secret|ssh-key|gpg-key)[[:space:]]' "touching GitHub secrets/keys"
  rule "$CB"'gh[[:space:]]+auth[[:space:]]+(token|logout|refresh|login)' "touching GitHub credentials"
  rule "$CB"'gh[[:space:]]+release[[:space:]]+delete' "deleting a release"
  rule "$CB"'gh[[:space:]]+issue[[:space:]]+(delete|transfer)' "deleting/transferring issues" "close it with a comment instead"
  rule "$CB"'gh[[:space:]]+api[[:space:]]([^;&|]*[[:space:]])?(-X|--method)[[:space:]=]*'"$Q"'?[Dd][Ee][Ll][Ee][Tt][Ee]' "a DELETE through the GitHub API"
  # docker, publishing
  rule "$CB"'docker[[:space:]]+(system|volume|image|container|builder|network)[[:space:]]+prune' "docker prune"
  rule "$CB"'docker[[:space:]]+volume[[:space:]]+rm' "deleting docker volumes"
  rule "$CB"'docker[[:space:]]+run[[:space:]]([^;&|]*[[:space:]])?(-v|--volume)[[:space:]=]+'"$Q"'?/:' "mounting the host root into a container"
  rule "$CB"'(npm|pnpm|yarn|bun)[[:space:]]+publish' "publishing a package"
  rule "$CB"'(twine[[:space:]]+upload|cargo[[:space:]]+publish|gem[[:space:]]+push)' "publishing a package"
  # credentials, environment dumps, system files, hackmode's own files
  rule '(\.ssh/id_|\.aws/credentials|\.config/gh/hosts\.yml|\.git-credentials|\.netrc|\.claude/\.credentials|\.docker/config\.json|\.kube/config)' "touching a credential store" "never read or copy credential files"
  rule "$CB"'(printenv|env|set|export[[:space:]]+-p)[[:space:]]*($|[;&|>)])' "dumping every environment variable (they include tokens)" "print one variable: printenv NAME"
  rule '(>|[[:space:]]tee[[:space:]]+(-a[[:space:]]+)?)[[:space:]]*'"$Q"'?(/etc/|/usr/|/boot/|/bin/|/sbin/|~/\.ssh/|\$HOME/\.ssh/)' "writing to system or SSH files" "ask the human"
  rule "$CB"'crontab[[:space:]]+-r' "deleting the crontab"
  rule '(>|[[:space:]]tee[[:space:]]+(-a[[:space:]]+)?|sed[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-i|(^|[[:space:];&|])(rm|mv|cp|ln|install|truncate)[[:space:]][^;&|]*)[^;&|]*(\.claude/hackmode/(config|hooks)|\.claude/hackmode'"$Q"'?([[:space:]]|$)|\.claude/settings[a-z.]*\.json|CLAUDE\.local\.md)' "modifying hackmode's own guardrail files" "ask the human (they edit hackmode's template and re-run 'hackmode on')"
}

# git push: no force, nothing to protected branches, only claude/* branches may be deleted.
check_push() {
  local seg x n i ref src dst del br
  local -a w args
  while IFS= read -r seg; do
    [[ $seg =~ (^|[[:space:]])git([[:space:]].*)?[[:space:]]push([[:space:]]|$) ]] || continue
    read -ra w <<< "${seg#*push}"
    args=(); del=0
    for x in ${w[@]+"${w[@]}"}; do
      x="$(strip_quotes "$x")"
      case "$x" in
        --force|--force-with-lease|--force-with-lease=*|--force-if-includes)
          block "force-push" "$CMD" "push to a new branch name instead: git push -u origin HEAD:claude/<name>-v2" ;;
        --mirror|--all|--prune) block "pushing every ref (git push $x)" "$CMD" "push one branch: git push -u origin <branch>" ;;
        --delete) del=1 ;;
        --*) ;;
        -*) [[ $x =~ ^-[a-zA-Z]*f ]] && block "force-push ($x)" "$CMD" "push to a new branch name instead"
            [[ $x =~ ^-[a-zA-Z]*d ]] && del=1 ;;
        *) args+=("$x") ;;
      esac
    done
    n=${#args[@]}
    if (( n <= 1 )); then
      br="$(current_branch)"
      is_protected "$br" && block "pushing the protected branch '$br'" "$CMD" "git switch -c claude/<issue#>-<slug>, then push that branch and open a PR"
      continue
    fi
    for (( i = 1; i < n; i++ )); do
      ref="${args[i]}"
      [[ $ref == +* ]] && block "force-push (+refspec $ref)" "$CMD" "push to a new branch name instead"
      if [[ $ref == *:* ]]; then src="${ref%%:*}"; dst="${ref#*:}"; else src="$ref"; dst="$ref"; fi
      dst="${dst#refs/heads/}"
      if [ "$src" = HEAD ] && [[ $ref != *:* ]]; then dst="$(current_branch)"; fi
      if (( del )) || [[ $ref == :* ]]; then
        [[ $dst == claude/* ]] || block "deleting the remote branch '$dst' (only claude/* branches may be deleted)" "$CMD"
        continue
      fi
      is_protected "$dst" && block "pushing to the protected branch '$dst'" "$CMD" "push your claude/* branch and open a PR"
    done
  done <<< "$(split_cmds "$CMD_NORM")"
}

# commit/merge/rebase/cherry-pick/revert/am are not allowed while a protected branch is checked out.
check_branch_ops() {
  local re="${G}(commit|merge|rebase|cherry-pick|revert|am)${E}" op="commit" br
  [[ $CMD_NORM =~ $re ]] || return 0
  re='git[^;&|]*[[:space:]](commit|merge|rebase|cherry-pick|revert|am)([[:space:]]|$|[;&|)])'
  [[ $CMD_NORM =~ $re ]] && op="${BASH_REMATCH[1]}"
  re="${G}(switch|checkout)[[:space:]]+([^;&|]*[[:space:]])?(${PROT_RE})${E}"
  if [[ $CMD_NORM =~ $re ]]; then
    block "git $op right after switching to a protected branch" "$CMD" "work on a claude/<issue#>-<slug> branch"
  fi
  re="${G}(switch|checkout)[[:space:]]"
  [[ $CMD_NORM =~ $re ]] && return 0      # the command switches branch first; can't know where it ends up
  br="$(current_branch)"
  is_protected "$br" && block "git $op while on the protected branch '$br'" "$CMD" "git switch -c claude/<issue#>-<slug> first (uncommitted changes come along), then retry"
  return 0
}

# .env files: never read, print, upload or stage them (.env.example & co. are fine).
check_env_access() {
  local s tok found="" re
  s="$(printf '%s' "$CMD_NORM" | sed -E 's/--env-file[= ]+[^[:space:]]+//g')"
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    tok="${tok#[[:space:]/\'\"=@<:]}"
    case "$tok" in
      .env.example|.env.sample|.env.template|.env.dist|.env.defaults|.env.schema) ;;
      *) found="$tok"; break ;;
    esac
  done <<< "$(printf '%s' "$s" | grep -oE "(^|[[:space:]/'\"=@<:])\.env(\.[A-Za-z0-9_.-]+)?" 2>/dev/null)"
  [ -n "$found" ] || return 0
  re="${B}(cat|less|more|head|tail|bat|batcat|grep|egrep|fgrep|rg|ag|awk|sed|cut|sort|uniq|strings|xxd|od|hexdump|base64|nl|tac|diff|source|vi|vim|nvim|nano|code|type|Get-Content|gc|scp|rsync|curl|wget|nc|ncat|python|python3|node|ruby|perl|php|jq|yq)${E}"
  if [[ $s =~ $re ]]; then block "reading or sending $found (secrets are human-managed)" "$CMD" "use the variable names from .env.example; the human manages the values"; fi
  re='(^|[;&|({`]|\$\()[[:space:]]*\.[[:space:]]'
  if [[ $s =~ $re ]]; then block "sourcing $found" "$CMD" "let the app load it (e.g. python-dotenv) instead of printing it"; fi
  if [[ $s == *@.env* ]]; then block "uploading $found" "$CMD"; fi
  re="${G}add${E}"
  if [[ $s =~ $re ]]; then block "staging $found" "$CMD" "make sure .env is in .gitignore; commit only .env.example"; fi
  return 0
}

# rm / mv / find -delete / cd: nothing at or above the project root, nothing outside it (except /tmp).
check_paths() {
  local seg n i w cls cmd unsafe_cd=0
  local -a words
  while IFS= read -r seg; do
    read -ra words <<< "$seg"
    n=${#words[@]}
    (( n )) || continue
    i=0
    while (( i < n )) && [[ ${words[i]} =~ ^([A-Za-z_][A-Za-z0-9_]*=.*|sudo|command|builtin|nice|nohup|time|exec|xargs|env)$ ]]; do i=$(( i + 1 )); done
    (( i < n )) || continue
    cmd="${words[i]##*/}"
    case "$cmd" in
      cd|pushd|Set-Location|sl)
        if (( i + 1 < n )); then
          cls="$(classify_path "${words[i+1]}")"
          case "$cls" in root|home|parent|outside|var) unsafe_cd=1 ;; *) unsafe_cd=0 ;; esac
        else
          unsafe_cd=1
        fi ;;
      rm|rmdir|unlink|shred|Remove-Item|ri|del|erase|rd)
        for w in "${words[@]:i+1}"; do
          case "$w" in
            --no-preserve-root) block "rm --no-preserve-root" "$CMD" ;;
            -*|/[sSqQ]) continue ;;
          esac
          case "$(strip_quotes "$w")" in
            *.claude/hackmode*|*CLAUDE.local.md*|*.claude/settings*) block "deleting hackmode's own files ($w)" "$CMD" "ask the human ('hackmode off' removes them cleanly)" ;;
          esac
          cls="$(classify_path "$w")"
          case "$cls" in
            ok|tmp)
              if (( unsafe_cd )) && [[ $w != /* && $w != [A-Za-z]:* ]]; then
                block "deleting '$w' after changing directory outside the project" "$CMD" "use paths inside the project, relative to its root"
              fi ;;
            *) block "deleting $(describe "$cls") ($w)" "$CMD" "delete specific paths inside the project (relative paths), or ask the human" ;;
          esac
        done ;;
      mv|Move-Item|move)
        for w in "${words[@]:i+1}"; do
          case "$w" in -*) continue ;; esac
          cls="$(classify_path "$w")"
          case "$cls" in root|home|cwd|parent|git) block "moving $(describe "$cls") ($w)" "$CMD" ;; esac
        done ;;
      find)
        if [[ $seg =~ (-delete|-exec[[:space:]]+(rm|shred)) ]] && (( i + 1 < n )); then
          cls="$(classify_path "${words[i+1]}")"
          case "$cls" in ok|tmp|cwd) ;; *) block "find … -delete on $(describe "$cls")" "$CMD" ;; esac
        fi ;;
    esac
  done <<< "$(split_cmds "$CMD_NORM")"
}

# ---------------------------------------------------------------- secrets
# stdin → prints "<kind>, starts with abcd…" for the first secret-looking value. $1=strong skips the generic rule.
find_secret() {
  local text m kind
  text="$(head -c 4194304)"                    # scan at most 4 MB
  [ -n "$text" ] || return 1
  local strong='AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z]+ )*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|xox[abposr]-[A-Za-z0-9-]{10,}|sk-(ant-|proj-)?[A-Za-z0-9_-]{32,}|AIza[0-9A-Za-z_-]{35}|(sk|rk)_live_[0-9A-Za-z]{20,}|[Aa][Pp][Ii]_?[Kk][Ee][Yy]=[A-Za-z0-9]{30,}'
  local junk='(your|example|placeholder|changeme|change_me|dummy|sample|fake|xxxx|demo|mock|hackathon|insecure|<|>|\.\.\.)'
  m="$(printf '%s' "$text" | grep -oE -e "$strong" 2>/dev/null | grep -viE "$junk" | head -n 1)"
  if [ -n "$m" ]; then
    case "$m" in
      AKIA*) kind="AWS access key" ;; -----*) kind="private key" ;; gh*|github_pat_*) kind="GitHub token" ;;
      xox*) kind="Slack token" ;; AIza*) kind="Google API key" ;; sk_live*|rk_live*) kind="Stripe live key" ;;
      sk-*) kind="API key" ;; *) kind="API key in a URL" ;;
    esac
    printf '%s, starts with %s…' "$kind" "${m:0:4}"; return 0
  fi
  if [ "${1:-}" != strong ]; then
    m="$(printf '%s' "$text" | grep -oiE -e "(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)[\"']?[[:space:]]*[:=][[:space:]]*[\"'][^\"'[:space:]\$<{%]{12,}[\"']" 2>/dev/null | grep -viE "$junk" | head -n 1)"
    if [ -n "$m" ]; then printf 'hardcoded credential, starts with %s…' "${m:0:4}"; return 0; fi
  fi
  return 1
}

# New text being written. Write payloads only hold the path + new content, so scan them raw (fast);
# for Edit/MultiEdit/NotebookEdit extract the new_* fields so old_string (e.g. a secret being removed) is ignored.
new_content() {
  if [ "$TOOL" = Write ]; then
    printf '%s' "$INPUT" | sed -e 's/\\"/"/g'
  else
    printf '%s' "$INPUT" | grep -oE '"(content|new_string|new_source)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*' 2>/dev/null \
      | sed -e 's/\\"/"/g' -e 's/\\n/ /g'
  fi
}

# ---------------------------------------------------------------- file edits
check_edit() {
  local f base d br label
  f="$(json_str file_path)"; [ -n "$f" ] || f="$(json_str notebook_path)"
  [ -n "$f" ] || return 0
  f="$(hm_normpath "$f")"
  case "$f" in
    */.claude/hackmode/HACKATHON_STATE.md) return 0 ;;   # the anchor is always editable (/state)
    */.claude/hackmode/*|*/.claude/settings.json|*/.claude/settings.local.json|*/CLAUDE.local.md)
      block "editing hackmode's own guardrail files ($f)" "$f" "ask the human (they edit hackmode's template and re-run 'hackmode on')" ;;
    */.git/*) block "editing git internals ($f)" "$f" ;;
  esac
  base="${f##*/}"
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist|.env.defaults|.env.schema) ;;
    .env|.env.*) block "writing $base (secrets are human-managed)" "$f" "document variable names in .env.example and read values from the environment" ;;
    *.pem|*.key|*.p12|*.pfx|id_rsa*|id_ed25519*|id_ecdsa*) block "writing key material ($base)" "$f" ;;
  esac
  # branch rule: no edits while a protected branch is checked out in the file's repo
  d="${f%/*}"; [ "$d" != "$f" ] || d="."
  while [ -n "$d" ] && [ ! -d "$d" ]; do
    if [[ $d == */* ]]; then d="${d%/*}"; else d="."; fi
  done
  br="$(current_branch "${d:-/}")"
  if is_protected "$br"; then
    block "editing files while the protected branch '$br' is checked out" "$f" "git fetch origin && git switch -c claude/<issue#>-<slug> origin/$br — then retry the edit"
  fi
  label="$(new_content | find_secret)" && block "the new content looks like it contains a secret ($label)" "(redacted)" "read it from an environment variable and keep the value in the git-ignored .env"
  return 0
}

# ---------------------------------------------------------------- main
case "$TOOL" in
  Bash|PowerShell)
    CMD="$(json_str command)"
    [ -n "$CMD" ] || exit 0
    CMD_NORM="${CMD//\\$'\n'/ }"                   # join line continuations
    CMD_NORM="$(strip_heredocs "$CMD_NORM")"
    CMD_NORM="${CMD_NORM%$'\n'}"
    CMD_NORM="${CMD_NORM//$'\n'/;}"                # newlines separate commands
    CMD_NORM="$(scrub_messages "$CMD_NORM")"
    check_rules
    check_push
    check_branch_ops
    check_env_access
    check_paths
    label="$(printf '%s' "$CMD" | find_secret strong)" && block "a hardcoded secret in the command ($label)" "(redacted)" "the human exports it as an environment variable; reference \$NAME instead"
    ;;
  Edit|Write|MultiEdit|NotebookEdit)
    check_edit ;;
esac
exit 0
