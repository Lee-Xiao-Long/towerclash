<#
.SYNOPSIS
  Builds the TowerClash spike server container image (towerclash-server:dev):
  exports the "Linux Server" preset, writes server-only EOS credentials next to compose.yaml,
  then docker build with Godot/ as the context. Verbose output: Godot/logs/image_build.log.
.EXAMPLE
  ./build_image.ps1
  ./build_image.ps1 -SkipExport
#>
param(
    [switch]$SkipExport,
    [string]$Tag = "towerclash-server:dev",
    [string]$Godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$godotDir = Split-Path $here -Parent
$proj = Join-Path $godotDir "TowerClashSpike"
$log = Join-Path $godotDir "logs\image_build.log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null

if (-not $SkipExport) {
    $p = Start-Process $Godot -ArgumentList @("--headless", "--path", "`"$proj`"", "--export-release", "`"Linux Server`"") -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    if ($p.ExitCode -ne 0) { throw "Linux export failed (exit $($p.ExitCode)), see $log" }
    if (-not (Test-Path (Join-Path $godotDir "build\linux_server\libEOSSDK-Linux-Shipping.so"))) {
        throw "EOS libs missing next to the Linux export. Run TowerClashSpike/tools/get_eosg.ps1 -Platform linux, then re-run."
    }
}

# Server-only credentials: the DedicatedServer client id/secret plus the shared product ids.
$creds = Join-Path $proj "eos_credentials.local.json"
if (Test-Path $creds) {
    $c = Get-Content $creds -Raw | ConvertFrom-Json
    $sc = [ordered]@{ product_id = $c.product_id; sandbox_id = $c.sandbox_id; deployment_id = $c.deployment_id
        encryption_key = $c.encryption_key; server_client_id = $c.server_client_id; server_client_secret = $c.server_client_secret }
    [IO.File]::WriteAllText((Join-Path $here "eos_server_credentials.local.json"), ($sc | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
} else {
    Write-Host "no $creds - the container can only run with EOS=0"
}

# Through cmd so docker's progress on stderr is not a terminating error under ErrorActionPreference=Stop.
cmd /c "docker build -f `"$(Join-Path $here 'Dockerfile')`" -t $Tag `"$godotDir`" >> `"$log`" 2>&1"
if ($LASTEXITCODE -ne 0) { throw "docker build failed, see $log" }
$size = docker image inspect $Tag --format "{{.Size}}"
Write-Host ("built {0} ({1} MB); log {2}" -f $Tag, [math]::Round([double]$size / 1MB), $log)
