<#
.SYNOPSIS
  Copies the EOS product/client credentials from the UE project's Config into a git-ignored
  eos_credentials.local.json next to project.godot. Values are never printed.
#>
param([string]$UEConfig = "D:\Dev\Unreal\Source5.7\Games\TowerClash\Config")
$ErrorActionPreference = "Stop"
$proj = Split-Path $PSScriptRoot -Parent

function Get-IniValue([string]$file, [string]$key) {
    $m = Select-String -Path $file -Pattern "^\s*$key\s*=\s*(.+?)\s*$" | Select-Object -First 1
    if ($null -eq $m) { return "" }
    return $m.Matches[0].Groups[1].Value
}
$eng = Join-Path $UEConfig "DefaultEngine.ini"
$ded = Join-Path $UEConfig "DedicatedServerEngine.ini"
$c = [ordered]@{
    product_id = Get-IniValue $eng "ProductId"
    sandbox_id = Get-IniValue $eng "SandboxId"
    deployment_id = Get-IniValue $eng "DeploymentId"
    client_id = Get-IniValue $eng "ClientId"
    client_secret = Get-IniValue $eng "ClientSecret"
    encryption_key = Get-IniValue $eng "PlayerDataEncryptionKey"
    server_client_id = Get-IniValue $ded "DedicatedServerClientId"
    server_client_secret = Get-IniValue $ded "DedicatedServerClientSecret"
}
$missing = @($c.Keys | Where-Object { $c[$_] -eq "" })
$out = Join-Path $proj "eos_credentials.local.json"
[IO.File]::WriteAllText($out, ($c | ConvertTo-Json))
Write-Host ("wrote {0} (missing: {1})" -f $out, ($(if ($missing.Count) { $missing -join ", " } else { "none" })))
