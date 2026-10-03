<#
.SYNOPSIS
  Spins up the playable TowerClash spike locally: one dedicated server plus N windowed clients
  running the full app flow (logo splash -> home -> Quick Match -> match -> home).
  Logs go to Godot/logs/play_<stamp>/ (one file per process); the terminal gets a short summary.
.EXAMPLE
  ./play_local.ps1                 # server + 2 bot clients, EOS matchmaking, loop forever
  ./play_local.ps1 -Bots 1         # you play client 0 against a bot
  ./play_local.ps1 -Bots 0         # two manual clients (press Quick Match in both)
  ./play_local.ps1 -Local          # no EOS: clients connect straight to 127.0.0.1
  ./play_local.ps1 -Exported       # use the exported builds in Godot/build/
  ./play_local.ps1 -Loops 2 -Wait  # unattended: bots play 2 matches, then summary
  ./play_local.ps1 -Loops 1 -Wait -Shots -TimeScale 2   # capture each screen of client 0
  ./play_local.ps1 -Stop           # close everything the last launch started
  -TimeScale speeds up the server sim (bots act faster to match); -ProfilePrefix keeps test
  runs from touching your client0/client1 profiles.
#>
param(
    [ValidateRange(0, 4)][int]$Clients = 2,
    [ValidateRange(0, 4)][int]$Bots = 2,
    [switch]$Local,
    [switch]$Exported,
    [int]$Loops = 0,
    [int]$Port = 7777,
    [double]$TimeScale = 1,
    [switch]$Wait,
    [int]$TimeoutSec = 900,
    [switch]$Stop,
    [switch]$Shots,
    [string]$ProfilePrefix = "client",
    [string]$Godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$proj = Split-Path $PSScriptRoot -Parent
$root = Split-Path $proj -Parent
$logRoot = Join-Path $root "logs"
$lastFile = Join-Path $logRoot "play_last.json"

function Stop-Last {
    if (-not (Test-Path $lastFile)) { return 0 }
    $n = 0
    foreach ($id in (Get-Content $lastFile -Raw | ConvertFrom-Json).pids) {
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($null -ne $p -and ($p.ProcessName -like "Godot*" -or $p.ProcessName -like "TowerClash*")) {
            Stop-Process -Id $id -Force; $n++
        }
    }
    Remove-Item $lastFile
    return $n
}
if ($Stop) { Write-Host "stopped $(Stop-Last) process(es)"; return }
[void](Stop-Last)

$dir = Join-Path $logRoot ("play_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $dir | Out-Null

$creds = Join-Path $proj "eos_credentials.local.json"
$useEos = (-not $Local) -and (Test-Path $creds)
if (-not $Local -and -not $useEos) { Write-Host "no eos_credentials.local.json - falling back to -Local" }

$serverExe = ""; $clientExe = ""
if ($Exported) {
    $serverExe = Join-Path $root "build\windows_server\TowerClashSpikeServer.exe"
    $clientExe = Join-Path $root "build\windows_client\TowerClashSpike.exe"
    foreach ($e in $serverExe, $clientExe) { if (-not (Test-Path $e)) { throw "missing $e - export first (see Docs/Godot_Spike.md)" } }
    if ($useEos) {
        # Each build gets only the credentials its role needs.
        $c = Get-Content $creds -Raw | ConvertFrom-Json
        $common = [ordered]@{ product_id = $c.product_id; sandbox_id = $c.sandbox_id; deployment_id = $c.deployment_id; encryption_key = $c.encryption_key }
        $sc = [ordered]@{} + $common; $sc.server_client_id = $c.server_client_id; $sc.server_client_secret = $c.server_client_secret
        $cc = [ordered]@{} + $common; $cc.client_id = $c.client_id; $cc.client_secret = $c.client_secret
        $enc = New-Object Text.UTF8Encoding $false
        [IO.File]::WriteAllText((Join-Path (Split-Path $serverExe) "eos_credentials.local.json"), ($sc | ConvertTo-Json), $enc)
        [IO.File]::WriteAllText((Join-Path (Split-Path $clientExe) "eos_credentials.local.json"), ($cc | ConvertTo-Json), $enc)
    }
}

function Start-Godot([string]$name, [string[]]$godotArgs, [string[]]$userArgs, [string]$exe) {
    if ($exe -eq "") { $exe = $Godot; $godotArgs = @("--path", "`"$proj`"") + $godotArgs }
    Start-Process -FilePath $exe -ArgumentList ($godotArgs + @("--") + $userArgs) -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $dir "$name.log") -RedirectStandardError (Join-Path $dir "$name.err.log")
}

$sa = @("--server", "--port=$Port", "--timescale=$TimeScale")
if ($useEos) { $sa += "--eos" }
# All-bot runs with a loop count are finite: let the server shut itself down (destroying its EOS
# session) instead of being killed, which can leave a stale advertised session behind.
$finite = $Loops -gt 0 -and $Bots -ge $Clients
if ($finite) { $sa += "--max-matches=$Loops" }
$server = Start-Godot "server" @("--headless") $sa $serverExe
$procs = @($server)
if ($useEos) {
    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Select-String -Path (Join-Path $dir "server.log") -Pattern "EOS session advertised|EOS ERROR" -Quiet) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
} else { Start-Sleep -Milliseconds 800 }

for ($i = 0; $i -lt $Clients; $i++) {
    $isBot = $i -ge ($Clients - $Bots)
    $name = $(if ($isBot) { "Bot$i" } else { "Player$i" })
    $ua = @("--profile=$ProfilePrefix$i", "--name=$name")
    if ($isBot) { $ua += @("--bot", "--bot-speed=$TimeScale"); if ($Loops -gt 0) { $ua += "--loops=$Loops" } }
    if ($useEos) { $ua += "--online" } else { $ua += "--local=127.0.0.1:$Port" }
    if ($Shots -and $i -eq 0) { $ua += "--app-shots=$(Join-Path $dir 'shots')" }
    $ga = @("--position", "$(40 + $i * 580),40")
    $procs += Start-Godot "client$i" $ga $ua $clientExe
    Start-Sleep -Milliseconds 400
}
[IO.File]::WriteAllText($lastFile, (@{ dir = $dir; pids = @($procs | ForEach-Object { $_.Id }) } | ConvertTo-Json))
Write-Host ("launched server + {0} client(s) ({1} bot) via {2}{3}; logs {4}" -f $Clients, $Bots, $(if ($useEos) { "EOS" } else { "direct 127.0.0.1:$Port" }), $(if ($Exported) { ", exported builds" } else { "" }), $dir)
if (-not $Wait) { Write-Host "close the client windows when done, then: ./play_local.ps1 -Stop"; return }

# -Wait: block until the clients exit (bots with -Loops quit on their own), then summarise.
$deadline = (Get-Date).AddSeconds($TimeoutSec)
foreach ($p in $procs[1..($procs.Count - 1)]) {
    $left = [int][math]::Max(1, ($deadline - (Get-Date)).TotalMilliseconds)
    [void]$p.WaitForExit($left)
}
$cleanExit = $false
if ($finite) { $cleanExit = $server.WaitForExit(20000) }
$n = Stop-Last
$played = @(Select-String -Path (Join-Path $dir "server.log") -Pattern "\] SERVER RESULT ").Count
$recorded = @(Get-ChildItem $dir -Filter "client*.log" | Select-String -Pattern "APP match \d+ recorded").Count
$done = @(Get-ChildItem $dir -Filter "client*.log" | Select-String -Pattern "APP done").Count
$errs = @(Get-ChildItem $dir -Filter *.log | Select-String -Pattern "SCRIPT ERROR|^ERROR|\] (SERVER|CLIENT\S*) ERROR|EOS ERROR" | ForEach-Object { "$($_.Filename): $($_.Line)" })
$eosStates = @(Select-String -Path (Join-Path $dir "server.log") -Pattern "EOS session state -> (\w+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) -join ","
$pass = $errs.Count -eq 0 -and ($Loops -eq 0 -or ($done -eq $Bots -and $played -ge $Loops)) -and (-not $finite -or $cleanExit)
Write-Host ("PASS={0} server_matches={1} client_records={2} bots_done={3}/{4} eos_states=[{5}] server_clean_exit={6} errors={7} killed={8} log={9}" -f $pass, $played, $recorded, $done, $Bots, $eosStates, $cleanExit, $errs.Count, $n, $dir)
$errs | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
