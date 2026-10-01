<#
.SYNOPSIS
  EOS probe: a dedicated-server process advertises a session, a client process logs in with a
  device ID and searches for it. Logs go to Godot/logs/eos_<stamp>/; prints a short summary.
  Needs tools/get_eosg.ps1 and tools/make_eos_credentials.ps1 to have been run once.
#>
param([string]$Godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe", [int]$HoldSec = 40,
      [string]$ServerExe = "", [string]$ClientExe = "")
$ErrorActionPreference = "Stop"
$proj = Split-Path $PSScriptRoot -Parent
$dir = Join-Path (Join-Path (Split-Path $proj -Parent) "logs") ("eos_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $dir | Out-Null
$nonce = "n" + (Get-Random)

# Exported builds read eos_credentials.local.json from next to the executable.
function Start-Godot([string]$name, [string[]]$userArgs, [string]$exe) {
    $ga = @("--headless")
    if ($exe -eq "") { $exe = $Godot; $ga += @("--path", "`"$proj`"") }
    Start-Process -FilePath $exe -ArgumentList ($ga + @("--") + $userArgs) -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $dir "$name.log") -RedirectStandardError (Join-Path $dir "$name.err.log")
}
$server = Start-Godot "server" @("--eostest=server", "--nonce=$nonce", "--hold=$HoldSec") $ServerExe
$deadline = (Get-Date).AddSeconds(60)
while (-not (Select-String -Path (Join-Path $dir "server.log") -Pattern "EOS_SESSION_READY|EOS_RESULT" -Quiet) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
$client = Start-Godot "client" @("--eostest=client", "--nonce=$nonce") $ClientExe
foreach ($p in $client, $server) { if (-not $p.WaitForExit(($HoldSec + 60) * 1000)) { Stop-Process -Id $p.Id -Force } }

$fail = @()
foreach ($n in "server", "client") {
    $line = Select-String -Path (Join-Path $dir "$n.log") -Pattern "EOS_RESULT (\{.*\})$" | Select-Object -Last 1
    if ($null -eq $line) { $fail += "${n}: no EOS_RESULT"; continue }
    $r = $line.Matches[0].Groups[1].Value | ConvertFrom-Json
    $steps = ($r.steps | ForEach-Object { "{0}={1}@{2}ms" -f $_.step, $(if ($_.ok) { "ok" } else { "FAIL" }), $_.ms }) -join " "
    Write-Host "$n ok=$($r.ok) $steps"
    if (-not $r.ok) { $fail += "$n not ok" }
}
$crash = @(Get-ChildItem $dir -Filter *.log | Select-String -Pattern "CrashHandlerException|SCRIPT ERROR" | ForEach-Object { "$($_.Filename): $($_.Line)" })
$fail += $crash
Write-Host ("PASS={0} {1} log={2}" -f ($fail.Count -eq 0), ($fail -join "; "), $dir)
