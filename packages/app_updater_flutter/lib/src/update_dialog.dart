import 'package:material_ui/material_ui.dart';

import 'manifest.dart';
import 'update_service.dart';

class UpdateDialogColors {
  final Color dialogBackground;
  final Color titleColor;
  final Color bodyColor;
  final Color notesBoxBackground;
  final Color notesBoxBorder;
  final Color notesTextColor;
  final Color mandatoryBannerBackground;
  final Color mandatoryBannerText;
  final Color errorBannerBackground;
  final Color errorBannerText;
  final Color primaryButtonBackground;
  final Color primaryButtonText;
  final Color secondaryButtonText;

  const UpdateDialogColors({
    required this.dialogBackground,
    required this.titleColor,
    required this.bodyColor,
    required this.notesBoxBackground,
    required this.notesBoxBorder,
    required this.notesTextColor,
    required this.mandatoryBannerBackground,
    required this.mandatoryBannerText,
    required this.errorBannerBackground,
    required this.errorBannerText,
    required this.primaryButtonBackground,
    required this.primaryButtonText,
    required this.secondaryButtonText,
  });

  /// Returns an explicit palette with verified >= 4.5:1 WCAG contrast for both light and dark themes.
  factory UpdateDialogColors.forBrightness(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const UpdateDialogColors(
        dialogBackground: Color(0xFF1A1D24),
        titleColor: Color(0xFFF3F4F6),
        bodyColor: Color(0xFFD1D5DB),
        notesBoxBackground: Color(0xFF111318),
        notesBoxBorder: Color(0xFF374151),
        notesTextColor: Color(0xFFE5E7EB),
        mandatoryBannerBackground: Color(0xFF450A0A),
        mandatoryBannerText: Color(0xFFFECACA),
        errorBannerBackground: Color(0xFF450A0A),
        errorBannerText: Color(0xFFFECACA),
        primaryButtonBackground: Color(0xFF60A5FA),
        primaryButtonText: Color(0xFF0A0E17),
        secondaryButtonText: Color(0xFF93C5FD),
      );
    }
    return const UpdateDialogColors(
      dialogBackground: Color(0xFFFFFFFF),
      titleColor: Color(0xFF111827),
      bodyColor: Color(0xFF374151),
      notesBoxBackground: Color(0xFFF3F4F6),
      notesBoxBorder: Color(0xFFD1D5DB),
      notesTextColor: Color(0xFF1F2937),
      mandatoryBannerBackground: Color(0xFFFEF2F2),
      mandatoryBannerText: Color(0xFF991B1B),
      errorBannerBackground: Color(0xFFFEF2F2),
      errorBannerText: Color(0xFF991B1B),
      primaryButtonBackground: Color(0xFF1D4ED8),
      primaryButtonText: Color(0xFFFFFFFF),
      secondaryButtonText: Color(0xFF1E40AF),
    );
  }
}

class UpdatePromptDialog extends StatefulWidget {
  final AppReleaseManifest manifest;
  final UpdateService updateService;

  const UpdatePromptDialog({
    super.key,
    required this.manifest,
    required this.updateService,
  });

  /// Checks for an update on app launch and displays [UpdatePromptDialog] if a newer release is available.
  /// Silent if already up-to-date, unconfigured, or offline.
  static Future<UpdateCheckResult> checkOnLaunch(
    BuildContext context, {
    required UpdateService updateService,
    String? appIdOverride,
  }) async {
    final result = await updateService.checkForUpdate(
      appIdOverride: appIdOverride,
    );
    if (result.hasUpdate && context.mounted) {
      try {
        await showDialog<void>(
          context: context,
          barrierDismissible: !result.manifest!.isMandatory,
          builder: (_) => UpdatePromptDialog(
            manifest: result.manifest!,
            updateService: updateService,
          ),
        );
      } catch (e, st) {
        updateService.recordDialogFailure(e, st);
      }
    }
    return result;
  }

  @override
  State<UpdatePromptDialog> createState() => _UpdatePromptDialogState();
}

class _UpdatePromptDialogState extends State<UpdatePromptDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _errorMessage;

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _errorMessage = null;
    });

    try {
      await widget.updateService.downloadAndInstall(
        manifest: widget.manifest,
        onProgress: (p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
      );
      if (mounted && !widget.manifest.isMandatory) {
        Navigator.of(context).pop();
      } else if (mounted) {
        setState(() => _isDownloading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette = UpdateDialogColors.forBrightness(brightness);
    final sizeText = _formatBytes(widget.manifest.fileSize);

    return PopScope(
      canPop: !widget.manifest.isMandatory && !_isDownloading,
      child: AlertDialog(
        backgroundColor: palette.dialogBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Update v${widget.manifest.versionName} Available',
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
              if (widget.manifest.isMandatory)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.mandatoryBannerBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'This is a required update to continue using the app.',
                    style: TextStyle(
                      color: palette.mandatoryBannerText,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              Text(
                sizeText.isNotEmpty
                    ? 'Build ${widget.manifest.versionCode} ($sizeText)'
                    : 'Build ${widget.manifest.versionCode}',
                style: TextStyle(
                  color: palette.bodyColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "What's new:",
                style: TextStyle(
                  color: palette.titleColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.notesBoxBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.notesBoxBorder),
                ),
                child: Text(
                  widget.manifest.releaseNotes.isNotEmpty
                      ? widget.manifest.releaseNotes
                      : 'Bug fixes and improvements.',
                  style: TextStyle(
                    color: palette.notesTextColor,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
              if (_isDownloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  key: const Key('update-download-progress'),
                  value: _progress,
                  backgroundColor: palette.notesBoxBorder,
                  color: palette.primaryButtonBackground,
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_progress * 100).toStringAsFixed(0)}% downloaded — verifying SHA-256 checksum on completion...',
                  style: TextStyle(
                    color: palette.bodyColor,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  key: const Key('update-error-banner'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.errorBannerBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: palette.errorBannerText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Use Wrap instead of Row so buttons stack cleanly on < 400px mobile widths
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!widget.manifest.isMandatory && !_isDownloading)
                    TextButton(
                      key: const Key('update-later-button'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.secondaryButtonText,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Later'),
                    ),
                  ElevatedButton(
                    key: const Key('update-now-button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.primaryButtonBackground,
                      foregroundColor: palette.primaryButtonText,
                    ),
                    onPressed: _isDownloading ? null : _startUpdate,
                    child: Text(
                      _isDownloading ? 'Downloading...' : 'Update Now',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
