<#
.SYNOPSIS
  Runs one TowerClash spike match: headless dedicated server + 2 bot clients.
  Verbose output goes to Godot/logs/match_<stamp>/; the terminal gets a short summary.
.EXAMPLE
  ./run_match.ps1 -TimeScale 4
  ./run_match.ps1 -Visual -Shots "20,60,120"     # windowed clients at 1x, screenshots
#>
param(
    [double]$TimeScale = 4,
    [int]$Seed = 12345,
    [int]$Port = 7777,
    [switch]$Visual,
    [string]$Shots = "",
    [int]$TimeoutSec = 600,
    [string]$Godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$ServerExe = "",
    [string]$ClientExe = "",
    [switch]$InputTest
)
$ErrorActionPreference = "Stop"
$proj = Split-Path $PSScriptRoot -Parent
$logRoot = Join-Path (Split-Path $proj -Parent) "logs"
$dir = Join-Path $logRoot ("match_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $dir | Out-Null

function Start-Godot([string]$name, [string[]]$godotArgs, [string[]]$userArgs, [string]$exe) {
    if ($exe -eq "") { $exe = $Godot; $godotArgs = @("--path", "`"$proj`"") + $godotArgs }
    $all = $godotArgs + @("--") + $userArgs
    Start-Process -FilePath $exe -ArgumentList $all -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $dir "$name.log") -RedirectStandardError (Join-Path $dir "$name.err.log")
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$server = Start-Godot "server" @("--headless") @("--server", "--port=$Port", "--seed=$Seed", "--timescale=$TimeScale", "--quit-on-end", "--codec-check") $ServerExe
Start-Sleep -Milliseconds 1500
$clients = @()
foreach ($i in 0, 1) {
    $ua = @("--host=127.0.0.1", "--port=$Port", "--name=Bot$i", "--bot", "--bot-speed=$TimeScale", "--quit-on-end", "--mute")
    # -InputTest: client 0 merges only through synthetic mouse drags (needs -Visual for real input).
    if ($InputTest -and $i -eq 0) { $ua += "--input-test" }
    if ($Visual) {
        $ga = @("--position", "$(40 + $i * 580),40")
        if ($Shots -ne "") { $ua += @("--shots=$Shots", "--shot-prefix=$(Join-Path $dir "client$i")") }
    } else { $ga = @("--headless") }
    $clients += Start-Godot "client$i" $ga $ua $ClientExe
    Start-Sleep -Milliseconds 300
}

$all = @($server) + $clients
if (-not $server.WaitForExit($TimeoutSec * 1000)) { Write-Host "TIMEOUT after $TimeoutSec s" }
foreach ($c in $clients) { [void]$c.WaitForExit(15000) }
foreach ($p in $all) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
$wall = [math]::Round($sw.Elapsed.TotalSeconds, 1)

function Get-Json([string]$file, [string]$tag) {
    $line = Select-String -Path $file -Pattern "$tag (\{.*\})$" | Select-Object -Last 1
    if ($null -eq $line) { return $null }
    return $line.Matches[0].Groups[1].Value | ConvertFrom-Json
}
$res = Get-Json (Join-Path $dir "server.log") "RESULT"
$cr = @((Get-Json (Join-Path $dir "client0.log") "CLIENT_RESULT"), (Get-Json (Join-Path $dir "client1.log") "CLIENT_RESULT"))

$fail = @()
if ($null -eq $res) { $fail += "no server RESULT" }
foreach ($c in $cr) {
    if ($null -eq $c) { $fail += "missing CLIENT_RESULT"; continue }
    if ($null -eq $res) { continue }
    if ($c.winner -ne $res.winner) { $fail += "client$($c.index) winner mismatch" }
    if ($c.last_snapshot_me[1] -ne $res.base_hp[$c.index]) { $fail += "client$($c.index) base hp mismatch ($($c.last_snapshot_me[1]) vs $($res.base_hp[$c.index]))" }
    if ($c.last_snapshot_me[0] -ne $res.gold[$c.index]) { $fail += "client$($c.index) gold mismatch" }
    if ($c.counts.snapshots -lt 10) { $fail += "client$($c.index) too few snapshots" }
}
$errs = @(Get-ChildItem $dir -Filter *.log | Select-String -Pattern "SCRIPT ERROR|^ERROR|\] (SERVER|CLIENT\S*) ERROR" | ForEach-Object { "$($_.Filename): $($_.Line)" })
$warns = @(Get-ChildItem $dir -Filter *.log | Select-String -Pattern "^WARNING" | ForEach-Object { "$($_.Filename): $($_.Line)" })
$summary = [ordered]@{
    dir = $dir; wall_s = $wall; timescale = $TimeScale; seed = $Seed
    pass = ($fail.Count -eq 0 -and $errs.Count -eq 0); failures = $fail; engine_errors = $errs.Count; engine_warnings = $warns
    result = $res
    clients = $cr
}
[IO.File]::WriteAllText((Join-Path $dir "summary.json"), ($summary | ConvertTo-Json -Depth 8))

if ($null -ne $res) {
    Write-Host ("winner={0} reason={1} round={2} sim_time={3}s wall={4}s hp={5} gold={6} kills={7} recycled_spawns={8} merges={9}" -f `
        $res.winner, $res.reason, $res.round, $res.time, $wall, ($res.base_hp -join "/"), ($res.gold -join "/"), ($res.kills -join "/"), $res.stats.recycled_spawns, $res.stats.merges)
    Write-Host ("net: snapshots={0} avg={1}B max={2}B (naive Variant avg={3}B max={4}B) payload ~{5} B/s/client (sim time) codec_fail={6}/{7}" -f $res.net.snapshots, $res.net.avg_snapshot_bytes, $res.net.max_snapshot_bytes, $res.net.naive_variant_avg_bytes, $res.net.naive_variant_max_bytes, $res.net.snapshot_payload_bytes_per_s_per_client, $res.net.codec_failures, $res.net.codec_checks)
}
Write-Host ("PASS={0} failures={1} engine_errors={2} warnings={3} log={4}" -f $summary.pass, ($fail -join "; "), $errs.Count, $warns.Count, $dir)
if ($errs.Count -gt 0) { $errs | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" } }
