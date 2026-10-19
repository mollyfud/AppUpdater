import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_updater_flutter/app_updater_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

double _relativeLuminance(Color c) {
  double channel(double v) {
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrastRatio(Color a, Color b) {
  final l1 = _relativeLuminance(a);
  final l2 = _relativeLuminance(b);
  final brightest = math.max(l1, l2);
  final darkest = math.min(l1, l2);
  return (brightest + 0.05) / (darkest + 0.05);
}

PackageInfo _fakePackageInfo({
  String version = '1.2.0',
  String buildNumber = '10',
  String packageName = 'com.molly.switchboard',
}) {
  return PackageInfo(
    appName: 'Switchboard',
    packageName: packageName,
    version: version,
    buildNumber: buildNumber,
  );
}

Map<String, dynamic> _sampleManifestJson({
  int versionCode = 14,
  int minRequiredVersionCode = 12,
  String? sha256Override,
}) {
  final apkBytes = utf8.encode('MOCK_SIGNED_APK_BINARY');
  final computedSha = sha256.convert(apkBytes).toString();
  return {
    'schema': 'app-updater/1',
    'appId': 'com.molly.switchboard',
    'project': 'Switchboard',
    'versionName': '1.3.0',
    'versionCode': versionCode,
    'minRequiredVersionCode': minRequiredVersionCode,
    'releaseDate': '2026-10-20T08:00:00Z',
    'releaseNotes': '• Added Argon usage meter\n• Improved mobile layout',
    'apkKey': 'com.molly.switchboard/builds/Switchboard-v1.3.0.apk',
    'sha256': sha256Override ?? computedSha,
    'fileSize': apkBytes.length,
    'downloadUrl': 'https://updater.example.com/api/v1/download?key=apk&expires=9999999999&sig=abc',
  };
}

void main() {
  group('UpdateDialogColors WCAG 4.5:1 Contrast Verification', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      test('meets >= 4.5:1 contrast ratio in ${brightness.name} mode', () {
        final c = UpdateDialogColors.forBrightness(brightness);
        expect(
          _contrastRatio(c.titleColor, c.dialogBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} title on dialogBackground',
        );
        expect(
          _contrastRatio(c.bodyColor, c.dialogBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} body on dialogBackground',
        );
        expect(
          _contrastRatio(c.notesTextColor, c.notesBoxBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} notesText on notesBoxBackground',
        );
        expect(
          _contrastRatio(c.mandatoryBannerText, c.mandatoryBannerBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} mandatoryBannerText on mandatoryBannerBackground',
        );
        expect(
          _contrastRatio(c.errorBannerText, c.errorBannerBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} errorBannerText on errorBannerBackground',
        );
        expect(
          _contrastRatio(c.primaryButtonText, c.primaryButtonBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} primaryButtonText on primaryButtonBackground',
        );
        expect(
          _contrastRatio(c.secondaryButtonText, c.dialogBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} secondaryButtonText on dialogBackground',
        );
      });
    }
  });

  group('UpdateService', () {
    test('returns updateAvailable when remote versionCode > local versionCode', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(), 'https://updater.example.com/api/v1/update/com.molly.switchboard');
        expect(req.headers['Authorization'], 'Bearer shared-token-123');
        return http.Response.bytes(
          utf8.encode(jsonEncode(_sampleManifestJson(versionCode: 14, minRequiredVersionCode: 12))),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = UpdateService(
        baseUrl: 'https://updater.example.com',
        authToken: 'shared-token-123',
        httpClient: client,
        packageInfoLoader: () async => _fakePackageInfo(buildNumber: '10'),
      );

      final result = await service.checkForUpdate();
      expect(result.errorMessage, isNull);
      expect(result.hasUpdate, isTrue);
      expect(result.manifest!.versionName, '1.3.0');
      expect(result.manifest!.versionCode, 14);
      expect(result.manifest!.isMandatory, isTrue);
    });

    test('returns upToDate when remote versionCode <= local versionCode', () async {
      final client = MockClient((req) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode(_sampleManifestJson(versionCode: 10))),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = UpdateService(
        baseUrl: 'https://updater.example.com',
        authToken: 'shared-token-123',
        httpClient: client,
        packageInfoLoader: () async => _fakePackageInfo(buildNumber: '10'),
      );

      final result = await service.checkForUpdate();
      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.hasUpdate, isFalse);
    });

    test('streams download, verifies SHA-256, and invokes installer launcher', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_updater_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final apkBytes = utf8.encode('MOCK_SIGNED_APK_BINARY');
      String? launchedPath;

      final client = MockClient.streaming((req, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([apkBytes]),
          200,
          contentLength: apkBytes.length,
        );
      });

      final service = UpdateService(
        baseUrl: 'https://updater.example.com',
        authToken: 'shared-token-123',
        httpClient: client,
        tempDirProvider: () async => tempDir,
        installerLauncher: (path) async {
          launchedPath = path;
        },
      );

      final manifest = AppReleaseManifest.fromJson(
        _sampleManifestJson(),
        currentVersionCode: 10,
      );

      final progressEvents = <double>[];
      final file = await service.downloadAndInstall(
        manifest: manifest,
        onProgress: progressEvents.add,
      );

      expect(await file.exists(), isTrue);
      expect(progressEvents.last, 1.0);
      expect(launchedPath, file.path);
    });

    test('deletes APK and throws on SHA-256 mismatch', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_updater_bad_sha_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final apkBytes = utf8.encode('TAMPERED_APK_BINARY');
      final client = MockClient.streaming((req, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([apkBytes]),
          200,
          contentLength: apkBytes.length,
        );
      });

      final service = UpdateService(
        baseUrl: 'https://updater.example.com',
        authToken: 'shared-token-123',
        httpClient: client,
        tempDirProvider: () async => tempDir,
        installerLauncher: (_) async {},
      );

      final manifest = AppReleaseManifest.fromJson(
        _sampleManifestJson(
          sha256Override: '0000000000000000000000000000000000000000000000000000000000000000',
        ),
        currentVersionCode: 10,
      );

      await expectLater(
        () => service.downloadAndInstall(manifest: manifest, onProgress: (_) {}),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Widgets (UpdatePromptDialog & CheckForUpdateTile at 360px mobile width)', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('CheckForUpdateTile shows up-to-date message and opens dialog when update available (${brightness.name})', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        bool returnUpdate = false;
        final client = MockClient((req) async {
          final code = returnUpdate ? 14 : 10;
          return http.Response.bytes(
            utf8.encode(jsonEncode(_sampleManifestJson(versionCode: code, minRequiredVersionCode: 1))),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final service = UpdateService(
          baseUrl: 'https://updater.example.com',
          authToken: 'shared-token-123',
          httpClient: client,
          packageInfoLoader: () async => _fakePackageInfo(version: '1.2.0', buildNumber: '10'),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: CheckForUpdateTile(updateService: service),
              ),
            ),
          ),
        );

        // 1. Tap Check for Update when already up to date
        await tester.tap(find.byKey(const Key('check-for-update-button')));
        await tester.pumpAndSettle();
        expect(find.textContaining('You are up to date (v1.2.0 (10))'), findsOneWidget);

        // 2. Now simulate a new release published and tap Check for Update again
        returnUpdate = true;
        await tester.tap(find.byKey(const Key('check-for-update-button')));
        await tester.pumpAndSettle();

        expect(find.text('Update v1.3.0 Available'), findsOneWidget);
        expect(find.byKey(const Key('update-now-button')), findsOneWidget);
        expect(find.byKey(const Key('update-later-button')), findsOneWidget);

        // Dismiss via Later
        await tester.tap(find.byKey(const Key('update-later-button')));
        await tester.pumpAndSettle();
        expect(find.text('Update v1.3.0 Available'), findsNothing);
      });
    }
  });
}
