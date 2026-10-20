import 'package:material_ui/material_ui.dart';

import 'manifest.dart';
import 'update_dialog.dart';
import 'update_service.dart';

/// Drop-in widget for an app's Settings / About screen providing a manual "Check for Update" button
/// with clear inline status feedback (D-0003).
class CheckForUpdateTile extends StatefulWidget {
  final UpdateService updateService;
  final String? appIdOverride;
  final String title;

  /// Shows a "Details" button after a check that opens [UpdateService.lastCheckReport].
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
      try {
        await showDialog<void>(
          context: context,
          barrierDismissible: !result.manifest!.isMandatory,
          builder: (_) => UpdatePromptDialog(
            manifest: result.manifest!,
            updateService: widget.updateService,
          ),
        );
      } catch (e, st) {
        widget.updateService.recordDialogFailure(e, st);
        if (!mounted) return;
        setState(() {
          _statusMessage =
              'Update v${result.manifest!.versionName} is available but the update dialog could not be shown: $e';
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final palette =
            UpdateDialogColors.forBrightness(Theme.of(dialogContext).brightness);
        return AlertDialog(
          backgroundColor: palette.dialogBackground,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Last update check',
            style: TextStyle(
              color: palette.titleColor,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  report.isNotEmpty ? report : 'No update check has run yet.',
                  key: const Key('check-for-update-report'),
                  style: TextStyle(
                    color: palette.bodyColor,
                    fontSize: 12,
                    height: 1.4,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 16),
                // Wrap instead of Row so the action fits on < 400px widths
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      key: const Key('check-for-update-details-close'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.secondaryButtonText,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
            if (widget.showDetails && !_isChecking)
              TextButton(
                key: const Key('check-for-update-details'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.secondaryButtonText,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                onPressed: _showDetails,
                child: const Text('Details'),
              ),
          ],
        ],
      ),
    );
  }
}
