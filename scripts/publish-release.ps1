# publish-release.ps1 - Generate version.json (if needed), upload APK + manifest to Cloudflare R2,
# and optionally send an ntfy push notification.
# ASCII-only for Windows PowerShell 5.1 compatibility.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias("ProjectPath")]
    [string]$ProjectDir,

    [string]$AppId = "",
    [string]$ProjectName = "",
    [string]$ApkPath = "",
    [string]$VersionName = "",
    [int]$VersionCode = 0,
    [int]$MinRequiredVersionCode = 1,
    [string]$ReleaseNotes = "",
    [string]$BucketName = "private-app-releases",
    [string]$ConfigPath = "$env:LOCALAPPDATA\Switchboard\updater.toml",
    [switch]$ManifestOnly = $false,
    [switch]$DryRun = $false,
    [switch]$SkipNtfy = $false
)

$ErrorActionPreference = "Stop"

$resolvedProject = (Resolve-Path -Path $ProjectDir).Path
if (-not $ProjectName) {
    $ProjectName = Split-Path -Path $resolvedProject -Leaf
}

# 1. Read optional updater.toml (holds r2_endpoint, bucket_name, ntfy_url, ntfy_topic, etc.)
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

if ($cfg.ContainsKey("bucket_name") -and $cfg["bucket_name"]) {
    $BucketName = $cfg["bucket_name"]
}

# 2. Discover AppId, VersionName, and VersionCode from project files if not passed explicitly
$gradleFiles = @(
    (Join-Path $resolvedProject "app\build.gradle.kts"),
    (Join-Path $resolvedProject "android\app\build.gradle.kts"),
    (Join-Path $resolvedProject "android\app\build.gradle")
)
foreach ($gf in $gradleFiles) {
    if (Test-Path -Path $gf) {
        $gContent = Get-Content -Path $gf -Raw
        if (-not $AppId -and ($gContent -match 'applicationId\s*=?\s*["'']([^"'']+)["'']')) {
            $AppId = $Matches[1].Trim()
        }
        if (-not $VersionName -and ($gContent -match 'versionName\s*=\s*["'']([^"'']+)["'']')) {
            $VersionName = $Matches[1].Trim()
        }
        if ($VersionCode -le 0 -and ($gContent -match 'versionCode\s*=\s*(\d+)')) {
            $VersionCode = [int]$Matches[1]
        }
    }
}

# Search pubspec.yaml for Flutter projects if VersionName/VersionCode still missing
$pubspecCandidates = @(
    (Join-Path $resolvedProject "pubspec.yaml")
)
if (Test-Path (Join-Path $resolvedProject "packages")) {
    $pubspecCandidates += Get-ChildItem -Path (Join-Path $resolvedProject "packages") -Filter "pubspec.yaml" -Recurse -Depth 2 | ForEach-Object { $_.FullName }
}
$pubspecCandidates += Get-ChildItem -Path $resolvedProject -Filter "pubspec.yaml" -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }

foreach ($pub in $pubspecCandidates) {
    if (Test-Path -Path $pub) {
        $pContent = Get-Content -Path $pub -Raw
        if ($pContent -match '(?m)^version:\s*([^+\s#]+)(?:\+(\d+))?') {
            if (-not $VersionName) { $VersionName = $Matches[1].Trim() }
            if ($VersionCode -le 0 -and $Matches[2]) { $VersionCode = [int]$Matches[2] }
        }
        $subGradle = Join-Path (Split-Path -Path $pub -Parent) "android\app\build.gradle"
        $subGradleKts = Join-Path (Split-Path -Path $pub -Parent) "android\app\build.gradle.kts"
        foreach ($sg in @($subGradle, $subGradleKts)) {
            if (-not $AppId -and (Test-Path -Path $sg)) {
                $sgContent = Get-Content -Path $sg -Raw
                if ($sgContent -match 'applicationId\s*=?\s*["'']([^"'']+)["'']') {
                    $AppId = $Matches[1].Trim()
                }
            }
        }
    }
}

if (-not $VersionName) { $VersionName = "0.1.0" }
if ($VersionCode -le 0) { $VersionCode = 1 }
if (-not $AppId) {
    $safeSlug = ($ProjectName.ToLower() -replace '[^a-z0-9]', '')
    $AppId = "com.molly.$safeSlug"
}

# 3. Locate APK in dist/ if not passed explicitly
$distDir = Join-Path $resolvedProject "dist"
if (-not $ApkPath) {
    $expectedDistApk = Join-Path $distDir "$ProjectName-v$VersionName.apk"
    if (Test-Path -Path $expectedDistApk) {
        $ApkPath = $expectedDistApk
    } elseif (Test-Path -Path $distDir) {
        $latestApk = Get-ChildItem -Path $distDir -Filter "*.apk" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestApk) { $ApkPath = $latestApk.FullName }
    }
}

if (-not $ApkPath -or -not (Test-Path -Path $ApkPath)) {
    throw "APK file not found. Build the APK first (build-apk.ps1) or pass -ApkPath."
}
$ApkPath = (Resolve-Path -Path $ApkPath).Path

# 4. Extract latest CHANGELOG.md section if ReleaseNotes not provided
if (-not $ReleaseNotes) {
    $changelogPath = Join-Path $resolvedProject "CHANGELOG.md"
    if (Test-Path -Path $changelogPath) {
        $lines = Get-Content -Path $changelogPath
        $inLatest = $false
        $collected = @()
        foreach ($line in $lines) {
            if ($line -match '^##\s+') {
                if ($inLatest) { break }
                $inLatest = $true
                continue
            }
            if ($inLatest -and $line.Trim()) {
                $collected += $line.Trim()
                if ($collected.Count -ge 8) { break }
            }
        }
        if ($collected.Count -gt 0) {
            $ReleaseNotes = ($collected -join "`n")
        }
    }
}
if (-not $ReleaseNotes) {
    $ReleaseNotes = "Release $ProjectName v$VersionName (build $VersionCode)."
}

# 5. Compute SHA-256 and file size
$hashObj = Get-FileHash -Path $ApkPath -Algorithm SHA256
$sha256 = $hashObj.Hash.ToLower()
$fileSize = (Get-Item -Path $ApkPath).Length
$apkFileName = Split-Path -Path $ApkPath -Leaf
$apkKey = "$AppId/builds/$apkFileName"
$releaseDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# 6. Write dist/version.json matching contract app-updater/1
if (-not (Test-Path -Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}
$manifestPath = Join-Path $distDir "version.json"

$manifest = [ordered]@{
    schema                 = "app-updater/1"
    appId                  = $AppId
    project                = $ProjectName
    versionName            = $VersionName
    versionCode            = $VersionCode
    minRequiredVersionCode = $MinRequiredVersionCode
    releaseDate            = $releaseDate
    releaseNotes           = $ReleaseNotes
    apkKey                 = $apkKey
    sha256                 = $sha256
    fileSize               = $fileSize
}

$manifestJson = $manifest | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "[$([char]0x2713)] Wrote manifest: $manifestPath" -ForegroundColor Green
Write-Host "    AppId:   $AppId ($ProjectName)"
Write-Host "    Version: $VersionName+$VersionCode"
Write-Host "    SHA256:  $sha256 ($fileSize bytes)"

if ($ManifestOnly) {
    return
}

if ($DryRun) {
    Write-Host "[DryRun] Would upload $ApkPath -> r2://$BucketName/$apkKey" -ForegroundColor Yellow
    Write-Host "[DryRun] Would upload $manifestPath -> r2://$BucketName/$AppId/version.json" -ForegroundColor Yellow
    return
}

# 7. Upload to Cloudflare R2 (via wrangler r2 object put, or aws s3 cp if R2_ENDPOINT is configured)
$r2Endpoint = if ($env:R2_ENDPOINT) { $env:R2_ENDPOINT } elseif ($cfg.ContainsKey("r2_endpoint")) { $cfg["r2_endpoint"] } else { "" }
$wranglerCmd = Get-Command "wrangler" -ErrorAction SilentlyContinue
$npxCmd = Get-Command "npx" -ErrorAction SilentlyContinue
$awsCmd = Get-Command "aws" -ErrorAction SilentlyContinue

if ($r2Endpoint -and $awsCmd) {
    Write-Host "[*] Uploading APK and version.json to R2 via AWS S3 CLI ($r2Endpoint)..." -ForegroundColor Cyan
    & aws s3 cp $ApkPath "s3://$BucketName/$apkKey" --endpoint-url $r2Endpoint --content-type "application/vnd.android.package-archive"
    if ($LASTEXITCODE -ne 0) { throw "Failed to upload APK to R2 via aws s3 cp (exit $LASTEXITCODE)" }
    & aws s3 cp $manifestPath "s3://$BucketName/$AppId/version.json" --endpoint-url $r2Endpoint --content-type "application/json"
    if ($LASTEXITCODE -ne 0) { throw "Failed to upload version.json to R2 via aws s3 cp (exit $LASTEXITCODE)" }
} elseif ($wranglerCmd -or $npxCmd) {
    Write-Host "[*] Uploading APK and version.json to R2 via Cloudflare Wrangler..." -ForegroundColor Cyan
    if ($wranglerCmd) {
        & wrangler r2 object put "$BucketName/$apkKey" --file $ApkPath --content-type "application/vnd.android.package-archive" --remote
        if ($LASTEXITCODE -ne 0) { throw "wrangler r2 object put APK failed (exit $LASTEXITCODE)" }
        & wrangler r2 object put "$BucketName/$AppId/version.json" --file $manifestPath --content-type "application/json" --remote
        if ($LASTEXITCODE -ne 0) { throw "wrangler r2 object put version.json failed (exit $LASTEXITCODE)" }
    } else {
        & npx wrangler r2 object put "$BucketName/$apkKey" --file $ApkPath --content-type "application/vnd.android.package-archive" --remote
        if ($LASTEXITCODE -ne 0) { throw "npx wrangler r2 object put APK failed (exit $LASTEXITCODE)" }
        & npx wrangler r2 object put "$BucketName/$AppId/version.json" --file $manifestPath --content-type "application/json" --remote
        if ($LASTEXITCODE -ne 0) { throw "npx wrangler r2 object put version.json failed (exit $LASTEXITCODE)" }
    }
} else {
    throw "Neither Cloudflare Wrangler (wrangler/npx) nor AWS CLI (with r2_endpoint) is available to upload to R2."
}

Write-Host "[$([char]0x2713)] Published $ProjectName v$VersionName+$VersionCode to R2 bucket '$BucketName'." -ForegroundColor Green

# 8. Send instant ntfy notification (D-0003)
$ntfyTopic = if ($env:SWITCHBOARD_NTFY_TOPIC) { $env:SWITCHBOARD_NTFY_TOPIC } elseif ($cfg.ContainsKey("ntfy_topic")) { $cfg["ntfy_topic"] } else { "" }
$ntfyServer = if ($cfg.ContainsKey("ntfy_server") -and $cfg["ntfy_server"]) { $cfg["ntfy_server"].TrimEnd("/") } else { "https://ntfy.sh" }

if (-not $SkipNtfy -and $ntfyTopic) {
    try {
        $ntfyUri = "$ntfyServer/$ntfyTopic"
        $headers = @{
            "Title"    = "App Update: $ProjectName v$VersionName"
            "Priority" = "default"
            "Tags"     = "iphone,up"
        }
        $body = "New Android APK published for $ProjectName (v$VersionName, build $VersionCode).`nOpen the app to install the update.`n`n$ReleaseNotes"
        Invoke-RestMethod -Uri $ntfyUri -Method Post -Headers $headers -Body $body -ContentType "text/plain; charset=utf-8" -TimeoutSec 10 | Out-Null
        Write-Host "[$([char]0x2713)] Sent ntfy notification to topic." -ForegroundColor Cyan
    } catch {
        Write-Warning "Uploaded to R2, but ntfy push failed: $_"
    }
}
