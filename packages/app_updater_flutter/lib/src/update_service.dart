import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'manifest.dart';

/// SDK version reported in the update-check log. Bump together with `pubspec.yaml`.
const appUpdaterFlutterVersion = '0.5.2';

/// Thrown when a URL the SDK is asked to fetch is not `https://`.
/// The message names only the scheme, never the URL (download URLs carry a signature).
class InsecureUrlException implements Exception {
  final String message;
  const InsecureUrlException(this.message);

  @override
  String toString() => message;
}

/// Parses [url] and returns it only if it is `https://` with a host. No exceptions, not even
/// localhost. Route every URL the SDK fetches through this.
Uri requireHttpsUri(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) {
    throw const InsecureUrlException(
        'Refusing insecure update URL: it could not be parsed (https required)');
  }
  if (uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    final scheme = uri.scheme.isEmpty ? '(none)' : uri.scheme;
    throw InsecureUrlException(
        "Refusing insecure update URL: scheme '$scheme' is not https");
  }
  return uri;
}

typedef ApkInstallerLauncher = Future<void> Function(String apkFilePath);

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

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

  final List<String> _lastCheckLog = [];
  UpdateCheckResult? _lastResult;

  /// Token-free log lines of the most recent [checkForUpdate] call (cleared at the start of each call).
  List<String> get lastCheckLog => List.unmodifiable(_lastCheckLog);

  /// Result of the most recent [checkForUpdate] call, or null before the first check.
  UpdateCheckResult? get lastResult => _lastResult;

  /// [lastCheckLog] joined with newlines, ready for a selectable/copyable text box in Settings.
  String get lastCheckReport => _lastCheckLog.join('\n');

  /// Records that showing the update dialog failed, so it appears in [lastCheckReport].
  void recordDialogFailure(Object error, StackTrace stack) {
    _log('dialog error: $error');
    final frames = stack
        .toString()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(3);
    for (final f in frames) {
      _log('  at ${f.trim()}');
    }
  }

  void _log(String line) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _lastCheckLog.add('${two(now.hour)}:${two(now.minute)}:${two(now.second)} $line');
    debugPrint('[app_updater] $line');
  }

  UpdateCheckResult _finish(UpdateCheckResult result, String reason) {
    _log('outcome: ${result.status.name} - $reason');
    _lastResult = result;
    return result;
  }

  /// Drops query string, fragment and user info so signed URLs and credentials never reach the log.
  static String _sanitizeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return url.split('?').first.split('#').first;
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }

  /// Checks the Cloudflare Worker gateway (`GET /api/v1/update/:appId`) for a newer APK release.
  /// Never throws; returns an [UpdateCheckResult] describing the state. Each call also records a
  /// token-free diagnostic log, available afterwards via [lastCheckLog] / [lastCheckReport].
  Future<UpdateCheckResult> checkForUpdate({String? appIdOverride}) async {
    _lastCheckLog.clear();
    _lastResult = null;
    _log('check started (app_updater_flutter $appUpdaterFlutterVersion)');

    if (kIsWeb) {
      return _finish(
        UpdateCheckResult.unconfigured(),
        'update checks are not supported on web',
      );
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
      _log('package info error: $e');
      return _finish(
        UpdateCheckResult.error(
          message: 'Could not read installed package version: $e',
        ),
        'could not read installed package version',
      );
    }

    final currentCode = int.tryParse(pkgInfo.buildNumber) ?? 0;
    final currentName = pkgInfo.version;
    final appId = (appIdOverride ?? pkgInfo.packageName).trim();
    final overridden = appIdOverride != null;

    _log('appId: ${appId.isEmpty ? '(empty)' : appId}'
        '${overridden ? ' (appIdOverride)' : ' (package name)'}');
    _log('local: v$currentName build $currentCode'
        ' (buildNumber "${pkgInfo.buildNumber}")');
    _log(cleanToken.isEmpty
        ? 'token: missing'
        : 'token: set (${cleanToken.length} chars)');

    final missing = <String>[
      if (cleanBase.isEmpty) 'gateway URL',
      if (cleanToken.isEmpty) 'token',
      if (appId.isEmpty) 'app id',
    ];
    if (missing.isNotEmpty) {
      return _finish(
        UpdateCheckResult.unconfigured(
          currentVersionCode: currentCode,
          currentVersionName: currentName,
          appId: appId.isEmpty ? null : appId,
          missingSettings: missing,
        ),
        'missing ${missing.join(', ')}',
      );
    }

    final endpoint = cleanBase.endsWith('/api/v1/update')
        ? '$cleanBase/${Uri.encodeComponent(appId)}'
        : '$cleanBase/api/v1/update/${Uri.encodeComponent(appId)}';
    final safeEndpoint = _sanitizeUrl(endpoint);
    _log('endpoint: GET $safeEndpoint');

    final Uri endpointUri;
    try {
      endpointUri = requireHttpsUri(endpoint);
    } on InsecureUrlException {
      _log('blocked: gateway URL is not https');
      final scheme = Uri.tryParse(endpoint)?.scheme ?? '';
      return _finish(
        UpdateCheckResult.error(
          message: 'Update server URL must start with https:// '
              '(got ${scheme.isEmpty ? 'no scheme' : '$scheme://'})',
          currentVersionCode: currentCode,
          currentVersionName: currentName,
          appId: appId,
          endpoint: safeEndpoint,
        ),
        'gateway URL is not https',
      );
    }

    http.Response response;
    try {
      response = await _httpClient.get(
        endpointUri,
        headers: {
          'Authorization': 'Bearer $cleanToken',
          'Accept': 'application/json',
        },
      );
    } catch (e) {
      _log('connect error: $e');
      return _finish(
        UpdateCheckResult.error(
          message: 'Could not connect to update server at $safeEndpoint ($e)',
          currentVersionCode: currentCode,
          currentVersionName: currentName,
          appId: appId,
          endpoint: safeEndpoint,
        ),
        'request failed',
      );
    }

    final status = response.statusCode;
    _log('response: HTTP $status, ${response.bodyBytes.length} bytes');

    if (status == 404) {
      String? serverError;
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body is Map && body['error'] is String) {
          serverError = body['error'] as String;
        }
      } catch (_) {
        // Not JSON (e.g. the Worker's plain-text route 404); handled below.
      }
      if (serverError == 'App manifest not found') {
        return _finish(
          UpdateCheckResult.error(
            message: 'Server has no release for $appId (HTTP 404)',
            currentVersionCode: currentCode,
            currentVersionName: currentName,
            appId: appId,
            endpoint: safeEndpoint,
            httpStatus: status,
          ),
          'gateway reached but no manifest is published for this app id',
        );
      }
      return _finish(
        UpdateCheckResult.error(
          message: 'Update endpoint not found at $safeEndpoint (HTTP 404)'
              ' - check the gateway URL',
          currentVersionCode: currentCode,
          currentVersionName: currentName,
          appId: appId,
          endpoint: safeEndpoint,
          httpStatus: status,
        ),
        'route not found; the gateway URL is probably wrong',
      );
    }

    if (status == 403 || status == 401) {
      return _finish(
        UpdateCheckResult.error(
          message: 'Update check unauthorized (HTTP $status) at $safeEndpoint',
          currentVersionCode: currentCode,
          currentVersionName: currentName,
          appId: appId,
          endpoint: safeEndpoint,
          httpStatus: status,
        ),
        'token rejected',
      );
    }

    if (status != 200) {
      return _finish(
        UpdateCheckResult.error(
          message: 'Update server returned HTTP $status at $safeEndpoint',
          currentVersionCode: currentCode,
          currentVersionName: currentName,
          appId: appId,
          endpoint: safeEndpoint,
          httpStatus: status,
        ),
        'unexpected HTTP status',
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return _finish(
          UpdateCheckResult.error(
            message: 'Malformed manifest response',
            currentVersionCode: currentCode,
            currentVersionName: currentName,
            appId: appId,
            endpoint: safeEndpoint,
            httpStatus: status,
          ),
          'response body is not a JSON object',
        );
      }

      final manifest = AppReleaseManifest.fromJson(
        decoded,
        currentVersionCode: currentCode,
      );
      final hasDownloadUrl = manifest.downloadUrl.isNotEmpty;
      final downloadHost =
          hasDownloadUrl ? (Uri.tryParse(manifest.downloadUrl)?.host ?? '?') : '';
      final downloadScheme =
          hasDownloadUrl ? (Uri.tryParse(manifest.downloadUrl)?.scheme ?? '?') : '';
      var downloadIsHttps = false;
      if (hasDownloadUrl) {
        try {
          requireHttpsUri(manifest.downloadUrl);
          downloadIsHttps = true;
        } on InsecureUrlException {
          downloadIsHttps = false;
        }
      }
      _log('server: v${manifest.versionName} build ${manifest.versionCode}'
          '${manifest.appId.isNotEmpty ? ' (appId ${manifest.appId})' : ''}');
      _log('server manifest: sha256 length ${manifest.sha256.length}, downloadUrl '
          '${hasDownloadUrl ? 'present (host $downloadHost, scheme $downloadScheme)' : 'empty'}');

      if (manifest.versionCode > currentCode) {
        if (hasDownloadUrl && !downloadIsHttps) {
          return _finish(
            UpdateCheckResult.error(
              message: 'Server build ${manifest.versionCode} is newer than local build '
                  '$currentCode but the manifest has an insecure download URL '
                  '(https required)',
              currentVersionCode: currentCode,
              currentVersionName: currentName,
              appId: appId,
              endpoint: safeEndpoint,
              httpStatus: status,
              remoteVersionCode: manifest.versionCode,
              remoteVersionName: manifest.versionName,
            ),
            'newer build but download URL is not https',
          );
        }
        if (hasDownloadUrl && manifest.sha256.length == 64) {
          return _finish(
            UpdateCheckResult.updateAvailable(
              currentVersionCode: currentCode,
              currentVersionName: currentName,
              manifest: manifest,
              appId: appId,
              endpoint: safeEndpoint,
              httpStatus: status,
            ),
            'server build ${manifest.versionCode} > local build $currentCode',
          );
        }
        return _finish(
          UpdateCheckResult.error(
            message: 'Server build ${manifest.versionCode} is newer than local build '
                '$currentCode but its manifest is incomplete (sha256 length '
                '${manifest.sha256.length}, downloadUrl '
                '${hasDownloadUrl ? 'ok' : 'empty'})',
            currentVersionCode: currentCode,
            currentVersionName: currentName,
            appId: appId,
            endpoint: safeEndpoint,
            httpStatus: status,
            remoteVersionCode: manifest.versionCode,
            remoteVersionName: manifest.versionName,
          ),
          'newer build but manifest incomplete',
        );
      }

      return _finish(
        UpdateCheckResult.upToDate(
          currentVersionCode: currentCode,
          currentVersionName: currentName,
          appId: appId,
          endpoint: safeEndpoint,
          httpStatus: status,
          remoteVersionCode: manifest.versionCode,
          remoteVersionName: manifest.versionName,
          manifest: manifest,
        ),
        'server build ${manifest.versionCode} <=local build $currentCode',
      );
    } catch (e) {
      _log('parse error: $e');
      return _finish(
        UpdateCheckResult.error(
          message: 'Could not parse update manifest: $e',
          currentVersionCode: currentCode,
          currentVersionName: currentName,
          appId: appId,
          endpoint: safeEndpoint,
          httpStatus: status,
        ),
        'manifest could not be parsed',
      );
    }
  }

  /// Streams the APK download to disk, computes its SHA-256 digest in a single streaming pass
  /// in-flight (avoiding loading the full APK into memory or a second disk read), verifies
  /// the checksum, and launches the Android package installer.
  Future<File> downloadAndInstall({
    required AppReleaseManifest manifest,
    required ValueChanged<double> onProgress,
  }) async {
    // Checked first so nothing (cache, request, installer) happens for an insecure URL.
    final downloadUri = requireHttpsUri(manifest.downloadUrl);

    final baseTemp = await (_tempDirProvider != null
        ? _tempDirProvider()
        : getTemporaryDirectory());
    final updateDir = Directory('${baseTemp.path}/updates');
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }

    final apkFile = File('${updateDir.path}/update-v${manifest.versionCode}.apk');

    // Reuse verified cached APK if already fully downloaded and hash matches
    if (await apkFile.exists()) {
      try {
        final existingDigest = await sha256.bind(apkFile.openRead()).first;
        if (existingDigest.toString().toLowerCase() == manifest.sha256.toLowerCase()) {
          _log('cached APK already verified (sha256 match); skipping download');
          onProgress(1.0);
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
      } catch (_) {
        // If unreadable, fall through and delete
      }
      await apkFile.delete();
    }

    final request = http.Request('GET', downloadUri);
    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
      throw Exception(
        'APK download failed (HTTP ${streamedResponse.statusCode})',
      );
    }

    final totalBytes = streamedResponse.contentLength ?? manifest.fileSize;
    int receivedBytes = 0;

    final digestSink = _DigestSink();
    final hashInput = sha256.startChunkedConversion(digestSink);
    final sink = apkFile.openWrite();

    try {
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        hashInput.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress((receivedBytes / totalBytes).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      hashInput.close();
    } catch (e) {
      await sink.close();
      if (await apkFile.exists()) {
        await apkFile.delete();
      }
      rethrow;
    } finally {
      await sink.close();
    }

    final actualHash = (digestSink.digest?.toString() ?? '').toLowerCase();
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
