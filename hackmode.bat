@echo off
rem ===========================================================================
rem  hackmode.bat - NASA Space Apps hackathon mode for Claude Code (Windows)
rem  Usage: hackmode.bat COMMAND [repo-path] [options]   (run "hackmode.bat help")
rem  Needs: Git for Windows (Claude Code runs hackmode's bash hooks with its
rem         Git Bash), Windows PowerShell 5.1+ (built in) and Claude Code.
rem  Batch can't do date math or UTF-8 text edits, so lib\hackmode-win.ps1
rem  handles those; everything else happens here.
rem ===========================================================================
setlocal EnableExtensions DisableDelayedExpansion
set "HM_VERSION=1.0.0"
set "KIT=%~dp0"
if "%KIT:~-1%"=="\" set "KIT=%KIT:~0,-1%"
set "TPL=%KIT%\template"
set "HELPER=%KIT%\lib\hackmode-win.ps1"
set "PSH=powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%""

set "CMD=%~1"
if not defined CMD set "CMD=help"
shift
set "TARGET=."
set "O_START="
set "O_HOURS="
set "O_DEADLINE="
set "O_EVENT="
set "O_LANG="
set "O_AUTONOMY="
set "PASS="

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--start"    (set "O_START=%~2"    & shift & shift & goto parse)
if /i "%~1"=="--hours"    (set "O_HOURS=%~2"    & shift & shift & goto parse)
if /i "%~1"=="--deadline" (set "O_DEADLINE=%~2" & shift & shift & goto parse)
if /i "%~1"=="--event"    (set "O_EVENT=%~2"    & shift & shift & goto parse)
if /i "%~1"=="--lang"     (set "O_LANG=%~2"     & shift & shift & goto parse)
if /i "%~1"=="--autonomy" (set "O_AUTONOMY=%~2" & shift & shift & goto parse)
if "%~1"=="--" goto collect
set "TARGET=%~1"
shift
goto parse
:collect
shift
if "%~1"=="" goto parsed
set "PASS=%PASS% %1"
goto collect
:parsed

if not defined O_AUTONOMY goto autonomy_ok
for %%A in (allowlist auto yolo) do if /i "%O_AUTONOMY%"=="%%A" goto autonomy_ok
echo [x] --autonomy must be allowlist, auto or yolo
exit /b 1
:autonomy_ok
if not defined O_HOURS goto hours_ok
set /a "CHK=O_HOURS" 2>nul
if not "%CHK%"=="%O_HOURS%" (echo [x] --hours must be a positive integer& exit /b 1)
if %CHK% LEQ 0 (echo [x] --hours must be a positive integer& exit /b 1)
:hours_ok

if /i "%CMD%"=="on"     goto cmd_on
if /i "%CMD%"=="off"    goto cmd_off
if /i "%CMD%"=="status" goto cmd_status
if /i "%CMD%"=="clock"  goto cmd_clock
if /i "%CMD%"=="state"  goto cmd_state
if /i "%CMD%"=="claude" goto cmd_claude
if /i "%CMD%"=="tmux"   (echo [x] The tmux war room is Linux-only ^(hackmode.sh^). On Windows use: hackmode.bat claude [repo]& exit /b 1)
if /i "%CMD%"=="help"   goto usage
if /i "%CMD%"=="-h"     goto usage
if /i "%CMD%"=="--help" goto usage
echo [x] Unknown command: %CMD%
echo.

:usage
echo hackmode v%HM_VERSION% - NASA Space Apps hackathon mode for Claude Code (Windows)
echo.
echo Usage: hackmode.bat COMMAND [repo-path] [options]     (repo-path defaults to .)
echo.
echo Commands
echo   on       Enable hackathon mode in the repo (safe to re-run: refreshes files, keeps state + clock)
echo   off      Disable it and restore the repo (state archived to %%USERPROFILE%%\.hackmode\archive)
echo   status   Mode, clock, phase, state file, guard blocks
echo   clock    Show the clock, or move it: clock --deadline "2026-11-15 18:00"
echo   state    Print HACKATHON_STATE.md
echo   claude   Start Claude in the repo with the configured autonomy (extra claude args after --)
echo.
echo Options (on / clock)
echo   --start "YYYY-MM-DD HH:MM"     event start, local time         (default: now)
echo   --hours N                      event length in hours           (default: 48)
echo   --deadline "YYYY-MM-DD HH:MM"  submission deadline             (overrides start + hours)
echo   --event "NAME"                 default: NASA Space Apps Challenge
echo   --lang CODE                    team language for issues/PR comments (default: pt-BR)
echo   --autonomy MODE                allowlist (default) ^| auto ^| yolo
echo.
echo Example: hackmode.bat on C:\code\spaceapps --start "2026-11-14 09:00" --hours 48
echo The tmux war room and the dev worktree are Linux-only (hackmode.sh).
exit /b 0

rem ---------------------------------------------------------------- commands
:cmd_on
call :resolve || exit /b 1
if not exist "%TPL%\doctrine.md" (echo [x] template folder not found next to hackmode.bat& exit /b 1)
call :loadcfg
if not defined HACK_EVENT set "HACK_EVENT=NASA Space Apps Challenge"
if defined O_EVENT set "HACK_EVENT=%O_EVENT%"
if not defined HACK_LANG set "HACK_LANG=pt-BR"
if defined O_LANG set "HACK_LANG=%O_LANG%"
if not defined HACK_AUTONOMY set "HACK_AUTONOMY=allowlist"
if defined O_AUTONOMY set "HACK_AUTONOMY=%O_AUTONOMY%"
call :clock_compute || exit /b 1
call :protected
if not exist "%HMW%\hooks" mkdir "%HMW%\hooks"
if not exist "%HMW%\backup" mkdir "%HMW%\backup"
copy /y "%TPL%\hooks\*.sh" "%HMW%\hooks\" >nul || (echo [x] Could not copy the hooks.& exit /b 1)
call :write_config || exit /b 1
if exist "%HMW%\HACKATHON_STATE.md" goto on_state_exists
%PSH% state "%TPL%\HACKATHON_STATE.md" "%HMW%\HACKATHON_STATE.md" "%HACK_EVENT%" "%C_HUMAN%" "%C_HOURS%" "%HACK_LANG%" || exit /b 1
goto on_state_done
:on_state_exists
%PSH% set-deadline "%HMW%\HACKATHON_STATE.md" "%C_HUMAN%" "%C_HOURS%"
:on_state_done
call :install_into "%ROOTW%" || exit /b 1
call :exclude_add || exit /b 1
echo.
echo [+] Hackathon mode ON in %ROOT%
echo     deadline  %C_HUMAN% (%C_HOURS%h event)
echo     autonomy  %HACK_AUTONOMY%
echo     language  %HACK_LANG% for issues / PR comments - English for judge-facing text
echo     protected %PROT% (no edits, commits or pushes)
echo     files     CLAUDE.local.md + .claude\{settings.local.json, agents, skills, output-styles, hackmode} - all git-excluded
call :preflight
echo.
echo Next: hackmode.bat claude "%ROOTW%"
echo       then in Claude: /state challenge: ...; value prop: ...; demo: 1) ... 2) ... 3) ...
exit /b 0

:cmd_off
call :resolve || exit /b 1
call :loadcfg
if exist "%HMW%\HACKATHON_STATE.md" call :archive
if exist "%HMW%\manifest" for /f "usebackq delims=" %%F in ("%HMW%\manifest") do if exist "%%F" del /q "%%F"
if exist "%HMW%\backup\index" for /f "usebackq tokens=1,* delims=|" %%A in ("%HMW%\backup\index") do copy /y "%HMW%\backup\%%A" "%%B" >nul && echo [+] Restored %%B
%PSH% undoctrine "%ROOTW%\CLAUDE.local.md"
if exist "%HMW%\" rd /s /q "%HMW%"
if exist "%ROOTW%\.claude\skills\" for /d %%D in ("%ROOTW%\.claude\skills\*") do rd "%%D" 2>nul
for %%D in (skills agents output-styles) do rd "%ROOTW%\.claude\%%D" 2>nul
rd "%ROOTW%\.claude" 2>nul
%PSH% exclude-remove "%EXCL%"
echo [+] Hackathon mode OFF - Claude is back to normal in %ROOT%
exit /b 0

:cmd_status
call :resolve || exit /b 1
call :loadcfg
if "%ACTIVE%"=="0" (echo hackmode: OFF in %ROOT%& exit /b 0)
echo hackmode ON in %ROOT% (v%HACK_VERSION%)
%PSH% status "%HMW%\config" "%HMW%\HACKATHON_STATE.md"
set "BLK=0"
if exist "%HMW%\guard.log" for /f %%N in ('type "%HMW%\guard.log" ^| find /c /v ""') do set "BLK=%%N"
echo   guard     %BLK% block(s) - see .claude\hackmode\guard.log
for /f "delims=" %%B in ('git -C "%ROOT%" symbolic-ref --short -q HEAD 2^>nul') do echo   branch    %%B
exit /b 0

:cmd_clock
call :resolve || exit /b 1
call :loadcfg
if "%ACTIVE%"=="0" (echo [x] hackmode is off here - run: hackmode.bat on& exit /b 1)
if not defined O_START if not defined O_HOURS if not defined O_DEADLINE goto clock_show
call :clock_compute || exit /b 1
set "PROT=%HACK_PROTECTED_BRANCHES%"
call :write_config || exit /b 1
%PSH% set-deadline "%HMW%\HACKATHON_STATE.md" "%C_HUMAN%" "%C_HOURS%"
echo [+] Clock updated - deadline %C_HUMAN% (%C_HOURS%h event)
:clock_show
%PSH% status "%HMW%\config" "%HMW%\HACKATHON_STATE.md"
exit /b 0

:cmd_state
call :resolve || exit /b 1
if not exist "%HMW%\HACKATHON_STATE.md" (echo [x] No state file - run: hackmode.bat on& exit /b 1)
%PSH% cat "%HMW%\HACKATHON_STATE.md"
exit /b 0

:cmd_claude
call :resolve || exit /b 1
call :loadcfg
if "%ACTIVE%"=="0" (echo [x] hackmode is off here - run: hackmode.bat on "%ROOTW%"& exit /b 1)
set "MODEFLAG=--permission-mode acceptEdits"
if /i "%HACK_AUTONOMY%"=="auto" set "MODEFLAG=--permission-mode auto"
if /i "%HACK_AUTONOMY%"=="yolo" set "MODEFLAG=--dangerously-skip-permissions"
cd /d "%ROOTW%"
call claude %MODEFLAG%%PASS%
exit /b %errorlevel%

rem ---------------------------------------------------------------- helpers
:resolve
if not exist "%TARGET%\" (echo [x] No such directory: %TARGET%& exit /b 1)
where git >nul 2>&1 || (echo [x] git not found - install Git for Windows: https://git-scm.com/download/win& exit /b 1)
set "TOP="
for /f "usebackq delims=" %%I in (`git -C "%TARGET%" rev-parse --show-toplevel 2^>nul`) do set "TOP=%%I"
if not defined TOP (echo [x] %TARGET% is not inside a git repository - clone the team repo first.& exit /b 1)
set "ROOT="
for /f "usebackq tokens=1,*" %%A in (`git -C "%TOP%" worktree list --porcelain`) do if not defined ROOT if "%%A"=="worktree" set "ROOT=%%B"
if not defined ROOT set "ROOT=%TOP%"
set "ROOTW=%ROOT:/=\%"
set "HMF=%ROOT%/.claude/hackmode"
set "HMW=%ROOTW%\.claude\hackmode"
for %%I in ("%ROOTW%") do set "REPO=%%~nxI"
set "GCD="
for /f "usebackq delims=" %%I in (`git -C "%ROOT%" rev-parse --git-common-dir`) do set "GCD=%%I"
if not "%GCD:~1,1%"==":" set "GCD=%ROOT%/%GCD%"
set "EXCL=%GCD:/=\%\info\exclude"
exit /b 0

:loadcfg
set "ACTIVE=0"
if not exist "%HMW%\config" exit /b 1
for /f "usebackq tokens=1,* delims==" %%A in ("%HMW%\config") do set "%%A=%%B"
set "ACTIVE=1"
exit /b 0

:protected
set "DEF="
for /f "usebackq delims=" %%I in (`git -C "%ROOT%" symbolic-ref -q --short refs/remotes/origin/HEAD 2^>nul`) do set "DEF=%%I"
set "PROT=main master"
if not defined DEF exit /b 0
set "DEF=%DEF:origin/=%"
if /i "%DEF%"=="main" exit /b 0
if /i "%DEF%"=="master" exit /b 0
set "PROT=main master %DEF%"
exit /b 0

rem Sets C_START / C_END / C_HOURS / C_HUMAN (same rules as hackmode.sh):
rem   --deadline D [--start S or --hours H] : end = D; start = S, D-H, the existing start, or now
rem   --start S [--hours H]                 : end = S + H (H defaults to the current length, else 48)
rem   --hours H                             : keeps the start, end = start + H
:clock_compute
set "NOW="
for /f "usebackq delims=" %%I in (`%PSH% now`) do set "NOW=%%I"
if not defined NOW (echo [x] The PowerShell helper failed - is PowerShell available?& exit /b 1)
set "HOURS=48"
if defined HACK_START if defined HACK_END set /a "HOURS=(HACK_END-HACK_START+1800)/3600"
if defined O_HOURS set "HOURS=%O_HOURS%"
set "S_EP="
set "D_EP="
if defined O_START for /f "usebackq delims=" %%I in (`%PSH% epoch "%O_START%"`) do set "S_EP=%%I"
if defined O_START if not defined S_EP (echo [x] Can't parse --start "%O_START%" - use "YYYY-MM-DD HH:MM"& exit /b 1)
if defined O_DEADLINE for /f "usebackq delims=" %%I in (`%PSH% epoch "%O_DEADLINE%"`) do set "D_EP=%%I"
if defined O_DEADLINE if not defined D_EP (echo [x] Can't parse --deadline "%O_DEADLINE%" - use "YYYY-MM-DD HH:MM"& exit /b 1)
if not defined D_EP goto cc_nodeadline
set "C_END=%D_EP%"
if defined S_EP (set "C_START=%S_EP%" & goto cc_done)
if defined O_HOURS (set /a "C_START=D_EP-HOURS*3600" & goto cc_done)
if defined HACK_START (set "C_START=%HACK_START%") else (set "C_START=%NOW%")
goto cc_done
:cc_nodeadline
if defined S_EP (set "C_START=%S_EP%") else if defined HACK_START (set "C_START=%HACK_START%") else (set "C_START=%NOW%")
if not defined S_EP if not defined O_HOURS if defined HACK_END (set "C_END=%HACK_END%" & goto cc_done)
set /a "C_END=C_START+HOURS*3600"
:cc_done
if %C_END% LEQ %C_START% (echo [x] The deadline must be after the start.& exit /b 1)
set /a "C_HOURS=(C_END-C_START+1800)/3600"
set "C_HUMAN="
for /f "usebackq delims=" %%I in (`%PSH% human %C_END%`) do set "C_HUMAN=%%I"
exit /b 0

:write_config
%PSH% config "%HMW%\config" "HACK_VERSION=%HM_VERSION%" "HACK_EVENT=%HACK_EVENT%" "HACK_START=%C_START%" "HACK_END=%C_END%" "HACK_END_HUMAN=%C_HUMAN%" "HACK_HOURS=%C_HOURS%" "HACK_LANG=%HACK_LANG%" "HACK_AUTONOMY=%HACK_AUTONOMY%" "HACK_PROTECTED_BRANCHES=%PROT%" "HACK_MAIN_ROOT=%ROOT%"
exit /b %errorlevel%

rem install_into CHECKOUT: agents, skills, output style, settings (hooks run via Git Bash), doctrine
:install_into
set "DST=%~1"
for %%F in ("%TPL%\agents\*.md") do call :put "%%~fF" "%DST%\.claude\agents\%%~nxF" || exit /b 1
for /d %%D in ("%TPL%\skills\*") do call :put "%%~fD\SKILL.md" "%DST%\.claude\skills\%%~nxD\SKILL.md" || exit /b 1
call :put "%TPL%\output-styles\hackathon.md" "%DST%\.claude\output-styles\hackathon.md" || exit /b 1
set "TMPS=%TEMP%\hackmode-settings-%RANDOM%%RANDOM%.json"
%PSH% render "%TPL%\settings.local.json" "%TMPS%" "%HMF%/hooks" "[]" || exit /b 1
call :put "%TMPS%" "%DST%\.claude\settings.local.json" || exit /b 1
del /q "%TMPS%" >nul 2>&1
%PSH% doctrine "%TPL%\doctrine.md" "%DST%\CLAUDE.local.md" || exit /b 1
exit /b 0

rem put SRC DST: copy into place; on the first "on", back up anything already there
:put
if not exist "%~dp2" mkdir "%~dp2"
if "%ACTIVE%"=="0" if exist "%~2" call :backup "%~2"
copy /y "%~1" "%~2" >nul || (echo [x] Could not write %~2& exit /b 1)
>>"%HMW%\manifest" echo %~2
exit /b 0

:backup
set "B_KEY=%~1"
set "B_KEY=%B_KEY::=%"
set "B_KEY=%B_KEY:\=#%"
if exist "%HMW%\backup\%B_KEY%" exit /b 0
copy /y "%~1" "%HMW%\backup\%B_KEY%" >nul
>>"%HMW%\backup\index" echo %B_KEY%^|%~1
echo [!] Backed up your existing %~1 (restored by "hackmode.bat off")
exit /b 0

:exclude_add
set "EXL=/CLAUDE.local.md /.claude/hackmode /.claude/settings.local.json /.claude/output-styles/hackathon.md /.claude/worktrees/"
for %%F in ("%TPL%\agents\*.md") do call set "EXL=%%EXL%% /.claude/agents/%%~nxF"
for /d %%D in ("%TPL%\skills\*") do call set "EXL=%%EXL%% /.claude/skills/%%~nxD/"
%PSH% exclude-add "%EXCL%" %EXL%
exit /b %errorlevel%

:archive
set "STAMP="
for /f "usebackq delims=" %%I in (`%PSH% stamp`) do set "STAMP=%%I"
set "ARCH=%USERPROFILE%\.hackmode\archive\%REPO%-%STAMP%"
if not exist "%ARCH%" mkdir "%ARCH%"
copy /y "%HMW%\HACKATHON_STATE.md" "%ARCH%\" >nul
if exist "%HMW%\guard.log" copy /y "%HMW%\guard.log" "%ARCH%\" >nul
echo [+] Archived state + guard log to %ARCH%
exit /b 0

:preflight
where claude >nul 2>&1 || echo [!] claude CLI not found on PATH - install: irm https://claude.ai/install.ps1 ^| iex
call :find_bash
where gh >nul 2>&1 || (echo [!] gh ^(GitHub CLI^) not found - issues, PR reviews and the pinned state issue need it& exit /b 0)
gh auth status >nul 2>&1 || echo [!] gh is not logged in - run: gh auth login ^(as Claude's GitHub account^)
exit /b 0

:find_bash
if defined CLAUDE_CODE_GIT_BASH_PATH if exist "%CLAUDE_CODE_GIT_BASH_PATH%" exit /b 0
if exist "%ProgramFiles%\Git\bin\bash.exe" exit /b 0
for /f "delims=" %%G in ('where git 2^>nul') do if exist "%%~dpG..\bin\bash.exe" exit /b 0
echo [!] Git Bash not found - Claude Code runs hackmode's hooks with it. Install Git for Windows or set CLAUDE_CODE_GIT_BASH_PATH.
exit /b 0
