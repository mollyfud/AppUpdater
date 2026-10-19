import 'package:flutter/material.dart';

import 'manifest.dart';
import 'update_dialog.dart';
import 'update_service.dart';

/// Drop-in widget for an app's Settings / About screen providing a manual "Check for Update" button
/// with clear inline status feedback (D-0003).
class CheckForUpdateTile extends StatefulWidget {
  final UpdateService updateService;
  final String? appIdOverride;
  final String title;

  const CheckForUpdateTile({
    super.key,
    required this.updateService,
    this.appIdOverride,
    this.title = 'App Updates',
  });

  @override
  State<CheckForUpdateTile> createState() => _CheckForUpdateTileState();
}

class _CheckForUpdateTileState extends State<CheckForUpdateTile> {
  bool _isChecking = false;
  String? _statusMessage;
  bool _isError = false;

  Future<void> _runCheck() async {
    setState(() {
      _isChecking = true;
      _statusMessage = 'Checking for updates...';
      _isError = false;
    });

    final result = await widget.updateService.checkForUpdate(
      appIdOverride: widget.appIdOverride,
    );

    if (!mounted) return;

    if (result.hasUpdate && result.manifest != null) {
      setState(() {
        _isChecking = false;
        _statusMessage =
            'Update v${result.manifest!.versionName} (build ${result.manifest!.versionCode}) is available!';
        _isError = false;
      });
      await showDialog<void>(
        context: context,
        barrierDismissible: !result.manifest!.isMandatory,
        builder: (_) => UpdatePromptDialog(
          manifest: result.manifest!,
          updateService: widget.updateService,
        ),
      );
      return;
    }

    setState(() {
      _isChecking = false;
      switch (result.status) {
        case UpdateCheckStatus.upToDate:
          final ver = result.currentVersionName.isNotEmpty
              ? 'v${result.currentVersionName} (${result.currentVersionCode})'
              : 'build ${result.currentVersionCode}';
          _statusMessage = 'You are up to date ($ver).';
          _isError = false;
        case UpdateCheckStatus.unconfigured:
          _statusMessage =
              'Update server URL or token is not configured on this device.';
          _isError = true;
        case UpdateCheckStatus.error:
          _statusMessage = result.errorMessage ?? 'Update check failed.';
          _isError = true;
        case UpdateCheckStatus.updateAvailable:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette = UpdateDialogColors.forBrightness(brightness);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.notesBoxBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.notesBoxBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: palette.titleColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              ElevatedButton.icon(
                key: const Key('check-for-update-button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.primaryButtonBackground,
                  foregroundColor: palette.primaryButtonText,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _isChecking ? null : _runCheck,
                icon: const Icon(Icons.system_update, size: 18),
                label: Text(_isChecking ? 'Checking...' : 'Check for Update'),
              ),
            ],
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage!,
              key: const Key('check-for-update-status'),
              style: TextStyle(
                color: _isError ? palette.errorBannerText : palette.bodyColor,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
