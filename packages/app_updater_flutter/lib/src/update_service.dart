import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'manifest.dart';

typedef ApkInstallerLauncher = Future<void> Function(String apkFilePath);

class UpdateService {
  final String baseUrl;
  final String authToken;
  final http.Client _httpClient;
  final Future<PackageInfo> Function()? _packageInfoLoader;
  final Future<Directory> Function()? _tempDirProvider;
  final ApkInstallerLauncher? _installerLauncher;

  UpdateService({
    required this.baseUrl,
    required this.authToken,
    http.Client? httpClient,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<Directory> Function()? tempDirProvider,
    ApkInstallerLauncher? installerLauncher,
  })  : _httpClient = httpClient ?? http.Client(),
        _packageInfoLoader = packageInfoLoader,
        _tempDirProvider = tempDirProvider,
        _installerLauncher = installerLauncher;

  /// Checks the Cloudflare Worker gateway (`GET /api/v1/update/:appId`) for a newer APK release.
  /// Never throws; returns an [UpdateCheckResult] describing the state.
  Future<UpdateCheckResult> checkForUpdate({String? appIdOverride}) async {
    if (kIsWeb) {
      return UpdateCheckResult.unconfigured();
    }

    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final cleanToken = authToken.trim();

    PackageInfo pkgInfo;
    try {
      final loader = _packageInfoLoader;
      pkgInfo = await (loader != null
          ? loader()
          : PackageInfo.fromPlatform());
    } catch (e) {
      return UpdateCheckResult.error(
        message: 'Could not read installed package version: $e',
      );
    }

    final currentCode = int.tryParse(pkgInfo.buildNumber) ?? 0;
    final currentName = pkgInfo.version;
    final appId = (appIdOverride ?? pkgInfo.packageName).trim();

    if (cleanBase.isEmpty || cleanToken.isEmpty || appId.isEmpty) {
      return UpdateCheckResult.unconfigured(
        currentVersionCode: currentCode,
        currentVersionName: currentName,
      );
    }

    final endpoint = cleanBase.endsWith('/api/v1/update')
        ? '$cleanBase/${Uri.encodeComponent(appId)}'
        : '$cleanBase/api/v1/update/${Uri.encodeComponent(appId)}';

    http.Response response;
    try {
      response = await _httpClient.get(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $cleanToken',
          'Accept': 'application/json',
        },
      );
    } catch (e) {
      return UpdateCheckResult.error(
        message: 'Could not connect to update server ($e)',
        currentVersionCode: currentCode,
        currentVersionName: currentName,
      );
    }

    if (response.statusCode == 404) {
      return UpdateCheckResult.upToDate(
        currentVersionCode: currentCode,
        currentVersionName: currentName,
      );
    }

    if (response.statusCode == 403 || response.statusCode == 401) {
      return UpdateCheckResult.error(
        message: 'Update check unauthorized (HTTP ${response.statusCode})',
        currentVersionCode: currentCode,
        currentVersionName: currentName,
      );
    }

    if (response.statusCode != 200) {
      return UpdateCheckResult.error(
        message: 'Update server returned HTTP ${response.statusCode}',
        currentVersionCode: currentCode,
        currentVersionName: currentName,
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return UpdateCheckResult.error(
          message: 'Malformed manifest response',
          currentVersionCode: currentCode,
          currentVersionName: currentName,
        );
      }

      final manifest = AppReleaseManifest.fromJson(
        decoded,
        currentVersionCode: currentCode,
      );

      if (manifest.versionCode > currentCode &&
          manifest.downloadUrl.isNotEmpty &&
          manifest.sha256.length == 64) {
        return UpdateCheckResult.updateAvailable(
          currentVersionCode: currentCode,
          currentVersionName: currentName,
          manifest: manifest,
        );
      }

      return UpdateCheckResult.upToDate(
        currentVersionCode: currentCode,
        currentVersionName: currentName,
      );
    } catch (e) {
      return UpdateCheckResult.error(
        message: 'Could not parse update manifest: $e',
        currentVersionCode: currentCode,
        currentVersionName: currentName,
      );
    }
  }

  /// Streams the APK download to disk, computes its SHA-256 digest in a streaming pass
  /// (avoiding loading the full APK into memory), verifies the checksum, and launches the
  /// Android package installer.
  Future<File> downloadAndInstall({
    required AppReleaseManifest manifest,
    required ValueChanged<double> onProgress,
  }) async {
    final baseTemp = await (_tempDirProvider != null
        ? _tempDirProvider()
        : getTemporaryDirectory());
    final updateDir = Directory('${baseTemp.path}/updates');
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }

    final apkFile = File('${updateDir.path}/update-v${manifest.versionCode}.apk');
    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    final request = http.Request('GET', Uri.parse(manifest.downloadUrl));
    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
      throw Exception(
        'APK download failed (HTTP ${streamedResponse.statusCode})',
      );
    }

    final totalBytes = streamedResponse.contentLength ?? manifest.fileSize;
    int receivedBytes = 0;

    final sink = apkFile.openWrite();
    try {
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress((receivedBytes / totalBytes).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // Stream file through SHA-256 without loading entire APK into memory at once
    final digest = await sha256.bind(apkFile.openRead()).first;
    final actualHash = digest.toString().toLowerCase();
    if (actualHash != manifest.sha256.toLowerCase()) {
      await apkFile.delete();
      throw Exception(
        'Security Error: APK SHA-256 checksum mismatch! Expected ${manifest.sha256}, got $actualHash.',
      );
    }

    if (_installerLauncher != null) {
      await _installerLauncher(apkFile.path);
    } else {
      await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );
    }

    return apkFile;
  }
}
