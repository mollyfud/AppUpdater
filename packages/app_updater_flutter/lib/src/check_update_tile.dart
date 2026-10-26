import 'package:material_ui/material_ui.dart';

import 'host_material.dart';
import 'manifest.dart';
import 'update_dialog.dart';
import 'update_service.dart';

/// Drop-in widget for an app's Settings / About screen providing a manual "Check for Update" button
/// with clear inline status feedback (D-0003).
class CheckForUpdateTile extends StatefulWidget {
  final UpdateService updateService;
  final String? appIdOverride;
  final String title;

  /// Shows a link after a check. When the last result has a manifest ("What's new") it opens the
  /// release notes, with [UpdateService.lastCheckReport] behind "Show technical details"; otherwise
  /// ("Details") it opens the report directly.
  final bool showDetails;

  const CheckForUpdateTile({
    super.key,
    required this.updateService,
    this.appIdOverride,
    this.title = 'App Updates',
    this.showDetails = true,
  });

  @override
  State<CheckForUpdateTile> createState() => _CheckForUpdateTileState();
}

class _CheckForUpdateTileState extends State<CheckForUpdateTile> {
  bool _isChecking = false;
  String? _statusMessage;
  bool _isError = false;
  UpdateCheckResult? _lastResult;

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
    _lastResult = result;

    final manifest = result.manifest;
    if (result.hasUpdate && manifest != null) {
      final label = describeRelease(manifest);
      setState(() {
        _isChecking = false;
        _statusMessage = '$label is available!';
        _isError = false;
      });
      try {
        await showUpdaterDialog<void>(
          context,
          barrierDismissible: !manifest.isMandatory,
          builder: (_) => UpdatePromptDialog(
            manifest: manifest,
            updateService: widget.updateService,
          ),
        );
      } catch (e, st) {
        widget.updateService.recordDialogFailure(e, st);
        if (!mounted) return;
        final reason = e is StateError ? e.message : '$e';
        setState(() {
          _statusMessage =
              '$label is available but the update dialog could not be shown: $reason';
          _isError = true;
        });
      }
      return;
    }

    setState(() {
      _isChecking = false;
      _statusMessage = result.summary;
      _isError = result.status == UpdateCheckStatus.error ||
          result.status == UpdateCheckStatus.unconfigured;
    });
  }

  Future<void> _showDetails() async {
    final report = widget.updateService.lastCheckReport;
    final manifest = _lastResult?.manifest;
    try {
      await _openDetailsDialog(report, manifest);
    } catch (e, st) {
      widget.updateService.recordDialogFailure(e, st);
      if (!mounted) return;
      final reason = e is StateError ? e.message : '$e';
      setState(() {
        _statusMessage = 'Could not open details: $reason';
        _isError = true;
      });
    }
  }

  Future<void> _openDetailsDialog(String report, AppReleaseManifest? manifest) {
    return showUpdaterDialog<void>(
      context,
      builder: (dialogContext) {
        final palette =
            UpdateDialogColors.forBrightness(hostBrightness(dialogContext));
        var showLog = manifest == null;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final titleStyle = TextStyle(
              color: palette.titleColor,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            );
            return AlertDialog(
              backgroundColor: palette.dialogBackground,
              surfaceTintColor: Colors.transparent,
              title: manifest == null
                  ? Text('Last update check', style: titleStyle)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            manifest.versionName.isEmpty
                                ? "What's new in build ${manifest.versionCode}"
                                : "What's new in v${manifest.versionName}",
                            style: titleStyle),
                        Text(
                          '(build ${manifest.versionCode})',
                          style: TextStyle(
                            color: palette.bodyColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (manifest != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: palette.notesBoxBackground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: palette.notesBoxBorder),
                        ),
                        child: SelectableText(
                          manifest.releaseNotes.trim().isNotEmpty
                              ? manifest.releaseNotes
                              : 'No release notes for this version.',
                          key: const Key('check-for-update-release-notes'),
                          style: TextStyle(
                            color: palette.notesTextColor,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    if (showLog) ...[
                      if (manifest != null) const SizedBox(height: 12),
                      SelectableText(
                        report.isNotEmpty
                            ? report
                            : 'No update check has run yet.',
                        key: const Key('check-for-update-report'),
                        style: TextStyle(
                          color: palette.bodyColor,
                          fontSize: 12,
                          height: 1.4,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (manifest != null)
                  TextButton(
                    key: const Key('check-for-update-toggle-log'),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.secondaryButtonText,
                    ),
                    onPressed: () =>
                        setDialogState(() => showLog = !showLog),
                    child: Text(showLog
                        ? 'Hide technical details'
                        : 'Show technical details'),
                  ),
                TextButton(
                  key: const Key('check-for-update-details-close'),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.secondaryButtonText,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = UpdateDialogColors.forBrightness(hostBrightness(context));

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
            if (widget.showDetails && !_isChecking)
              TextButton(
                key: const Key('check-for-update-details'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.secondaryButtonText,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                onPressed: _showDetails,
                child: Text(
                    _lastResult?.manifest != null ? "What's new" : 'Details'),
              ),
          ],
        ],
      ),
    );
  }
}
