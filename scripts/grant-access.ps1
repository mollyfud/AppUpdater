# grant-access.ps1 - give one person their own access token for some apps, list grants, or revoke one.
# The Worker stores only a hash of the token; the token and invite link are shown ONCE here.
# Examples:
#   .\grant-access.ps1 -Name Sam -Apps com.hawkspod.tennisspark_app -Days 180 -Note "tennis club"
#   .\grant-access.ps1 -List
#   .\grant-access.ps1 -Revoke Sam        (or the 16-char grant id from -List)
# Config: gateway_url and admin_token in updater.toml, or env APP_UPDATER_URL / APP_UPDATER_ADMIN_TOKEN.
# ASCII-only for Windows PowerShell 5.1 compatibility.
[CmdletBinding(DefaultParameterSetName = "Create")]
param(
    [Parameter(ParameterSetName = "Create", Mandatory = $true)]
    [string]$Name,

    [Parameter(ParameterSetName = "Create", Mandatory = $true)]
    [string[]]$Apps,

    [Parameter(ParameterSetName = "Create")]
    [int]$Days = 0,

    [Parameter(ParameterSetName = "Create")]
    [string]$Note = "",

    [Parameter(ParameterSetName = "Create")]
    [switch]$NoClipboard,

    [Parameter(ParameterSetName = "List", Mandatory = $true)]
    [switch]$List,

    [Parameter(ParameterSetName = "Revoke", Mandatory = $true)]
    [string]$Revoke,

    [string]$GatewayUrl = "",
    [string]$ConfigPath = "$env:LOCALAPPDATA\Switchboard\updater.toml"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "updater-admin.ps1")
$ctx = Get-UpdaterAdminContext -GatewayUrl $GatewayUrl -ConfigPath $ConfigPath

# PowerShell 7 turns ISO strings in JSON into DateTime; 5.1 keeps strings. Show yyyy-MM-dd either way.
function Format-Day($value) {
    if ($value -is [datetime]) { return $value.ToUniversalTime().ToString("yyyy-MM-dd") }
    return "$value".Substring(0, [Math]::Min(10, "$value".Length))
}

function Format-Grant($g) {
    $state = if ($g.revoked) { "revoked" } elseif ($g.live -eq $false) { "expired" } else { "live" }
    $exp = if ($g.expires) { Format-Day $g.expires } else { "never" }
    return [pscustomobject]@{
        Id      = $g.id
        Name    = $g.name
        State   = $state
        Apps    = ($g.apps -join ", ")
        Expires = $exp
        Created = Format-Day $g.created
        Note    = $g.note
    }
}

if ($PSCmdlet.ParameterSetName -eq "List") {
    $res = Invoke-UpdaterAdmin -Context $ctx -Method GET -Path "/api/v1/admin/grants"
    if (-not $res.grants -or @($res.grants).Count -eq 0) {
        Write-Host "No grants yet."
        return
    }
    @($res.grants) | ForEach-Object { Format-Grant $_ } | Format-Table -AutoSize
    return
}

if ($PSCmdlet.ParameterSetName -eq "Revoke") {
    $id = $Revoke.Trim()
    if ($id -notmatch '^[a-f0-9]{16}$') {
        $res = Invoke-UpdaterAdmin -Context $ctx -Method GET -Path "/api/v1/admin/grants"
        $found = @(@($res.grants) | Where-Object { $_.name -eq $id -and -not $_.revoked })
        if ($found.Count -eq 0) { throw "No unrevoked grant named '$id'. Use -List to see grants." }
        if ($found.Count -gt 1) {
            $found | ForEach-Object { Format-Grant $_ } | Format-Table -AutoSize | Out-String | Write-Host
            throw "More than one grant is named '$id'; pass its Id instead."
        }
        $id = $found[0].id
    }
    $res = Invoke-UpdaterAdmin -Context $ctx -Method POST -Path "/api/v1/admin/grants/$id/revoke" -Body @{}
    Write-Host "[OK] Revoked grant $($res.grant.id) ($($res.grant.name)). Their apps stop updating on the next check." -ForegroundColor Green
    return
}

# Create
$appList = @($Apps | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$body = @{ name = $Name; apps = [string[]]$appList }
if ($Days -gt 0) { $body["days"] = $Days }
if ($Note) { $body["note"] = $Note }

$res = Invoke-UpdaterAdmin -Context $ctx -Method POST -Path "/api/v1/admin/grants" -Body $body

Write-Host "[OK] Created grant $($res.grant.id) for $($res.grant.name)" -ForegroundColor Green
Write-Host "    Apps:    $($res.grant.apps -join ', ')"
$expText = if ($res.grant.expires) { Format-Day $res.grant.expires } else { "never" }
Write-Host "    Expires: $expText"
foreach ($w in @($res.warnings)) {
    if ($w) { Write-Warning $w }
}
Write-Host ""
Write-Host "Send this invite link to $Name (it contains their token). It is shown only now:" -ForegroundColor Yellow
Write-Host "    $($res.inviteUrl)"
Write-Host "Token on its own (for the app's Settings):"
Write-Host "    $($res.token)"
if (-not $NoClipboard) {
    try {
        Set-Clipboard -Value $res.inviteUrl
        Write-Host "(Invite link copied to the clipboard.)" -ForegroundColor Cyan
    } catch {
        Write-Warning "Could not copy to the clipboard: $_"
    }
}
