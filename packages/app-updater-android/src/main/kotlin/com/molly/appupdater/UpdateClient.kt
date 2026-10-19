package com.molly.appupdater

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
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

class DefaultHttpUrlConnectionTransport(
    private val connectTimeoutMs: Int = 10_000,
    private val readTimeoutMs: Int = 30_000
) : UpdateHttpTransport {
    override fun getJson(url: String, bearerToken: String): Pair<Int, String> {
        val conn = (URI.create(url).toURL().openConnection() as HttpURLConnection).apply {
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
        val conn = (URI.create(url).toURL().openConnection() as HttpURLConnection).apply {
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

        val (status, body) = try {
            transport.getJson(endpoint, cleanToken)
        } catch (e: Exception) {
            return UpdateCheckResult.Error(
                message = "Could not connect to update server (${e.message})",
                currentVersionCode = currentVersionCode,
                currentVersionName = currentVersionName
            )
        }

        if (status == 404) {
            return UpdateCheckResult.UpToDate(currentVersionCode, currentVersionName)
        }
        if (status == 401 || status == 403) {
            return UpdateCheckResult.Error(
                message = "Update check unauthorized (HTTP $status)",
                currentVersionCode = currentVersionCode,
                currentVersionName = currentVersionName
            )
        }
        if (status != 200) {
            return UpdateCheckResult.Error(
                message = "Update server returned HTTP $status",
                currentVersionCode = currentVersionCode,
                currentVersionName = currentVersionName
            )
        }

        return try {
            val manifest = AppReleaseManifest.fromJsonString(body, currentVersionCode)
            if (manifest.versionCode > currentVersionCode &&
                manifest.downloadUrl.isNotBlank() &&
                manifest.sha256.length == 64
            ) {
                UpdateCheckResult.UpdateAvailable(
                    currentVersionCode = currentVersionCode,
                    currentVersionName = currentVersionName,
                    manifest = manifest
                )
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
     */
    fun downloadAndVerifyApk(
        manifest: AppReleaseManifest,
        cacheDir: File,
        onProgress: (Float) -> Unit = {}
    ): File {
        val updatesDir = File(cacheDir, "updates")
        if (!updatesDir.exists()) {
            updatesDir.mkdirs()
        }
        val apkFile = File(updatesDir, "update-v${manifest.versionCode}.apk")
        if (apkFile.exists()) {
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
