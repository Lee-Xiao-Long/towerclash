<#
.SYNOPSIS
  Downloads the EOSG (Epic Online Services Godot) GDExtension release into addons/.
  The addon is git-ignored; run this once per checkout.
.EXAMPLE
  ./get_eosg.ps1                    # Windows binaries
  ./get_eosg.ps1 -Platform all      # every platform (~165 MB)
#>
param(
    [string]$Version = "2.3.1",
    [ValidateSet("windows", "linux", "android", "ios", "macos", "all")][string]$Platform = "windows"
)
$ErrorActionPreference = "Stop"
$proj = Split-Path $PSScriptRoot -Parent
$rel = Invoke-RestMethod "https://api.github.com/repos/3ddelano/epic-online-services-godot/releases/tags/$Version"
$asset = $rel.assets | Where-Object { $_.name -like "epic-online-services-godot-$Platform-*.zip" } | Select-Object -First 1
if ($null -eq $asset) { throw "No $Platform asset in EOSG $Version" }
$zip = Join-Path $env:TEMP $asset.name
$tmp = Join-Path $env:TEMP "eosg_$Platform"
curl.exe -sL -o $zip $asset.browser_download_url
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive $zip $tmp
New-Item -ItemType Directory -Force (Join-Path $proj "addons") | Out-Null
Copy-Item (Join-Path $tmp "epic-online-services-godot\addons\epic-online-services-godot") (Join-Path $proj "addons") -Recurse -Force
Get-ChildItem (Join-Path $proj "addons\epic-online-services-godot\bin") -Recurse -Filter *.pdb | Remove-Item
Write-Host "EOSG $Version ($Platform) installed. Run a headless --import so Godot registers the extension."
