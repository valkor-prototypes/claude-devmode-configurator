#!/usr/bin/env bash
# End-to-end test of hackmode.sh: on → re-run → clock → status → tmux → off (needs tmux + python3).
# Usage: bash tests/e2e_test.sh [kit-dir] [scratch-dir]
KIT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"; W="${2:-$(mktemp -d)}"; HM="$KIT/hackmode.sh"
rm -rf "$W"; mkdir -p "$W/bin" "$W/home"; cd "$W" || exit 1
export HOME="$W/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git config --global user.email t@t; git config --global user.name t; git config --global init.defaultBranch main
# fake claude: --help advertises --remote-control; otherwise prints its args and sleeps
cat > bin/claude <<'EOF'
#!/usr/bin/env bash
if [ "$1" = --help ]; then echo "  --remote-control [name]   Start an interactive session with Remote Control"; exit 0; fi
echo "FAKE CLAUDE in $PWD :: $*"; sleep 300
EOF
chmod +x bin/claude; export HACKMODE_CLAUDE="$W/bin/claude" HACKMODE_NO_ATTACH=1 HACKMODE_TMUX_SESSION=hmtest
git init -q --bare origin.git
git clone -q origin.git spaceapps 2>/dev/null && cd spaceapps
echo "# Team CLAUDE.md (tracked)" > CLAUDE.md; echo "node_modules/" > .gitignore; echo "print('hi')" > app.py
git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
mkdir -p .claude && echo '{"permissions":{"allow":["Bash(make *)"]}}' > .claude/settings.local.json
printf '# my personal notes\nUse tabs.\n' > CLAUDE.local.md
cd "$W"
ok=0; bad=0; t() { if eval "$2"; then ok=$((ok+1)); else bad=$((bad+1)); echo "FAIL: $1"; fi; }
R="$W/spaceapps"

echo "===== on"; bash "$HM" on "$R" --start "2026-11-14 09:00" --hours 48 --lang pt-BR 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
t "status clean after on"           '[ -z "$(git -C "$R" status --porcelain)" ]'
t "settings valid JSON"             'python3 -m json.tool "$R/.claude/settings.local.json" >/dev/null'
t "hooks path absolute"             'grep -q "bash '"'"'$R/.claude/hackmode/hooks/guard.sh'"'"'" "$R/.claude/settings.local.json"'
t "user settings backed up"         'grep -q "make" "$R"/.claude/hackmode/backup/*settings.local.json'
t "doctrine block on top"           'head -1 "$R/CLAUDE.local.md" | grep -q "hackmode:start"'
t "user CLAUDE.local.md kept"       'grep -q "my personal notes" "$R/CLAUDE.local.md"'
t "team CLAUDE.md untouched"        '[ "$(cat "$R/CLAUDE.md")" = "# Team CLAUDE.md (tracked)" ]'
t "5 agents"                        '[ "$(ls "$R/.claude/agents" | wc -l)" = 5 ]'
t "7 skills"                        '[ "$(ls "$R/.claude/skills" | wc -l)" = 7 ]'
t "output style"                    '[ -f "$R/.claude/output-styles/hackathon.md" ]'
t "state rendered"                  'grep -q "Deadline:\*\* Mon 16 Nov 09:00" "$R/.claude/hackmode/HACKATHON_STATE.md" && grep -q "Team language:\*\* pt-BR" "$R/.claude/hackmode/HACKATHON_STATE.md" && ! grep -q "__" "$R/.claude/hackmode/HACKATHON_STATE.md"'
t "config"                          'grep -q "^HACK_PROTECTED_BRANCHES=main master$" "$R/.claude/hackmode/config"'
t "exclude block once"              '[ "$(grep -c "^# >>> hackmode" "$R/.git/info/exclude")" = 1 ]'

echo "===== hooks"
cd "$R"
echo '{"session_id":"x","hook_event_name":"SessionStart","source":"startup"}' | CLAUDE_PROJECT_DIR="$R" bash .claude/hackmode/hooks/context.sh session | head -8
echo "--- prompt:"; echo '{}' | CLAUDE_PROJECT_DIR="$R" bash .claude/hackmode/hooks/context.sh prompt
echo "--- statusline:"; echo "{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$R\"},\"context_window\":{\"used_percentage\":23}}" | bash .claude/hackmode/hooks/statusline.sh | sed 's/\x1b\[[0-9;]*m//g'
t "brief works without stdin"       'timeout 5 bash .claude/hackmode/hooks/context.sh brief </dev/null | grep -q "end of state"'
cd "$W"

echo "===== re-run on (idempotent) + clock"
echo "- my note" >> "$R/.claude/hackmode/HACKATHON_STATE.md"
bash "$HM" on "$R" >/dev/null 2>&1
t "state preserved on re-run"       'grep -q "my note" "$R/.claude/hackmode/HACKATHON_STATE.md"'
t "clock kept on re-run"            'grep -q "Deadline:\*\* Mon 16 Nov 09:00" "$R/.claude/hackmode/HACKATHON_STATE.md"'
t "backup not overwritten"          'grep -q "make" "$R"/.claude/hackmode/backup/*settings.local.json && [ "$(wc -l < "$R/.claude/hackmode/backup/index")" = 1 ]'
t "exclude still once"              '[ "$(grep -c "^# >>> hackmode" "$R/.git/info/exclude")" = 1 ]'
t "one doctrine block"              '[ "$(grep -c "hackmode:start" "$R/CLAUDE.local.md")" = 1 ]'
bash "$HM" clock "$R" --deadline "2026-11-15 18:00" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
t "deadline moved"                  'grep -q "Deadline:\*\* Sun 15 Nov 18:00" "$R/.claude/hackmode/HACKATHON_STATE.md" && grep -q "^HACK_HOURS=33$" "$R/.claude/hackmode/config" && grep -q "^HACK_START=$(date -d "2026-11-14 09:00" +%s)$" "$R/.claude/hackmode/config"'

echo "===== tmux"
PATH="$W/bin:$PATH" bash "$HM" tmux "$R" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
sleep 1.5
t "tmux windows"                    '[ "$(tmux list-windows -t hmtest -F "#W" | tr "\n" " ")" = "lead dev ops " ]'
echo "lead pane: $(tmux capture-pane -pJ -t hmtest:lead | grep FAKE)"
echo "dev  pane: $(tmux capture-pane -pJ -t hmtest:dev | grep FAKE)"
t "dev worktree + symlink"          '[ -L "$W/spaceapps-dev/.claude/hackmode" ] && [ -f "$W/spaceapps-dev/.claude/settings.local.json" ]'
t "dev settings additionalDirs"     'grep -q "\"additionalDirectories\": \[\"$R/.claude/hackmode\"\]" "$W/spaceapps-dev/.claude/settings.local.json"'
t "dev status clean"                '[ -z "$(git -C "$W/spaceapps-dev" status --porcelain)" ]'
echo "--- dev session context:"; echo '{}' | CLAUDE_PROJECT_DIR="$W/spaceapps-dev" bash "$W/spaceapps-dev/.claude/hackmode/hooks/context.sh" session | sed -n '4p'
echo "===== status"; bash "$HM" status "$R" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
tmux kill-session -t hmtest

echo "===== off"
bash "$HM" off "$R" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
t "no hackmode dir"                 '[ ! -e "$R/.claude/hackmode" ]'
t "user settings restored"          '[ "$(cat "$R/.claude/settings.local.json")" = "{\"permissions\":{\"allow\":[\"Bash(make *)\"]}}" ]'
t "CLAUDE.local.md = user only"     '[ "$(cat "$R/CLAUDE.local.md")" = "$(printf "# my personal notes\nUse tabs.")" ]'
t "agents/skills gone"              '[ ! -e "$R/.claude/agents" ] && [ ! -e "$R/.claude/skills" ] && [ ! -e "$R/.claude/output-styles" ]'
t "exclude cleaned"                 '! grep -q hackmode "$R/.git/info/exclude"'
t "dev worktree removed"            '[ ! -e "$W/spaceapps-dev" ]'
t "archive exists"                  'ls "$HOME"/.hackmode/archive/*/HACKATHON_STATE.md >/dev/null 2>&1'
t "git status = only user files"    '[ "$(git -C "$R" status --porcelain | sort | tr "\n" " ")" = "?? .claude/ ?? CLAUDE.local.md " ]'
echo "PASS=$ok FAIL=$bad"
