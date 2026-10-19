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

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final int currentVersionCode;
  final String currentVersionName;
  final AppReleaseManifest? manifest;
  final String? errorMessage;

  const UpdateCheckResult._({
    required this.status,
    required this.currentVersionCode,
    required this.currentVersionName,
    this.manifest,
    this.errorMessage,
  });

  factory UpdateCheckResult.upToDate({
    required int currentVersionCode,
    required String currentVersionName,
  }) =>
      UpdateCheckResult._(
        status: UpdateCheckStatus.upToDate,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
      );

  factory UpdateCheckResult.updateAvailable({
    required int currentVersionCode,
    required String currentVersionName,
    required AppReleaseManifest manifest,
  }) =>
      UpdateCheckResult._(
        status: UpdateCheckStatus.updateAvailable,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
        manifest: manifest,
      );

  factory UpdateCheckResult.unconfigured({
    int currentVersionCode = 0,
    String currentVersionName = '',
  }) =>
      UpdateCheckResult._(
        status: UpdateCheckStatus.unconfigured,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
      );

  factory UpdateCheckResult.error({
    required String message,
    int currentVersionCode = 0,
    String currentVersionName = '',
  }) =>
      UpdateCheckResult._(
        status: UpdateCheckStatus.error,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
        errorMessage: message,
      );

  bool get hasUpdate =>
      status == UpdateCheckStatus.updateAvailable && manifest != null;
}
