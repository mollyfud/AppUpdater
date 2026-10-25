import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_updater_flutter/app_updater_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' as fm;
import 'package:material_ui/material_ui.dart';
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
  String? downloadUrlOverride,
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
    'downloadUrl': downloadUrlOverride ??
        'https://updater.example.com/api/v1/download?key=apk&expires=9999999999&sig=abc',
  };
}

UpdateService _serviceReturning(http.Response Function(http.Request req) respond) {
  return UpdateService(
    baseUrl: 'https://updater.example.com',
    authToken: 'shared-token-123',
    httpClient: MockClient((req) async => respond(req)),
    packageInfoLoader: () async => _fakePackageInfo(buildNumber: '10'),
  );
}

http.Response _jsonResponse(Object body, int status) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

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
        // CheckForUpdateTile draws status text and the Details button on notesBoxBackground
        expect(
          _contrastRatio(c.bodyColor, c.notesBoxBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} body on notesBoxBackground (tile status)',
        );
        expect(
          _contrastRatio(c.errorBannerText, c.notesBoxBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} errorBannerText on notesBoxBackground (tile error)',
        );
        expect(
          _contrastRatio(c.secondaryButtonText, c.notesBoxBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} secondaryButtonText on notesBoxBackground (Details)',
        );
      });
    }
  });

  group('AppReleaseManifest tolerance', () {
    test('oddly typed or missing optional fields parse without error', () {
      final m = AppReleaseManifest.fromJson({
        'versionCode': '19',
        'versionName': 1.46,
        'releaseNotes': null,
        'fileSize': '1234',
        'artifacts': {'windows': {'key': 'a.zip', 'sha256': 'AB', 'fileSize': 5}},
      }, currentVersionCode: 18);
      expect(m.versionCode, 19);
      expect(m.versionName, '1.46');
      expect(m.releaseNotes, '');
      expect(m.fileSize, 1234);
      expect(m.minRequiredVersionCode, 1);
      expect(m.artifacts['windows']?.sha256, 'ab');
    });

    test('list releaseNotes are joined with newlines', () {
      final m = AppReleaseManifest.fromJson({
        'versionCode': 2,
        'releaseNotes': ['One', 'Two'],
      }, currentVersionCode: 1);
      expect(m.releaseNotes, 'One\nTwo');
    });
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
      expect(result.remoteVersionCode, 10);
      expect(result.remoteVersionName, '1.3.0');
      expect(result.httpStatus, 200);
      expect(result.appId, 'com.molly.switchboard');
      expect(result.summary, contains('local v1.2.0 build 10'));
      expect(result.summary, contains('server v1.3.0 build 10'));
      expect(result.summary, contains('HTTP 200'));
    });

    test('404 with "App manifest not found" is an error naming the appId', () async {
      final service = _serviceReturning(
        (_) => _jsonResponse({'error': 'App manifest not found'}, 404),
      );
      final result = await service.checkForUpdate();
      expect(result.status, UpdateCheckStatus.error);
      expect(result.httpStatus, 404);
      expect(result.errorMessage, contains('com.molly.switchboard'));
      expect(result.errorMessage, contains('HTTP 404'));
      expect(result.summary, 'Server has no release for com.molly.switchboard (HTTP 404)');
    });

    test('plain-text 404 is an error pointing at the gateway URL', () async {
      final service = _serviceReturning((_) => http.Response('Not Found', 404));
      final result = await service.checkForUpdate();
      expect(result.status, UpdateCheckStatus.error);
      expect(result.httpStatus, 404);
      expect(
        result.errorMessage,
        contains('https://updater.example.com/api/v1/update/com.molly.switchboard'),
      );
      expect(result.errorMessage, contains('gateway URL'));
    });

    test('newer build with short sha256 is an error, not upToDate', () async {
      final service = _serviceReturning(
        (_) => _jsonResponse(_sampleManifestJson(versionCode: 14, sha256Override: 'abc'), 200),
      );
      final result = await service.checkForUpdate();
      expect(result.status, UpdateCheckStatus.error);
      expect(result.hasUpdate, isFalse);
      expect(result.remoteVersionCode, 14);
      expect(result.errorMessage, contains('sha256 length 3'));
      expect(result.errorMessage, contains('downloadUrl ok'));
    });

    test('newer build with empty downloadUrl is an error, not upToDate', () async {
      final service = _serviceReturning(
        (_) => _jsonResponse(_sampleManifestJson(versionCode: 14, downloadUrlOverride: ''), 200),
      );
      final result = await service.checkForUpdate();
      expect(result.status, UpdateCheckStatus.error);
      expect(result.errorMessage, contains('downloadUrl empty'));
    });

    test('unconfigured result names the missing settings', () async {
      final service = UpdateService(
        baseUrl: '',
        authToken: '',
        httpClient: MockClient((_) async => fail('no request expected')),
        packageInfoLoader: () async => _fakePackageInfo(),
      );
      final result = await service.checkForUpdate();
      expect(result.status, UpdateCheckStatus.unconfigured);
      expect(result.missingSettings, ['gateway URL', 'token']);
      expect(result.summary, contains('missing: gateway URL, token'));
    });

    test('refuses an http:// gateway URL without sending a request or the token', () async {
      final service = UpdateService(
        baseUrl: 'http://localhost:8787',
        authToken: 'shared-token-123',
        httpClient: MockClient((_) async => fail('no request expected')),
        packageInfoLoader: () async => _fakePackageInfo(),
      );
      final result = await service.checkForUpdate();
      expect(result.status, UpdateCheckStatus.error);
      expect(result.errorMessage, contains('must start with https://'));
      expect(service.lastCheckReport, contains('https'));
      expect(service.lastCheckReport, isNot(contains('shared-token-123')));
    });

    test('accepts an uppercase HTTPS:// gateway URL', () async {
      final service = UpdateService(
        baseUrl: 'HTTPS://updater.example.com',
        authToken: 'shared-token-123',
        httpClient: MockClient((req) async =>
            http.Response.bytes(utf8.encode(jsonEncode(_sampleManifestJson())), 200)),
        packageInfoLoader: () async => _fakePackageInfo(buildNumber: '10'),
      );
      final result = await service.checkForUpdate();
      expect(result.hasUpdate, isTrue);
    });

    test('newer build with an http:// download URL is an error, not updateAvailable', () async {
      final service = _serviceReturning((_) => _jsonResponse(
            _sampleManifestJson(downloadUrlOverride: 'http://updater.example.com/a.apk'),
            200,
          ));
      final result = await service.checkForUpdate();
      expect(result.status, UpdateCheckStatus.error);
      expect(result.errorMessage, contains('insecure download URL'));
    });

    test('downloadAndInstall refuses an http:// download URL before any I/O', () async {
      final tempDir = await Directory.systemTemp.createTemp('app_updater_http_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      var launched = false;
      final service = UpdateService(
        baseUrl: 'https://updater.example.com',
        authToken: 'shared-token-123',
        httpClient: MockClient.streaming((req, body) async => fail('no request expected')),
        tempDirProvider: () async => tempDir,
        installerLauncher: (_) async => launched = true,
      );
      final manifest = AppReleaseManifest.fromJson(
        _sampleManifestJson(downloadUrlOverride: 'http://updater.example.com/a.apk'),
        currentVersionCode: 10,
      );
      await expectLater(
        () => service.downloadAndInstall(manifest: manifest, onProgress: (_) {}),
        throwsA(isA<InsecureUrlException>()),
      );
      expect(launched, isFalse);
      expect(tempDir.listSync(recursive: true), isEmpty);
    });

    test('keeps a token-free log of the last check and resets it per check', () async {
      var code = 10;
      final service = _serviceReturning(
        (_) => _jsonResponse(_sampleManifestJson(versionCode: code), 200),
      );

      expect(service.lastCheckReport, isEmpty);
      expect(service.lastResult, isNull);

      await service.checkForUpdate();
      final report = service.lastCheckReport;
      expect(report, contains('https://updater.example.com/api/v1/update/com.molly.switchboard'));
      expect(report, contains('HTTP 200'));
      expect(report, contains('local: v1.2.0 build 10'));
      expect(report, contains('server: v1.3.0 build 10'));
      expect(report, contains('outcome: upToDate'));
      expect(report, contains('token: set (16 chars)'));
      expect(report, contains('app_updater_flutter $appUpdaterFlutterVersion'));
      expect(report, isNot(contains('shared-token-123')));
      expect(report, isNot(contains('sig=abc')));
      expect(report, isNot(contains('expires=')));
      expect(report, contains('downloadUrl present (host updater.example.com, scheme https)'));
      expect(service.lastResult?.status, UpdateCheckStatus.upToDate);
      expect(service.lastResult?.hasUpdate, isFalse);
      expect(service.lastResult?.manifest, isNotNull);
      expect(service.lastResult?.manifest?.releaseNotes, contains('Added Argon usage meter'));
      expect(service.lastCheckLog.length, report.split('\n').length);

      code = 14;
      await service.checkForUpdate();
      expect(service.lastCheckReport, contains('outcome: updateAvailable'));
      expect(service.lastCheckReport, isNot(contains('outcome: upToDate')));
      expect(
        'check started'.allMatches(service.lastCheckReport).length,
        1,
      );
      expect(service.lastCheckReport, isNot(contains('shared-token-123')));
      expect(service.lastCheckReport, isNot(contains('sig=abc')));
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
      testWidgets('material_ui app: tile follows theme and opens the Update Now dialog (${brightness.name})', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = _serviceReturning((_) => _jsonResponse(_sampleManifestJson(versionCode: 14), 200));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(body: CheckForUpdateTile(updateService: service)),
          ),
        );

        final palette = UpdateDialogColors.forBrightness(brightness);
        final tileBox = tester.widget<Container>(
          find.ancestor(of: find.text('App Updates'), matching: find.byType(Container)).first,
        );
        expect((tileBox.decoration as BoxDecoration).color, palette.notesBoxBackground);

        await tester.tap(find.byKey(const Key('check-for-update-button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Update Now'), findsOneWidget);
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(dialog.backgroundColor, palette.dialogBackground);
      });
    }

    testWidgets('dialog failure is shown in the tile status and the report', (tester) async {
      final service = _serviceReturning((_) => _jsonResponse(_sampleManifestJson(versionCode: 14), 200));
      // The tile sits above the Navigator (in MaterialApp.builder), so showDialog throws.
      await tester.pumpWidget(
        MaterialApp(
          home: const SizedBox(),
          builder: (context, child) => Stack(
            children: [
              child!,
              Material(child: Align(alignment: Alignment.topCenter, child: CheckForUpdateTile(updateService: service))),
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('check-for-update-button')));
      await tester.pumpAndSettle();
      final status = tester.widget<Text>(find.byKey(const Key('check-for-update-status'))).data!;
      expect(status, contains('could not be shown'));
      expect(status, contains('No Navigator above the update widget'));
      expect(service.lastCheckReport, contains('dialog error:'));
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('flutter/material app: tile opens the dialog (${brightness.name})', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = _serviceReturning((_) => _jsonResponse(_sampleManifestJson(versionCode: 14), 200));
        await tester.pumpWidget(
          fm.MaterialApp(
            theme: fm.ThemeData(brightness: brightness),
            home: fm.Scaffold(body: CheckForUpdateTile(updateService: service)),
          ),
        );
        final palette = UpdateDialogColors.forBrightness(brightness);

        await tester.tap(find.byKey(const Key('check-for-update-button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Update Now'), findsOneWidget);
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(dialog.backgroundColor, palette.dialogBackground);

        await tester.tap(find.byKey(const Key('update-later-button')));
        await tester.pumpAndSettle();
        expect(find.text('Update Now'), findsNothing);

        await tester.tap(find.byKey(const Key('check-for-update-details')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('check-for-update-release-notes')), findsOneWidget);
        await tester.tap(find.byKey(const Key('check-for-update-details-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('check-for-update-release-notes')), findsNothing);
      });
    }

    testWidgets('flutter/material app: checkOnLaunch opens the dialog', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final service = _serviceReturning((_) => _jsonResponse(_sampleManifestJson(versionCode: 14), 200));
      late BuildContext ctx;
      await tester.pumpWidget(
        fm.MaterialApp(home: fm.Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }))),
      );
      final future = UpdatePromptDialog.checkOnLaunch(ctx, updateService: service);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Update Now'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-later-button')));
      await tester.pumpAndSettle();
      expect((await future).hasUpdate, isTrue);
    });

    testWidgets('manifest with only the required fields still opens the dialog', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final full = _sampleManifestJson(versionCode: 14);
      final minimal = {
        for (final k in ['schema', 'appId', 'versionName', 'versionCode', 'releaseDate', 'apkKey', 'sha256', 'downloadUrl'])
          k: full[k],
      };
      final service = _serviceReturning((_) => _jsonResponse(minimal, 200));
      await tester.pumpWidget(
        fm.MaterialApp(home: fm.Scaffold(body: CheckForUpdateTile(updateService: service))),
      );
      await tester.tap(find.byKey(const Key('check-for-update-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(service.lastResult?.status, UpdateCheckStatus.updateAvailable);
      expect(find.text('Bug fixes and improvements.'), findsOneWidget);
    });

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
        expect(
          find.text('Up to date (local v1.2.0 build 10, server v1.3.0 build 10, HTTP 200)'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // "What's new" opens the release notes first, the log only on request
        expect(find.text("What's new"), findsOneWidget);
        await tester.tap(find.byKey(const Key('check-for-update-details')));
        await tester.pumpAndSettle();
        expect(find.text("What's new in v1.3.0"), findsOneWidget);
        final notesFinder = find.byKey(const Key('check-for-update-release-notes'));
        expect(tester.widget<SelectableText>(notesFinder).data!, contains('Added Argon usage meter'));
        final reportFinder = find.byKey(const Key('check-for-update-report'));
        expect(reportFinder, findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('check-for-update-toggle-log')));
        await tester.pumpAndSettle();
        expect(reportFinder, findsOneWidget);
        final reportText = tester.widget<SelectableText>(reportFinder).data!;
        expect(reportText, contains('outcome: upToDate'));
        expect(reportText, isNot(contains('shared-token-123')));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('check-for-update-details-close')));
        await tester.pumpAndSettle();
        expect(reportFinder, findsNothing);

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

      testWidgets('CheckForUpdateTile shows the 404 reason instead of up to date (${brightness.name})', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = _serviceReturning(
          (_) => _jsonResponse({'error': 'App manifest not found'}, 404),
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

        await tester.tap(find.byKey(const Key('check-for-update-button')));
        await tester.pumpAndSettle();
        expect(
          find.text('Server has no release for com.molly.switchboard (HTTP 404)'),
          findsOneWidget,
        );
        expect(find.textContaining('Up to date'), findsNothing);
        expect(find.byKey(const Key('check-for-update-details')), findsOneWidget);
        expect(find.text('Details'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // No manifest: the log opens straight away, with no notes box or toggle
        await tester.tap(find.byKey(const Key('check-for-update-details')));
        await tester.pumpAndSettle();
        expect(find.text('Last update check'), findsOneWidget);
        expect(find.byKey(const Key('check-for-update-report')), findsOneWidget);
        expect(find.byKey(const Key('check-for-update-toggle-log')), findsNothing);
        expect(find.byKey(const Key('check-for-update-release-notes')), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('CheckForUpdateTile says so when the release has no notes (${brightness.name})', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = _serviceReturning(
          (_) => _jsonResponse(
            {..._sampleManifestJson(versionCode: 10), 'releaseNotes': ''},
            200,
          ),
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

        await tester.tap(find.byKey(const Key('check-for-update-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('check-for-update-details')));
        await tester.pumpAndSettle();
        expect(find.text('No release notes for this version.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
