# AppUpdater — Design & Implementation Guide

## 1. Decisions Confirmed by Molly (2026-10-20)
- **D-0001 (Backend Hosting):** Cloudflare Worker + private Cloudflare R2 bucket (`private-app-releases`). Keeps binary storage and bandwidth off Railway.
- **D-0002 (Authentication):** Single shared Bearer token (`APP_UPDATER_TOKEN`) across all of Molly's private client apps.
- **D-0003 (Check & Notification Flow):**
  1. **On App Launch:** Each client app checks `GET /api/v1/update/:appId` on startup and shows `UpdatePromptDialog` if `remote.versionCode > local.versionCode`.
  2. **Instant `ntfy` Push on Publish:** When `publish-release.ps1` uploads a new APK to R2, it posts a notification to Molly's `ntfy` topic (`"Update available: <Project> v<Version>"`). No background `WorkManager` polling is needed in the apps.
  3. **Manual In-App "Check for Update":** Both client SDKs provide an interactive "Check for Update" button/tile for the app's Settings screen.
- **D-0004 (Platform Scope):** Android APKs first (7 Flutter apps + `PikminFilter` in native Android/Kotlin). Windows desktop updates remain via Switchboard's local `build_windows` install for now; `version.json` includes an optional `artifacts` map for future Windows `.zip` support.

---

## 2. Repository Layout (`C:\antigravity\AppUpdater`)

```text
C:\antigravity\AppUpdater\
├── contracts/
│   ├── README.md
│   └── version-manifest.schema.json   # app-updater/1 JSON schema
├── worker/                            # Cloudflare Worker + R2 gateway (TypeScript)
│   ├── wrangler.toml
│   ├── package.json
│   ├── src/index.ts
│   └── test/index.spec.ts
├── scripts/
│   └── publish-release.ps1            # Uploads dist/<App>.apk + dist/version.json to R2 & pushes ntfy
└── packages/
    ├── app_updater_flutter/           # Shared Flutter package (Dart)
    │   ├── pubspec.yaml
    │   ├── lib/
    │   │   ├── app_updater_flutter.dart
    │   │   ├── src/manifest.dart
    │   │   ├── src/update_service.dart
    │   │   ├── src/update_dialog.dart
    │   │   └── src/check_update_tile.dart
    │   └── test/
    └── app-updater-android/           # Shared Android/Kotlin library module
        ├── build.gradle.kts
        └── src/
            ├── main/kotlin/com/molly/appupdater/
            │   ├── AppReleaseManifest.kt      # kotlinx.serialization (no org.json)
            │   ├── UpdateClient.kt            # OkHttp + Coroutines + streaming SHA-256
            │   ├── ApkInstaller.kt            # FileProvider + PackageInstaller intent
            │   └── ui/UpdatePromptDialog.kt   # Jetpack Compose Material 3 dialog + Settings row
            └── test/kotlin/com/molly/appupdater/
```

---

## 3. Client SDK Specifications

### 3.1 Flutter SDK (`packages/app_updater_flutter`)
- **`UpdateService`**:
  - `checkForUpdate({required String baseUrl, required String authToken, String? appIdOverride})`: returns `UpdateCheckResult` (`upToDate`, `updateAvailable(manifest)`, `unconfigured`, or `error(message)`).
  - `downloadAndInstall({required AppReleaseManifest manifest, required ValueChanged<double> onProgress})`: downloads via `dio` to `getTemporaryDirectory()/updates/update-v<versionCode>.apk`, verifies SHA-256 via streaming `apkFile.openRead()` piped through `sha256`, and opens `application/vnd.android.package-archive` via `open_filex`.
- **`UpdatePromptDialog`**:
  - `UpdatePromptDialog.checkOnLaunch(BuildContext context, {required String baseUrl, required String authToken})`: silent if up-to-date or unconfigured; shows modal dialog if an update is available.
  - Responsive layout (`< 400px` safe with `Wrap` actions) and verified 4.5:1 contrast in light and dark themes.
- **`CheckForUpdateTile`**:
  - Drop-in `ListTile` for Settings pages showing current version (`v0.34.0 (44)`), a "Check for update" button, inline status feedback ("Up to date!" or error text), and triggers `UpdatePromptDialog` when a newer build is found.

### 3.2 Native Android / Kotlin SDK (`packages/app-updater-android`)
- **`AppReleaseManifest`**:
  - Annotated with `@Serializable` (`kotlinx.serialization.json.Json { ignoreUnknownKeys = true }`) so `gradlew testDebugUnitTest` runs on pure JVM without Android `org.json` stub exceptions.
- **`UpdateClient`**:
  - Uses `OkHttpClient` and `Dispatchers.IO`.
  - Streams APK download while updating `DigestInputStream(stream, MessageDigest.getInstance("SHA-256"))`, emitting `Flow<DownloadState>` (`Progress(0f..1f)`, `Verified(File)`, `Error(String)`).
- **`ApkInstaller`**:
  - Resolves `FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apkFile)` and starts `Intent(Intent.ACTION_VIEW)` with `FLAG_GRANT_READ_URI_PERMISSION | FLAG_ACTIVITY_NEW_TASK`.
- **`UpdatePromptDialog` & `CheckForUpdateRow` (Jetpack Compose)**:
  - Material 3 dialog + Settings row for `PikminFilter` and future Kotlin apps.

---

## 4. Switchboard Integration

1. **Build Scripts (`flutter-build-apk.ps1` & `gradle-build-apk.ps1`):**
   - After compiling the release APK and copying it to `dist\<Project>-v<Version>.apk`, the script computes `(Get-FileHash $destPath -Algorithm SHA256).Hash.ToLower()`, reads the newest section from `CHANGELOG.md`, and writes `dist\version.json`.
2. **Signed `publish_apk` Action (`switchboard_spoke/actions.py`):**
   - Added to the `flutter` and `gradle` sets when `dist/version.json` or `build-apk.ps1` is present.
   - Risk: `high`, with warning `"Uploads the built APK and version.json in dist/ to Cloudflare R2 and sends an ntfy update notification."` (`acknowledged: true`).
   - Reads R2 credentials and `ntfy` topic from `%LOCALAPPDATA%\Switchboard\updater.toml` (never stored in any repo).
3. **Projects Page Live Version Tracking (`[versions.<project>]` in `actions.toml`):**
   - Point `url = "https://<worker>/api/v1/version/<appId>"` and `json_key = "version"` so Switchboard's Projects page shows the live R2 APK version right next to the repo's `code_version`.
