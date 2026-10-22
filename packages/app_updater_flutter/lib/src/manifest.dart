class AppArtifactInfo {
  final String key;
  final String sha256;
  final int fileSize;
  final String? downloadUrl;

  const AppArtifactInfo({
    required this.key,
    required this.sha256,
    required this.fileSize,
    this.downloadUrl,
  });

  factory AppArtifactInfo.fromJson(Map<String, dynamic> json) {
    return AppArtifactInfo(
      key: (json['key'] as String? ?? '').trim(),
      sha256: (json['sha256'] as String? ?? '').trim().toLowerCase(),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      downloadUrl: json['downloadUrl'] as String?,
    );
  }
}

class AppReleaseManifest {
  final String schema;
  final String appId;
  final String project;
  final String versionName;
  final int versionCode;
  final int minRequiredVersionCode;
  final String releaseDate;
  final String releaseNotes;
  final String apkKey;
  final String sha256;
  final int fileSize;
  final String downloadUrl;
  final bool isMandatory;
  final Map<String, AppArtifactInfo> artifacts;

  const AppReleaseManifest({
    required this.schema,
    required this.appId,
    required this.project,
    required this.versionName,
    required this.versionCode,
    required this.minRequiredVersionCode,
    required this.releaseDate,
    required this.releaseNotes,
    required this.apkKey,
    required this.sha256,
    required this.fileSize,
    required this.downloadUrl,
    required this.isMandatory,
    this.artifacts = const {},
  });

  factory AppReleaseManifest.fromJson(
    Map<String, dynamic> json, {
    required int currentVersionCode,
  }) {
    final versionCode = (json['versionCode'] as num?)?.toInt() ?? 0;
    final minReq = (json['minRequiredVersionCode'] as num?)?.toInt() ?? 1;
    final rawArtifacts = json['artifacts'];
    final parsedArtifacts = <String, AppArtifactInfo>{};
    if (rawArtifacts is Map) {
      for (final entry in rawArtifacts.entries) {
        if (entry.key is String && entry.value is Map<String, dynamic>) {
          try {
            parsedArtifacts[entry.key as String] = AppArtifactInfo.fromJson(
              entry.value as Map<String, dynamic>,
            );
          } catch (_) {
            // Ignore malformed artifact entries so the primary manifest still works
          }
        }
      }
    }

    return AppReleaseManifest(
      schema: (json['schema'] as String? ?? 'app-updater/1').trim(),
      appId: (json['appId'] as String? ?? '').trim(),
      project: (json['project'] as String? ?? '').trim(),
      versionName: (json['versionName'] as String? ?? '').trim(),
      versionCode: versionCode,
      minRequiredVersionCode: minReq,
      releaseDate: (json['releaseDate'] as String? ?? '').trim(),
      releaseNotes: (json['releaseNotes'] as String? ?? '').trim(),
      apkKey: (json['apkKey'] as String? ?? '').trim(),
      sha256: (json['sha256'] as String? ?? '').trim().toLowerCase(),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      downloadUrl: (json['downloadUrl'] as String? ?? '').trim(),
      isMandatory: currentVersionCode < minReq,
      artifacts: parsedArtifacts,
    );
  }
}

enum UpdateCheckStatus {
  upToDate,
  updateAvailable,
  unconfigured,
  error,
}

/// Outcome of an update check. The optional diagnostic fields ([appId], [endpoint], [httpStatus],
/// [remoteVersionCode], [remoteVersionName]) explain *why* the check ended the way it did.
/// None of them ever holds the auth token or the signed download URL.
///
/// On [UpdateCheckStatus.updateAvailable] [manifest] is the newer release. On
/// [UpdateCheckStatus.upToDate] it is the server's current release (kept for its release notes).
class UpdateCheckResult {
  final UpdateCheckStatus status;
  final int currentVersionCode;
  final String currentVersionName;
  final AppReleaseManifest? manifest;
  final String? errorMessage;
  final String? appId;
  final String? endpoint;
  final int? httpStatus;
  final int? remoteVersionCode;
  final String? remoteVersionName;

  /// For [UpdateCheckStatus.unconfigured]: which settings are missing (e.g. `gateway URL`, `token`).
  final List<String> missingSettings;

  const UpdateCheckResult._({
    required this.status,
    required this.currentVersionCode,
    required this.currentVersionName,
    this.manifest,
    this.errorMessage,
    this.appId,
    this.endpoint,
    this.httpStatus,
    this.remoteVersionCode,
    this.remoteVersionName,
    this.missingSettings = const [],
  });

  factory UpdateCheckResult.upToDate({
    required int currentVersionCode,
    required String currentVersionName,
    String? appId,
    String? endpoint,
    int? httpStatus,
    int? remoteVersionCode,
    String? remoteVersionName,
    AppReleaseManifest? manifest,
  }) =>
      UpdateCheckResult._(
        status: UpdateCheckStatus.upToDate,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
        manifest: manifest,
        appId: appId,
        endpoint: endpoint,
        httpStatus: httpStatus,
        remoteVersionCode: remoteVersionCode,
        remoteVersionName: remoteVersionName,
      );

  factory UpdateCheckResult.updateAvailable({
    required int currentVersionCode,
    required String currentVersionName,
    required AppReleaseManifest manifest,
    String? appId,
    String? endpoint,
    int? httpStatus,
  }) =>
      UpdateCheckResult._(
        status: UpdateCheckStatus.updateAvailable,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
        manifest: manifest,
        appId: appId,
        endpoint: endpoint,
        httpStatus: httpStatus,
        remoteVersionCode: manifest.versionCode,
        remoteVersionName: manifest.versionName,
      );

  factory UpdateCheckResult.unconfigured({
    int currentVersionCode = 0,
    String currentVersionName = '',
    String? appId,
    List<String> missingSettings = const [],
  }) =>
      UpdateCheckResult._(
        status: UpdateCheckStatus.unconfigured,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
        appId: appId,
        missingSettings: missingSettings,
      );

  factory UpdateCheckResult.error({
    required String message,
    int currentVersionCode = 0,
    String currentVersionName = '',
    String? appId,
    String? endpoint,
    int? httpStatus,
    int? remoteVersionCode,
    String? remoteVersionName,
  }) =>
      UpdateCheckResult._(
        status: UpdateCheckStatus.error,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
        errorMessage: message,
        appId: appId,
        endpoint: endpoint,
        httpStatus: httpStatus,
        remoteVersionCode: remoteVersionCode,
        remoteVersionName: remoteVersionName,
      );

  bool get hasUpdate =>
      status == UpdateCheckStatus.updateAvailable && manifest != null;

  /// One-line, user-facing explanation of the result, shared by [CheckForUpdateTile] and apps.
  String get summary {
    switch (status) {
      case UpdateCheckStatus.upToDate:
        final parts = <String>['local ${_describe(currentVersionName, currentVersionCode)}'];
        if (remoteVersionCode != null) {
          parts.add('server ${_describe(remoteVersionName ?? '', remoteVersionCode!)}');
        }
        if (httpStatus != null) parts.add('HTTP $httpStatus');
        return 'Up to date (${parts.join(', ')})';
      case UpdateCheckStatus.updateAvailable:
        final remoteName = remoteVersionName ?? manifest?.versionName ?? '';
        final remoteCode = remoteVersionCode ?? manifest?.versionCode ?? 0;
        return 'Update available (local build $currentVersionCode, '
            'server ${_describe(remoteName, remoteCode)})';
      case UpdateCheckStatus.error:
        return errorMessage ?? 'Update check failed.';
      case UpdateCheckStatus.unconfigured:
        const base = 'Update server URL or token is not configured on this device';
        if (missingSettings.isEmpty) return '$base.';
        return '$base (missing: ${missingSettings.join(', ')}).';
    }
  }

  static String _describe(String name, int code) =>
      name.isNotEmpty ? 'v$name build $code' : 'build $code';
}
