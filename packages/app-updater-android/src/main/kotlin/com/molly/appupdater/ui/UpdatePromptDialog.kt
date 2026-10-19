package com.molly.appupdater.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.DialogProperties
import com.molly.appupdater.ApkInstaller
import com.molly.appupdater.AppReleaseManifest
import com.molly.appupdater.UpdateCheckResult
import com.molly.appupdater.UpdateClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun UpdatePromptDialog(
    manifest: AppReleaseManifest,
    updateClient: UpdateClient,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isDownloading by remember { mutableStateOf(false) }
    var progress by remember { mutableFloatStateOf(0f) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val isDark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val dialogBg = if (isDark) Color(0xFF1A1D24) else Color(0xFFFFFFFF)
    val titleColor = if (isDark) Color(0xFFF3F4F6) else Color(0xFF111827)
    val bodyColor = if (isDark) Color(0xFFD1D5DB) else Color(0xFF374151)
    val notesBg = if (isDark) Color(0xFF111318) else Color(0xFFF3F4F6)
    val notesBorder = if (isDark) Color(0xFF374151) else Color(0xFFD1D5DB)
    val notesText = if (isDark) Color(0xFFE5E7EB) else Color(0xFF1F2937)
    val errorBg = if (isDark) Color(0xFF450A0A) else Color(0xFFFEF2F2)
    val errorText = if (isDark) Color(0xFFFECACA) else Color(0xFF991B1B)
    val primaryBtnBg = if (isDark) Color(0xFF60A5FA) else Color(0xFF1D4ED8)
    val primaryBtnText = if (isDark) Color(0xFF0A0E17) else Color(0xFFFFFFFF)
    val secondaryBtnText = if (isDark) Color(0xFF93C5FD) else Color(0xFF1E40AF)

    AlertDialog(
        onDismissRequest = {
            if (!manifest.isMandatory && !isDownloading) {
                onDismiss()
            }
        },
        properties = DialogProperties(
            dismissOnBackPress = !manifest.isMandatory && !isDownloading,
            dismissOnClickOutside = !manifest.isMandatory && !isDownloading
        ),
        containerColor = dialogBg,
        title = {
            Text(
                text = "Update v${manifest.versionName} Available",
                color = titleColor,
                fontWeight = FontWeight.Bold,
                fontSize = 18.sp
            )
        },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                if (manifest.isMandatory) {
                    Surface(
                        color = errorBg,
                        shape = RoundedCornerShape(8.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 10.dp)
                    ) {
                        Text(
                            text = "This is a required update to continue using the app.",
                            color = errorText,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(10.dp)
                        )
                    }
                }
                Text(
                    text = "Build ${manifest.versionCode}",
                    color = bodyColor,
                    fontSize = 13.sp
                )
                Spacer(modifier = Modifier.height(10.dp))
                Text(
                    text = "What's new:",
                    color = titleColor,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp
                )
                Spacer(modifier = Modifier.height(6.dp))
                Surface(
                    color = notesBg,
                    shape = RoundedCornerShape(8.dp),
                    border = BorderStroke(1.dp, notesBorder),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = manifest.releaseNotes.ifBlank { "Bug fixes and improvements." },
                        color = notesText,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(10.dp)
                    )
                }
                if (isDownloading) {
                    Spacer(modifier = Modifier.height(14.dp))
                    LinearProgressIndicator(
                        progress = { progress },
                        color = primaryBtnBg,
                        trackColor = notesBorder,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = "${(progress * 100).toInt()}% downloaded — verifying SHA-256...",
                        color = bodyColor,
                        fontSize = 12.sp
                    )
                }
                errorMessage?.let { err ->
                    Spacer(modifier = Modifier.height(12.dp))
                    Surface(
                        color = errorBg,
                        shape = RoundedCornerShape(8.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = err,
                            color = errorText,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(10.dp)
                        )
                    }
                }
            }
        },
        confirmButton = {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (!manifest.isMandatory && !isDownloading) {
                    TextButton(
                        onClick = onDismiss,
                        colors = ButtonDefaults.textButtonColors(contentColor = secondaryBtnText)
                    ) {
                        Text("Later")
                    }
                }
                Button(
                    enabled = !isDownloading,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = primaryBtnBg,
                        contentColor = primaryBtnText
                    ),
                    onClick = {
                        isDownloading = true
                        errorMessage = null
                        scope.launch {
                            try {
                                val file = withContext(Dispatchers.IO) {
                                    updateClient.downloadAndVerifyApk(
                                        manifest = manifest,
                                        cacheDir = context.cacheDir,
                                        onProgress = { p -> progress = p }
                                    )
                                }
                                ApkInstaller.launchInstaller(context, file)
                                isDownloading = false
                                if (!manifest.isMandatory) {
                                    onDismiss()
                                }
                            } catch (e: Exception) {
                                isDownloading = false
                                errorMessage = e.message ?: "Update failed."
                            }
                        }
                    }
                ) {
                    Text(if (isDownloading) "Downloading..." else "Update Now")
                }
            }
        }
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CheckForUpdateRow(
    updateClient: UpdateClient,
    appId: String,
    currentVersionCode: Int,
    currentVersionName: String,
    modifier: Modifier = Modifier
) {
    val scope = rememberCoroutineScope()
    var isChecking by remember { mutableStateOf(false) }
    var statusText by remember { mutableStateOf<String?>(null) }
    var isError by remember { mutableStateOf(false) }
    var activeManifest by remember { mutableStateOf<AppReleaseManifest?>(null) }

    val isDark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val cardBg = if (isDark) Color(0xFF111318) else Color(0xFFF3F4F6)
    val cardBorder = if (isDark) Color(0xFF374151) else Color(0xFFD1D5DB)
    val titleColor = if (isDark) Color(0xFFF3F4F6) else Color(0xFF111827)
    val bodyColor = if (isDark) Color(0xFFD1D5DB) else Color(0xFF374151)
    val errorColor = if (isDark) Color(0xFFFECACA) else Color(0xFF991B1B)
    val primaryBtnBg = if (isDark) Color(0xFF60A5FA) else Color(0xFF1D4ED8)
    val primaryBtnText = if (isDark) Color(0xFF0A0E17) else Color(0xFFFFFFFF)

    activeManifest?.let { manifest ->
        UpdatePromptDialog(
            manifest = manifest,
            updateClient = updateClient,
            onDismiss = { activeManifest = null }
        )
    }

    Surface(
        color = cardBg,
        shape = RoundedCornerShape(10.dp),
        border = BorderStroke(1.dp, cardBorder),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "App Updates (v$currentVersionName)",
                    color = titleColor,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 15.sp,
                    modifier = Modifier.padding(top = 6.dp)
                )
                Button(
                    enabled = !isChecking,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = primaryBtnBg,
                        contentColor = primaryBtnText
                    ),
                    onClick = {
                        isChecking = true
                        statusText = "Checking for updates..."
                        isError = false
                        scope.launch {
                            val res = withContext(Dispatchers.IO) {
                                updateClient.checkForUpdate(
                                    appId = appId,
                                    currentVersionCode = currentVersionCode,
                                    currentVersionName = currentVersionName
                                )
                            }
                            isChecking = false
                            when (res) {
                                is UpdateCheckResult.UpdateAvailable -> {
                                    statusText = "Update v${res.manifest.versionName} is available!"
                                    isError = false
                                    activeManifest = res.manifest
                                }
                                is UpdateCheckResult.UpToDate -> {
                                    statusText = "You are up to date (v$currentVersionName, build $currentVersionCode)."
                                    isError = false
                                }
                                is UpdateCheckResult.Unconfigured -> {
                                    statusText = "Update server or token not configured."
                                    isError = true
                                }
                                is UpdateCheckResult.Error -> {
                                    statusText = res.message
                                    isError = true
                                }
                            }
                        }
                    }
                ) {
                    Text(if (isChecking) "Checking..." else "Check for Update")
                }
            }
            statusText?.let { msg ->
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = msg,
                    color = if (isError) errorColor else bodyColor,
                    fontSize = 13.sp
                )
            }
        }
    }
}
