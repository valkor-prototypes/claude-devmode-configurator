# hackmode-win.ps1 - text/date helpers for hackmode.bat (Windows PowerShell 5.1+ / PowerShell 7).
# Batch can't do date math or reliable UTF-8 text edits, so hackmode.bat calls this for those bits.
# Keep this file ASCII-only: PowerShell 5.1 reads BOM-less scripts with the ANSI code page.
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Verb,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
if ($null -eq $Rest) { $Rest = @() }
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Inv = [System.Globalization.CultureInfo]::InvariantCulture

function Read-Text([string]$Path) {
  if (Test-Path -LiteralPath $Path) { return [System.IO.File]::ReadAllText($Path, $Utf8) }
  return ''
}
function Write-Text([string]$Path, [string]$Text) {
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $Utf8)
}
function Remove-Block([string]$Text) {
  return [regex]::Replace($Text, '(?s)<!-- hackmode:start.*?<!-- hackmode:end -->[ \t]*\r?\n?', '')
}
function Remove-ExcludeBlock([string]$Text) {
  return [regex]::Replace($Text, '(?ms)^# >>> hackmode.*?^# <<< hackmode[^\n]*\n?', '')
}
function Get-Human([long]$Epoch) {
  return [DateTimeOffset]::FromUnixTimeSeconds($Epoch).ToLocalTime().ToString('ddd dd MMM HH:mm zzz', $Inv)
}

switch ($Verb) {
  'now'   { [DateTimeOffset]::Now.ToUnixTimeSeconds(); break }
  'stamp' { (Get-Date).ToString('yyyyMMdd-HHmmss', $Inv); break }
  'epoch' {
    # "YYYY-MM-DD HH:MM" in local time -> unix seconds
    $formats = [string[]]@('yyyy-MM-dd HH:mm', 'yyyy-MM-ddTHH:mm', 'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd')
    $d = [datetime]::ParseExact($Rest[0].Trim(), $formats, $Inv, [System.Globalization.DateTimeStyles]::None)
    ([DateTimeOffset]$d).ToUnixTimeSeconds(); break
  }
  'human' { Get-Human ([long]$Rest[0]); break }
  'config' {
    # config <file> KEY=VALUE...
    Write-Text $Rest[0] ((($Rest | Select-Object -Skip 1) -join "`n") + "`n"); break
  }
  'state' {
    # state <template> <out> <event> <deadline-human> <hours> <lang>   (never overwrites an existing state file)
    if (-not (Test-Path -LiteralPath $Rest[1])) {
      $now = (Get-Date).ToString('ddd dd MMM HH:mm', $Inv)
      $t = (Read-Text $Rest[0]).Replace('__EVENT__', $Rest[2]).Replace('__DEADLINE__', $Rest[3]).Replace('__HOURS__', $Rest[4]).Replace('__LANG__', $Rest[5]).Replace('__NOW__', $now)
      Write-Text $Rest[1] $t
    }
    break
  }
  'set-deadline' {
    # set-deadline <state-file> <deadline-human> <hours>
    if (Test-Path -LiteralPath $Rest[0]) {
      $line = ('- **Deadline:** ' + $Rest[1] + ' (' + $Rest[2] + 'h event)').Replace('$', '$$')
      Write-Text $Rest[0] ([regex]::Replace((Read-Text $Rest[0]), '(?m)^- \*\*Deadline:\*\* .*$', $line))
    }
    break
  }
  'render' {
    # render <settings-template> <out> <hooks-dir> <additional-dirs-json>
    $t = (Read-Text $Rest[0]).Replace('__HOOKS__', $Rest[2]).Replace('__ADDITIONAL_DIRS__', $Rest[3])
    Write-Text $Rest[1] $t; break
  }
  'doctrine' {
    # doctrine <doctrine-template> <CLAUDE.local.md>: managed block on top, the user's own content kept below
    $block = (Read-Text $Rest[0]).TrimEnd() + "`n"
    $rest = (Remove-Block (Read-Text $Rest[1])).Trim()
    if ($rest) { $block += "`n" + $rest + "`n" }
    Write-Text $Rest[1] $block; break
  }
  'undoctrine' {
    # undoctrine <CLAUDE.local.md>: remove the managed block; delete the file if nothing else is left
    if (Test-Path -LiteralPath $Rest[0]) {
      $rest = (Remove-Block (Read-Text $Rest[0])).Trim()
      if ($rest) { Write-Text $Rest[0] ($rest + "`n") } else { Remove-Item -LiteralPath $Rest[0] -Force }
    }
    break
  }
  'exclude-add' {
    # exclude-add <.git/info/exclude> <pattern>...
    $t = Remove-ExcludeBlock (Read-Text $Rest[0])
    if ($t.Length -gt 0 -and -not $t.EndsWith("`n")) { $t += "`n" }
    $t += "# >>> hackmode (local-only files; removed by 'hackmode off') >>>`n"
    $t += (($Rest | Select-Object -Skip 1) -join "`n") + "`n# <<< hackmode <<<`n"
    Write-Text $Rest[0] $t; break
  }
  'exclude-remove' {
    if (Test-Path -LiteralPath $Rest[0]) { Write-Text $Rest[0] (Remove-ExcludeBlock (Read-Text $Rest[0])) }
    break
  }
  'status' {
    # status <config> <state-file>: clock line + phase (same model as the bash hooks)
    $cfg = @{}
    foreach ($l in (Read-Text $Rest[0]) -split "`n") { if ($l -match '^([A-Z_]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2].TrimEnd("`r") } }
    $start = [long]$cfg['HACK_START']; $end = [long]$cfg['HACK_END']; $now = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    $total = [math]::Max(1, $end - $start); $el = $now - $start; $left = $end - $now; $pct = [math]::Floor($el * 100 / $total)
    $phase = 'OVER'
    if ($el -lt 0) { $phase = 'PRE-START' }
    elseif ($now -lt $start + $total * 0.10) { $phase = 'IDEATE' }
    elseif ($now -lt $start + $total * 0.55) { $phase = 'BUILD' }
    elseif ($now -lt $start + $total * 0.80) { $phase = 'INTEGRATE' }
    elseif ($now -lt $start + $total * 0.92) { $phase = 'FREEZE' }
    elseif ($left -gt 0) { $phase = 'SUBMIT' }
    $fmt = { param($s) $s = [math]::Abs($s); '{0}h{1:00}m' -f [math]::Floor($s / 3600), [math]::Floor(($s % 3600) / 60) }
    if ($phase -eq 'PRE-START') { $clock = 'event starts in ' + (& $fmt (-$el)) }
    elseif ($phase -eq 'OVER') { $clock = 'DEADLINE PASSED ' + (& $fmt $left) + ' ago' }
    else { $clock = 'T-' + (& $fmt $left) + ' left (' + $pct + '% elapsed)' }
    $age = ''
    if (Test-Path -LiteralPath $Rest[1]) { $age = & $fmt ($now - [DateTimeOffset]::new((Get-Item -LiteralPath $Rest[1]).LastWriteTime).ToUnixTimeSeconds()) }
    [Console]::OutputEncoding = $Utf8
    Write-Output ('  event     ' + $cfg['HACK_EVENT'])
    Write-Output ('  clock     ' + $clock + ' - phase ' + $phase)
    Write-Output ('  deadline  ' + $cfg['HACK_END_HUMAN'] + ' (' + $cfg['HACK_HOURS'] + 'h event)')
    Write-Output ('  autonomy  ' + $cfg['HACK_AUTONOMY'] + ' - team language ' + $cfg['HACK_LANG'])
    Write-Output ('  state     .claude\hackmode\HACKATHON_STATE.md (updated ' + $age + ' ago)')
    Write-Output ('  protected ' + $cfg['HACK_PROTECTED_BRANCHES'])
    break
  }
  'cat' { [Console]::OutputEncoding = $Utf8; [Console]::Out.Write((Read-Text $Rest[0])); break }
  default { Write-Error ('unknown verb: ' + $Verb); exit 2 }
}
