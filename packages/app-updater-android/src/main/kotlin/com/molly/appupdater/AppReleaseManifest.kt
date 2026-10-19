package com.molly.appupdater

/**
 * Pure Kotlin representation of the `app-updater/1` (`version.json`) manifest.
 *
 * Uses a zero-dependency pure Kotlin JSON parser rather than `org.json` so local JVM unit tests
 * (`testDebugUnitTest`) never hit `RuntimeException: Stub!`.
 */
data class AppReleaseManifest(
    val schema: String = "app-updater/1",
    val appId: String,
    val project: String,
    val versionName: String,
    val versionCode: Int,
    val minRequiredVersionCode: Int = 1,
    val releaseDate: String = "",
    val releaseNotes: String = "",
    val apkKey: String,
    val sha256: String,
    val fileSize: Long,
    val downloadUrl: String = "",
    val isMandatory: Boolean = false
) {
    companion object {
        /**
         * Parses a JSON object matching `contracts/version-manifest.schema.json` into [AppReleaseManifest]
         * using pure Kotlin string scanning (safe in Android runtime and pure JVM unit tests).
         */
        fun fromJsonString(json: String, currentVersionCode: Int): AppReleaseManifest {
            val fields = parseTopLevelJsonFields(json)
            val versionCode = fields["versionCode"]?.toIntOrNull()
                ?: throw IllegalArgumentException("Missing or invalid versionCode in manifest")
            val minReq = fields["minRequiredVersionCode"]?.toIntOrNull() ?: 1
            val versionName = fields["versionName"]?.takeIf { it.isNotBlank() }
                ?: throw IllegalArgumentException("Missing versionName in manifest")
            val sha256 = fields["sha256"]?.trim()?.lowercase()
                ?: throw IllegalArgumentException("Missing sha256 in manifest")

            return AppReleaseManifest(
                schema = fields["schema"]?.ifBlank { "app-updater/1" } ?: "app-updater/1",
                appId = fields["appId"] ?: "",
                project = fields["project"] ?: "",
                versionName = versionName,
                versionCode = versionCode,
                minRequiredVersionCode = minReq,
                releaseDate = fields["releaseDate"] ?: "",
                releaseNotes = fields["releaseNotes"] ?: "",
                apkKey = fields["apkKey"] ?: "",
                sha256 = sha256,
                fileSize = fields["fileSize"]?.toLongOrNull() ?: 0L,
                downloadUrl = fields["downloadUrl"] ?: "",
                isMandatory = currentVersionCode < minReq
            )
        }

        internal fun parseTopLevelJsonFields(json: String): Map<String, String> {
            val result = mutableMapOf<String, String>()
            var i = 0
            val n = json.length

            fun skipWhitespace() {
                while (i < n && json[i].isWhitespace()) i++
            }

            fun readQuotedString(): String {
                if (i >= n || json[i] != '"') return ""
                i++ // skip opening quote
                val sb = StringBuilder()
                while (i < n) {
                    val c = json[i++]
                    if (c == '"') break
                    if (c == '\\' && i < n) {
                        when (val esc = json[i++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                if (i + 4 <= n) {
                                    val hex = json.substring(i, i + 4)
                                    hex.toIntOrNull(16)?.let { sb.append(it.toChar()) }
                                    i += 4
                                }
                            }
                            else -> sb.append(esc)
                        }
                    } else {
                        sb.append(c)
                    }
                }
                return sb.toString()
            }

            fun skipNestedStructure(openChar: Char, closeChar: Char) {
                var depth = 0
                var inStr = false
                while (i < n) {
                    val c = json[i++]
                    if (inStr) {
                        if (c == '\\' && i < n) {
                            i++
                        } else if (c == '"') {
                            inStr = false
                        }
                    } else {
                        if (c == '"') {
                            inStr = true
                        } else if (c == openChar) {
                            depth++
                        } else if (c == closeChar) {
                            depth--
                            if (depth <= 0) break
                        }
                    }
                }
            }

            skipWhitespace()
            if (i >= n || json[i] != '{') {
                throw IllegalArgumentException("Expected JSON object starting with '{'")
            }
            i++ // skip '{'

            while (i < n) {
                skipWhitespace()
                if (i >= n || json[i] == '}') break
                if (json[i] == ',') {
                    i++
                    continue
                }
                if (json[i] != '"') break
                val key = readQuotedString()
                skipWhitespace()
                if (i < n && json[i] == ':') i++
                skipWhitespace()
                if (i >= n) break

                when (val valStart = json[i]) {
                    '"' -> result[key] = readQuotedString()
                    '{' -> skipNestedStructure('{', '}')
                    '[' -> skipNestedStructure('[', ']')
                    else -> {
                        val start = i
                        while (i < n && json[i] != ',' && json[i] != '}' && !json[i].isWhitespace()) {
                            i++
                        }
                        val token = json.substring(start, i)
                        if (token != "null") {
                            result[key] = token
                        }
                    }
                }
            }
            return result
        }
    }
}

sealed class UpdateCheckResult {
    data class UpToDate(val currentVersionCode: Int, val currentVersionName: String) : UpdateCheckResult()
    data class UpdateAvailable(
        val currentVersionCode: Int,
        val currentVersionName: String,
        val manifest: AppReleaseManifest
    ) : UpdateCheckResult()
    data class Unconfigured(val currentVersionCode: Int, val currentVersionName: String) : UpdateCheckResult()
    data class Error(
        val message: String,
        val currentVersionCode: Int = 0,
        val currentVersionName: String = ""
    ) : UpdateCheckResult()
}
