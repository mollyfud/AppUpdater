package com.molly.appupdater

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest

class AppUpdaterTest {

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun sampleJson(
        versionCode: Int = 14,
        minRequiredVersionCode: Int = 12,
        sha256: String = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ): String = """
        {
          "schema": "app-updater/1",
          "appId": "com.molly.pikminfilter",
          "project": "PikminFilter",
          "versionName": "1.3.0",
          "versionCode": $versionCode,
          "minRequiredVersionCode": $minRequiredVersionCode,
          "releaseDate": "2026-10-20T08:00:00Z",
          "releaseNotes": "• Added AccessibilityService capture\n• Improved OCR speed",
          "apkKey": "com.molly.pikminfilter/builds/PikminFilter-v1.3.0.apk",
          "sha256": "$sha256",
          "fileSize": 1024,
          "downloadUrl": "https://updater.example.com/api/v1/download?key=apk&expires=9999999999&sig=abc",
          "artifacts": {
            "android-arm64": {
              "key": "com.molly.pikminfilter/builds/PikminFilter-v1.3.0.apk",
              "sha256": "$sha256",
              "fileSize": 1024
            }
          }
        }
    """.trimIndent()

    @Test
    fun `AppReleaseManifest parses JSON without org_json and computes isMandatory`() {
        val manifest = AppReleaseManifest.fromJsonString(sampleJson(versionCode = 14, minRequiredVersionCode = 12), currentVersionCode = 10)
        assertEquals("app-updater/1", manifest.schema)
        assertEquals("com.molly.pikminfilter", manifest.appId)
        assertEquals("PikminFilter", manifest.project)
        assertEquals("1.3.0", manifest.versionName)
        assertEquals(14, manifest.versionCode)
        assertEquals(12, manifest.minRequiredVersionCode)
        assertTrue(manifest.isMandatory)
        assertTrue(manifest.releaseNotes.contains("AccessibilityService"))

        val nonMandatory = AppReleaseManifest.fromJsonString(sampleJson(versionCode = 14, minRequiredVersionCode = 10), currentVersionCode = 11)
        assertFalse(nonMandatory.isMandatory)
    }

    @Test
    fun `UpdateClient checkForUpdate detects newer version and upToDate state`() {
        val apkBytes = "FAKE_PIKMIN_APK_BINARY".toByteArray(Charsets.UTF_8)
        val validSha = sha256Hex(apkBytes)

        val fakeTransport = object : UpdateHttpTransport {
            override fun getJson(url: String, bearerToken: String): Pair<Int, String> {
                assertEquals("https://updater.example.com/api/v1/update/com.molly.pikminfilter", url)
                assertEquals("shared-token-123", bearerToken)
                return 200 to sampleJson(versionCode = 14, sha256 = validSha)
            }

            override fun openDownloadStream(url: String): Pair<Int, DownloadStream> {
                return 200 to DownloadStream(apkBytes.size.toLong(), ByteArrayInputStream(apkBytes))
            }
        }

        val client = UpdateClient(
            baseUrl = "https://updater.example.com",
            authToken = "shared-token-123",
            transport = fakeTransport
        )

        val updateRes = client.checkForUpdate("com.molly.pikminfilter", currentVersionCode = 11, currentVersionName = "0.6.0")
        assertTrue(updateRes is UpdateCheckResult.UpdateAvailable)
        val manifest = (updateRes as UpdateCheckResult.UpdateAvailable).manifest
        assertEquals("1.3.0", manifest.versionName)

        val upToDateRes = client.checkForUpdate("com.molly.pikminfilter", currentVersionCode = 14, currentVersionName = "1.3.0")
        assertTrue(upToDateRes is UpdateCheckResult.UpToDate)
    }

    @Test
    fun `UpdateClient checkForUpdate treats 404 as error distinguishing manifest missing vs route missing`() {
        val transportAppNotFound = object : UpdateHttpTransport {
            override fun getJson(url: String, bearerToken: String): Pair<Int, String> {
                return 404 to """{"error":"App manifest not found"}"""
            }
            override fun openDownloadStream(url: String): Pair<Int, DownloadStream> = throw UnsupportedOperationException()
        }

        val clientAppNotFound = UpdateClient("https://updater.example.com", "token", transportAppNotFound)
        val res1 = clientAppNotFound.checkForUpdate("com.molly.pikminfilter", 1, "1.0.0")
        assertTrue(res1 is UpdateCheckResult.Error)
        assertEquals("Server has no release for com.molly.pikminfilter (HTTP 404)", (res1 as UpdateCheckResult.Error).message)

        val transportRouteNotFound = object : UpdateHttpTransport {
            override fun getJson(url: String, bearerToken: String): Pair<Int, String> {
                return 404 to "Not Found"
            }
            override fun openDownloadStream(url: String): Pair<Int, DownloadStream> = throw UnsupportedOperationException()
        }

        val clientRouteNotFound = UpdateClient("https://updater.example.com", "token", transportRouteNotFound)
        val res2 = clientRouteNotFound.checkForUpdate("com.molly.pikminfilter", 1, "1.0.0")
        assertTrue(res2 is UpdateCheckResult.Error)
        assertTrue((res2 as UpdateCheckResult.Error).message.contains("Update endpoint not found at"))
    }

    @Test
    fun `UpdateClient checkForUpdate returns error on newer version with incomplete manifest`() {
        val fakeTransport = object : UpdateHttpTransport {
            override fun getJson(url: String, bearerToken: String): Pair<Int, String> {
                return 200 to sampleJson(versionCode = 14, sha256 = "short")
            }
            override fun openDownloadStream(url: String): Pair<Int, DownloadStream> = throw UnsupportedOperationException()
        }

        val client = UpdateClient("https://updater.example.com", "token", fakeTransport)
        val res = client.checkForUpdate("com.molly.pikminfilter", 10, "1.0.0")
        assertTrue(res is UpdateCheckResult.Error)
        assertTrue((res as UpdateCheckResult.Error).message.contains("manifest is incomplete"))
    }

    @Test
    fun `UpdateClient downloadAndVerifyApk streams and verifies SHA-256 and rejects mismatch`() {
        val apkBytes = "VERIFIED_KOTLIN_APK_CONTENT".toByteArray(Charsets.UTF_8)
        val validSha = sha256Hex(apkBytes)

        val fakeTransport = object : UpdateHttpTransport {
            override fun getJson(url: String, bearerToken: String): Pair<Int, String> = 200 to ""
            override fun openDownloadStream(url: String): Pair<Int, DownloadStream> {
                return 200 to DownloadStream(apkBytes.size.toLong(), ByteArrayInputStream(apkBytes))
            }
        }

        val client = UpdateClient("https://updater.example.com", "token", fakeTransport)
        val tempDir = Files.createTempDirectory("kotlin_updater_test").toFile()
        try {
            val manifest = AppReleaseManifest.fromJsonString(
                sampleJson(versionCode = 15, sha256 = validSha),
                currentVersionCode = 11
            )
            var lastProgress = 0f
            val downloadedFile = client.downloadAndVerifyApk(manifest, tempDir) { p ->
                lastProgress = p
            }
            assertTrue(downloadedFile.exists())
            assertEquals(1.0f, lastProgress, 0.001f)
            assertEquals("VERIFIED_KOTLIN_APK_CONTENT", downloadedFile.readText(Charsets.UTF_8))

            // Verified cached APK reuse
            val reusedFile = client.downloadAndVerifyApk(manifest, tempDir)
            assertTrue(reusedFile.exists())

            // Tampered SHA-256 must throw SecurityException and delete the file
            val badManifest = manifest.copy(
                versionCode = 16,
                sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
            )
            var threwSecurity = false
            try {
                client.downloadAndVerifyApk(badManifest, tempDir)
            } catch (e: SecurityException) {
                threwSecurity = true
            }
            assertTrue("Expected SecurityException on SHA-256 mismatch", threwSecurity)
        } finally {
            tempDir.deleteRecursively()
        }
    }

    @Test
    fun `DefaultHttpUrlConnectionTransport rejects insecure plain http URLs`() {
        val transport = DefaultHttpUrlConnectionTransport()
        var threwGet = false
        try {
            transport.getJson("http://127.0.0.1:1/x", "t")
        } catch (e: SecurityException) {
            threwGet = true
            assertTrue(e.message?.contains("not https") == true)
        }
        assertTrue("Expected SecurityException for insecure getJson", threwGet)

        var threwStream = false
        try {
            transport.openDownloadStream("http://insecure.example.com/file.apk")
        } catch (e: SecurityException) {
            threwStream = true
            assertTrue(e.message?.contains("not https") == true)
        }
        assertTrue("Expected SecurityException for insecure openDownloadStream", threwStream)
    }

    @Test
    fun `requireHttpsUrl accepts https in any case and rejects everything else`() {
        assertEquals("https", requireHttpsUrl("https://updater.example.com/x").protocol)
        assertEquals("https", requireHttpsUrl("HTTPS://updater.example.com/x").protocol)
        for (bad in listOf("http://updater.example.com", "ftp://updater.example.com", "file:///etc/passwd", "updater.example.com/x", "", "   ")) {
            var threw = false
            try {
                requireHttpsUrl(bad)
            } catch (e: SecurityException) {
                threw = true
            }
            assertTrue("Expected SecurityException for '$bad'", threw)
        }
    }

    private class CountingTransport(private val manifestJson: String = "") : UpdateHttpTransport {
        var getJsonCalls = 0
        var downloadCalls = 0
        override fun getJson(url: String, bearerToken: String): Pair<Int, String> {
            getJsonCalls++
            return 200 to manifestJson
        }
        override fun openDownloadStream(url: String): Pair<Int, DownloadStream> {
            downloadCalls++
            return 200 to DownloadStream(0, ByteArrayInputStream(ByteArray(0)))
        }
    }

    @Test
    fun `UpdateClient returns Error for http baseUrl without calling the transport`() {
        val transport = CountingTransport()
        val client = UpdateClient("http://updater.example.com", "token", transport)
        val res = client.checkForUpdate("com.molly.pikminfilter", 1, "1.0.0")
        assertTrue(res is UpdateCheckResult.Error)
        assertTrue((res as UpdateCheckResult.Error).message.contains("https://"))
        assertEquals(0, transport.getJsonCalls)
    }

    @Test
    fun `UpdateClient returns Error when manifest downloadUrl is http`() {
        val json = sampleJson(versionCode = 14, sha256 = "a".repeat(64))
            .replace("https://updater.example.com/api", "http://updater.example.com/api")
        val client = UpdateClient("https://updater.example.com", "token", CountingTransport(json))
        val res = client.checkForUpdate("com.molly.pikminfilter", 10, "1.0.0")
        assertTrue(res is UpdateCheckResult.Error)
        assertTrue((res as UpdateCheckResult.Error).message.contains("insecure download URL"))
    }

    @Test
    fun `downloadAndVerifyApk refuses http downloadUrl and leaves no file`() {
        val transport = CountingTransport()
        val client = UpdateClient("https://updater.example.com", "token", transport)
        val tempDir = Files.createTempDirectory("kotlin_updater_http").toFile()
        try {
            val manifest = AppReleaseManifest.fromJsonString(
                sampleJson(versionCode = 15, sha256 = "a".repeat(64))
                    .replace("https://updater.example.com/api", "http://updater.example.com/api"),
                currentVersionCode = 11
            )
            var threw = false
            try {
                client.downloadAndVerifyApk(manifest, tempDir)
            } catch (e: SecurityException) {
                threw = true
            }
            assertTrue("Expected SecurityException", threw)
            assertEquals(0, transport.downloadCalls)
            assertTrue(tempDir.walkTopDown().none { it.isFile })
        } finally {
            tempDir.deleteRecursively()
        }
    }
}
