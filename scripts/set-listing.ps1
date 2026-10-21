# set-listing.ps1 - mark an app shareable (or not) and set its store title/summary, or list all apps.
# Grants only see apps marked shareable. Stored at <appId>/listing.json; publish-release.ps1 never touches it.
# Examples:
#   .\set-listing.ps1 -AppId com.hawkspod.tennisspark_app -Shareable -Title "TennisSpark" -Summary "Tennis club scores"
#   .\set-listing.ps1 -AppId com.hawkspod.tennisspark_app -Unshare
#   .\set-listing.ps1 -List
# Config: gateway_url and admin_token in updater.toml, or env APP_UPDATER_URL / APP_UPDATER_ADMIN_TOKEN.
# ASCII-only for Windows PowerShell 5.1 compatibility.
[CmdletBinding(DefaultParameterSetName = "Set")]
param(
    [Parameter(ParameterSetName = "Set", Mandatory = $true)]
    [string]$AppId,

    [Parameter(ParameterSetName = "Set")]
    [switch]$Shareable,

    [Parameter(ParameterSetName = "Set")]
    [switch]$Unshare,

    [Parameter(ParameterSetName = "Set")]
    [string]$Title = "",

    [Parameter(ParameterSetName = "Set")]
    [string]$Summary = "",

    [Parameter(ParameterSetName = "List", Mandatory = $true)]
    [switch]$List,

    [string]$GatewayUrl = "",
    [string]$ConfigPath = "$env:LOCALAPPDATA\Switchboard\updater.toml"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "updater-admin.ps1")
$ctx = Get-UpdaterAdminContext -GatewayUrl $GatewayUrl -ConfigPath $ConfigPath

if ($PSCmdlet.ParameterSetName -eq "List") {
    $res = Invoke-UpdaterAdmin -Context $ctx -Method GET -Path "/api/v1/admin/apps"
    @($res.apps) | ForEach-Object {
        [pscustomobject]@{
            AppId     = $_.appId
            Title     = $_.title
            Version   = "$($_.versionName)+$($_.versionCode)"
            Shareable = $_.shareable
            Summary   = $_.summary
        }
    } | Format-Table -AutoSize
    return
}

if ($Shareable -eq $Unshare) {
    throw "Pass exactly one of -Shareable or -Unshare."
}

$body = @{ shareable = [bool]$Shareable }
if ($Title) { $body["title"] = $Title }
if ($Summary) { $body["summary"] = $Summary }

$res = Invoke-UpdaterAdmin -Context $ctx -Method PUT -Path "/api/v1/admin/listing/$([uri]::EscapeDataString($AppId))" -Body $body
$state = if ($res.listing.shareable) { "shareable" } else { "not shared" }
Write-Host "[OK] $($res.listing.appId) is now $state." -ForegroundColor Green
if ($res.listing.title) { Write-Host "    Title:   $($res.listing.title)" }
if ($res.listing.summary) { Write-Host "    Summary: $($res.listing.summary)" }
foreach ($w in @($res.warnings)) {
    if ($w) { Write-Warning $w }
}
