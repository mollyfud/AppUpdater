# updater-admin.ps1 - shared helpers for grant-access.ps1 and set-listing.ps1 (dot-source it).
# Reads the gateway URL and admin token from env vars or updater.toml; never prints the token.
# ASCII-only for Windows PowerShell 5.1 compatibility.

function Read-UpdaterConfig {
    param([string]$ConfigPath)
    $cfg = @{}
    if ($ConfigPath -and (Test-Path -Path $ConfigPath)) {
        foreach ($line in (Get-Content -Path $ConfigPath)) {
            $trimmed = $line.Trim()
            if ($trimmed -and -not $trimmed.StartsWith("#") -and -not $trimmed.StartsWith("[")) {
                if ($trimmed -match '^([A-Za-z0-9_.-]+)\s*=\s*"([^"]*)"') {
                    $cfg[$Matches[1]] = $Matches[2]
                } elseif ($trimmed -match "^([A-Za-z0-9_.-]+)\s*=\s*'([^']*)'") {
                    $cfg[$Matches[1]] = $Matches[2]
                }
            }
        }
    }
    return $cfg
}

function Get-UpdaterAdminContext {
    param([string]$GatewayUrl, [string]$ConfigPath)
    $cfg = Read-UpdaterConfig -ConfigPath $ConfigPath
    if (-not $GatewayUrl) {
        $GatewayUrl = if ($env:APP_UPDATER_URL) { $env:APP_UPDATER_URL } elseif ($cfg.ContainsKey("gateway_url")) { $cfg["gateway_url"] } else { "" }
    }
    $token = if ($env:APP_UPDATER_ADMIN_TOKEN) { $env:APP_UPDATER_ADMIN_TOKEN } elseif ($cfg.ContainsKey("admin_token")) { $cfg["admin_token"] } else { "" }
    if (-not $GatewayUrl) {
        throw "No gateway URL. Pass -GatewayUrl, set APP_UPDATER_URL, or add gateway_url = ""https://..."" to $ConfigPath."
    }
    if (-not $token) {
        throw "No admin token. Set APP_UPDATER_ADMIN_TOKEN or add admin_token = ""..."" to $ConfigPath (same value as the Worker secret APP_UPDATER_ADMIN_TOKEN)."
    }
    return @{ Url = $GatewayUrl.TrimEnd("/"); Token = $token }
}

function Invoke-UpdaterAdmin {
    param(
        [hashtable]$Context,
        [string]$Method,
        [string]$Path,
        $Body = $null
    )
    $params = @{
        Uri         = "$($Context.Url)$Path"
        Method      = $Method
        Headers     = @{ Authorization = "Bearer $($Context.Token)" }
        TimeoutSec  = 30
        ErrorAction = "Stop"
    }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 5 -Compress
        $params["Body"] = [System.Text.Encoding]::UTF8.GetBytes($json)
        $params["ContentType"] = "application/json; charset=utf-8"
    }
    try {
        return Invoke-RestMethod @params
    } catch {
        $detail = $_.ErrorDetails.Message
        if (-not $detail) { $detail = $_.Exception.Message }
        throw "$Method $Path failed: $detail"
    }
}
