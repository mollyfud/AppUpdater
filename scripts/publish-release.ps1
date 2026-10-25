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
    [switch]$SkipNtfy = $false,
    [string]$Aapt2Path = "",
    [switch]$SkipApkCheck = $false
)

$ErrorActionPreference = "Stop"
$PublisherVersion = "0.2.0"
Write-Host "publish-release $PublisherVersion"

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

function Find-Aapt2 {
    param([string]$Explicit, [hashtable]$Config, [ref]$Searched)
    $list = @()
    if ($Explicit) {
        $list += $Explicit
        $Searched.Value += "-Aapt2Path"
    }
    if ($Config.ContainsKey("aapt2_path") -and $Config["aapt2_path"]) {
        $list += $Config["aapt2_path"]
        $Searched.Value += "aapt2_path in updater.toml"
    }
    foreach ($c in $list) {
        if (Test-Path -Path $c -PathType Leaf) { return (Resolve-Path -Path $c).Path }
    }
    $onPath = Get-Command "aapt2" -ErrorAction SilentlyContinue
    $Searched.Value += "PATH"
    if ($onPath) { return $onPath.Source }
    $sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
    if ($env:LOCALAPPDATA) { $sdkRoots += (Join-Path $env:LOCALAPPDATA "Android\Sdk") }
    foreach ($root in $sdkRoots) {
        if (-not $root) { continue }
        $bt = Join-Path $root "build-tools"
        $Searched.Value += $bt
        if (-not (Test-Path -Path $bt)) { continue }
        $versions = @()
        foreach ($d in (Get-ChildItem -Path $bt -Directory -ErrorAction SilentlyContinue)) {
            $parsed = $null
            if ([version]::TryParse($d.Name, [ref]$parsed)) {
                $exe = Join-Path $d.FullName "aapt2.exe"
                if (Test-Path -Path $exe) { $versions += [pscustomobject]@{ Version = $parsed; Path = $exe } }
            }
        }
        if ($versions.Count -gt 0) {
            return ($versions | Sort-Object Version -Descending | Select-Object -First 1).Path
        }
    }
    return $null
}

function Get-ApkBadging {
    param([string]$Aapt2, [string]$Apk)
    $out = & $Aapt2 dump badging $Apk 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "aapt2 dump badging failed (exit $LASTEXITCODE) for ${Apk}: $($out -join ' ')"
    }
    foreach ($l in $out) {
        $s = "$l"
        if ($s -match '^package:') {
            if ($s -match "name='([^']*)'" ) { $n = $Matches[1] } else { $n = $null }
            if ($s -match "versionCode='(\d+)'") { $c = $Matches[1] } else { $c = $null }
            if ($s -match "versionName='([^']*)'") { $v = $Matches[1] } else { $v = $null }
            if ($null -eq $n -or $null -eq $c -or $null -eq $v) {
                throw "Could not parse name/versionCode/versionName from aapt2 output: $s"
            }
            return [pscustomobject]@{ Package = $n; VersionCode = [int]$c; VersionName = $v }
        }
    }
    throw "aapt2 dump badging printed no package line for $Apk"
}

# 3. Locate APK in dist/ if not passed explicitly
$apkFromFallback = $false
$distDir = Join-Path $resolvedProject "dist"
if (-not $ApkPath) {
    $expectedDistApk = Join-Path $distDir "$ProjectName-v$VersionName.apk"
    if (Test-Path -Path $expectedDistApk) {
        $ApkPath = $expectedDistApk
    } elseif (Test-Path -Path $distDir) {
        $latestApk = Get-ChildItem -Path $distDir -Filter "*.apk" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestApk) {
            $ApkPath = $latestApk.FullName
            $apkFromFallback = $true
            Write-Host "[!] Expected $expectedDistApk was not found; using the newest APK in dist/ instead: $($latestApk.FullName)" -ForegroundColor Yellow
        }
    }
}

if (-not $ApkPath -or -not (Test-Path -Path $ApkPath)) {
    throw "APK file not found. Build the APK first (build-apk.ps1) or pass -ApkPath."
}
$ApkPath = (Resolve-Path -Path $ApkPath).Path

# 3b. Check the APK's real package/versionCode/versionName against the manifest (aapt2 dump badging)
if ($SkipApkCheck) {
    Write-Host "[!] -SkipApkCheck: the APK was NOT verified against the manifest." -ForegroundColor Yellow
} else {
    $aapt2Searched = @()
    $aapt2 = Find-Aapt2 -Explicit $Aapt2Path -Config $cfg -Searched ([ref]$aapt2Searched)
    if (-not $aapt2) {
        throw ("aapt2 (Android build-tools) was not found, so the APK cannot be checked against the manifest. Searched: " +
            ($aapt2Searched -join "; ") + ". Fix: install Android build-tools, set ANDROID_HOME, pass -Aapt2Path, " +
            "set aapt2_path in updater.toml, or pass -SkipApkCheck to publish without the check.")
    }
    $badging = Get-ApkBadging -Aapt2 $aapt2 -Apk $ApkPath
    $problems = @()
    if ($badging.Package -ne $AppId) { $problems += "appId: manifest $AppId vs APK $($badging.Package)" }
    if ($badging.VersionName -ne $VersionName) { $problems += "versionName: manifest $VersionName vs APK $($badging.VersionName)" }
    if ([int]$badging.VersionCode -ne $VersionCode) { $problems += "versionCode: manifest $VersionCode vs APK $($badging.VersionCode)" }
    if ($problems.Count -gt 0) {
        $msg = "APK does not match manifest ($ApkPath): " + ($problems -join "; ") + "."
        if ($apkFromFallback) {
            $msg += " dist/$ProjectName-v$VersionName.apk was not found (rebuild with build-apk.ps1 or pass -ApkPath)."
        }
        throw $msg
    }
    Write-Host "[OK] APK matches manifest: $($badging.Package) v$($badging.VersionName)+$($badging.VersionCode)" -ForegroundColor Green
}

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
