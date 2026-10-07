<#
.SYNOPSIS
  Parse/import check: runs a headless import and prints only script errors and warnings.
  The full log goes to Godot/logs/check.log. Exit code 1 if any SCRIPT ERROR / Parse Error.
.EXAMPLE
  ./check.ps1
#>
param([string]$Godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe")
$proj = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path (Split-Path $proj -Parent) "logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "check.log"
$p = Start-Process -FilePath $Godot -ArgumentList @("--headless", "--path", "`"$proj`"", "--import") -PassThru -NoNewWindow -Wait `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
$hits = @(Get-Content $log, "$log.err" | Select-String -Pattern "SCRIPT ERROR|Parse Error|^ERROR|^WARNING|at: ")
$errs = @($hits | Where-Object { $_.Line -match "SCRIPT ERROR|Parse Error|^ERROR" })
$hits | Select-Object -First 40 | ForEach-Object { Write-Host $_.Line }
if ($errs.Count -gt 0) {
    # The import log only names the dependent script; --check-only per file gives the real message.
    Get-ChildItem (Join-Path $proj "scripts") -Recurse -Filter *.gd | ForEach-Object {
        $res = "res://" + $_.FullName.Substring($proj.Length + 1).Replace("\", "/")
        $out = & $Godot --headless --path $proj --check-only --script $res 2>&1 | Out-String
        if ($out -match "Parse Error: ([^
]+)") { Write-Host ("  {0}: {1}" -f $res, $Matches[1]) }
    }
}
Write-Host ("check: errors={0} lines={1} log={2}" -f $errs.Count, $hits.Count, $log)
if ($errs.Count -gt 0) { exit 1 }
exit 0
