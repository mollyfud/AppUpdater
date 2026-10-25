package com.molly.appupdater

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest

interface UpdateHttpTransport {
    fun getJson(url: String, bearerToken: String): Pair<Int, String>
    fun openDownloadStream(url: String): Pair<Int, DownloadStream>
}

data class DownloadStream(
    val contentLength: Long,
    val stream: InputStream
)

/**
 * Parses [url] and returns it only if it is `https://` with a host. No exceptions, not even
 * localhost. Route every URL the SDK fetches through this.
 * Throws [SecurityException]; the message names only the scheme, never the URL (download URLs
 * carry a signature).
 */
internal fun requireHttpsUrl(url: String): URL {
    val uri = try {
        URI.create(url.trim())
    } catch (e: IllegalArgumentException) {
        throw SecurityException("Refusing insecure update URL: it could not be parsed (https required)")
    }
    val scheme = uri.scheme
    if (scheme == null || !scheme.equals("https", ignoreCase = true) || uri.host.isNullOrBlank()) {
        throw SecurityException("Refusing insecure update URL: scheme '${scheme ?: "(none)"}' is not https")
    }
    return uri.toURL()
}

class DefaultHttpUrlConnectionTransport(
    private val connectTimeoutMs: Int = 10_000,
    private val readTimeoutMs: Int = 30_000
) : UpdateHttpTransport {
    override fun getJson(url: String, bearerToken: String): Pair<Int, String> {
        val conn = (requireHttpsUrl(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
            setRequestProperty("Authorization", "Bearer $bearerToken")
            setRequestProperty("Accept", "application/json")
        }
        return try {
            val status = conn.responseCode
            val stream = if (status in 200..299) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            status to body
        } finally {
            conn.disconnect()
        }
    }

    override fun openDownloadStream(url: String): Pair<Int, DownloadStream> {
        val conn = (requireHttpsUrl(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
        }
        val status = conn.responseCode
        val stream = if (status in 200..299) conn.inputStream else (conn.errorStream ?: InputStream.nullInputStream())
        return status to DownloadStream(conn.contentLengthLong, stream)
    }
}

class UpdateClient(
    private val baseUrl: String,
    private val authToken: String,
    private val transport: UpdateHttpTransport = DefaultHttpUrlConnectionTransport()
) {
    /**
     * Checks `GET /api/v1/update/:appId` for a newer release.
     * Safe to invoke from `Dispatchers.IO`.
     *
     * Only `https://` is accepted, with no localhost exception: a non-https gateway URL returns
     * [UpdateCheckResult.Error] before the transport (and the token) is touched, and so does a
     * manifest whose `downloadUrl` is not https.
     */
    fun checkForUpdate(
        appId: String,
        currentVersionCode: Int,
        currentVersionName: String
    ): UpdateCheckResult {
        val cleanBase = baseUrl.trim().trimEnd('/')
        val cleanToken = authToken.trim()
        val cleanAppId = appId.trim()

        if (cleanBase.isEmpty() || cleanToken.isEmpty() || cleanAppId.isEmpty()) {
            return UpdateCheckResult.Unconfigured(currentVersionCode, currentVersionName)
        }

        val encodedAppId = URLEncoder.encode(cleanAppId, "UTF-8")
        val endpoint = if (cleanBase.endsWith("/api/v1/update")) {
            "$cleanBase/$encodedAppId"
        } else {
            "$cleanBase/api/v1/update/$encodedAppId"
        }

        try {
            requireHttpsUrl(endpoint)
        } catch (e: SecurityException) {
            return UpdateCheckResult.Error(
                message = "Update server URL must start with https://",
                currentVersionCode = currentVersionCode,
                currentVersionName = currentVersionName
            )
        }

        val (status, body) = try {
            transport.getJson(endpoint, cleanToken)
        } catch (e: Exception) {
            return UpdateCheckResult.Error(
                message = "Could not connect to update server at $endpoint (${e.message})",
                currentVersionCode = currentVersionCode,
                currentVersionName = currentVersionName
            )
        }

        if (status == 404) {
            val serverError = try {
                AppReleaseManifest.parseTopLevelJsonFields(body)["error"]
            } catch (_: Exception) {
                null
            }
            val errorMsg = if (serverError == "App manifest not found") {
                "Server has no release for $cleanAppId (HTTP 404)"
            } else {
                "Update endpoint not found at $endpoint (HTTP 404) - check the gateway URL"
            }
            return UpdateCheckResult.Error(
                message = errorMsg,
                currentVersionCode = currentVersionCode,
                currentVersionName = currentVersionName
            )
        }
        if (status == 401 || status == 403) {
            return UpdateCheckResult.Error(
                message = "Update check unauthorized (HTTP $status) at $endpoint",
                currentVersionCode = currentVersionCode,
                currentVersionName = currentVersionName
            )
        }
        if (status != 200) {
            return UpdateCheckResult.Error(
                message = "Update server returned HTTP $status at $endpoint",
                currentVersionCode = currentVersionCode,
                currentVersionName = currentVersionName
            )
        }

        return try {
            val manifest = AppReleaseManifest.fromJsonString(body, currentVersionCode)
            if (manifest.versionCode > currentVersionCode) {
                val downloadIsHttps = manifest.downloadUrl.isBlank() || try {
                    requireHttpsUrl(manifest.downloadUrl)
                    true
                } catch (e: SecurityException) {
                    false
                }
                if (!downloadIsHttps) {
                    UpdateCheckResult.Error(
                        message = "Update manifest has an insecure download URL (https required)",
                        currentVersionCode = currentVersionCode,
                        currentVersionName = currentVersionName
                    )
                } else if (manifest.downloadUrl.isNotBlank() && manifest.sha256.length == 64) {
                    UpdateCheckResult.UpdateAvailable(
                        currentVersionCode = currentVersionCode,
                        currentVersionName = currentVersionName,
                        manifest = manifest
                    )
                } else {
                    UpdateCheckResult.Error(
                        message = "Server build ${manifest.versionCode} is newer than local build $currentVersionCode but its manifest is incomplete",
                        currentVersionCode = currentVersionCode,
                        currentVersionName = currentVersionName
                    )
                }
            } else {
                UpdateCheckResult.UpToDate(currentVersionCode, currentVersionName)
            }
        } catch (e: Exception) {
            UpdateCheckResult.Error(
                message = "Could not parse update manifest: ${e.message}",
                currentVersionCode = currentVersionCode,
                currentVersionName = currentVersionName
            )
        }
    }

    /**
     * Streams the APK download to `cacheDir/updates/update-v<versionCode>.apk`, computes the
     * SHA-256 checksum in a single streaming pass (`MessageDigest`), and verifies it against
     * [manifest.sha256]. Deletes the file and throws [SecurityException] if the hash does not match.
     * Reuses an already-downloaded file if its checksum matches [manifest.sha256].
     * Throws [SecurityException] before any file or network access if [manifest.downloadUrl] is
     * not `https://` (no localhost exception).
     */
    fun downloadAndVerifyApk(
        manifest: AppReleaseManifest,
        cacheDir: File,
        onProgress: (Float) -> Unit = {}
    ): File {
        requireHttpsUrl(manifest.downloadUrl)

        val updatesDir = File(cacheDir, "updates")
        if (!updatesDir.exists()) {
            updatesDir.mkdirs()
        }
        val apkFile = File(updatesDir, "update-v${manifest.versionCode}.apk")

        // Reuse verified cached APK if already fully downloaded and hash matches
        if (apkFile.exists()) {
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                apkFile.inputStream().use { stream ->
                    val buffer = ByteArray(16 * 1024)
                    while (true) {
                        val read = stream.read(buffer)
                        if (read == -1) break
                        digest.update(buffer, 0, read)
                    }
                }
                val existingHash = digest.digest().joinToString("") { "%02x".format(it) }
                if (existingHash.equals(manifest.sha256, ignoreCase = true)) {
                    onProgress(1.0f)
                    return apkFile
                }
            } catch (_: Exception) {
                // If unreadable, fall through and delete
            }
            apkFile.delete()
        }

        val (status, download) = transport.openDownloadStream(manifest.downloadUrl)
        if (status != 200) {
            download.stream.close()
            throw IllegalStateException("APK download failed (HTTP $status)")
        }

        val totalBytes = if (download.contentLength > 0) download.contentLength else manifest.fileSize
        val digest = MessageDigest.getInstance("SHA-256")
        var receivedBytes = 0L

        try {
            download.stream.use { input ->
                FileOutputStream(apkFile).use { output ->
                    val buffer = ByteArray(16 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        output.write(buffer, 0, read)
                        digest.update(buffer, 0, read)
                        receivedBytes += read
                        if (totalBytes > 0) {
                            val fraction = (receivedBytes.toFloat() / totalBytes.toFloat()).coerceIn(0f, 1f)
                            onProgress(fraction)
                        }
                    }
                    output.flush()
                }
            }
        } catch (e: Exception) {
            if (apkFile.exists()) {
                apkFile.delete()
            }
            throw e
        }

        val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
        if (!actualHash.equals(manifest.sha256, ignoreCase = true)) {
            apkFile.delete()
            throw SecurityException(
                "Security Error: APK SHA-256 checksum mismatch! Expected ${manifest.sha256}, got $actualHash."
            )
        }

        onProgress(1.0f)
        return apkFile
    }
}
