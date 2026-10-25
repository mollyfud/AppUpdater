import 'package:flutter/material.dart' as fm;
import 'package:flutter/widgets.dart' as w;
import 'package:material_ui/material_ui.dart';

import 'manifest.dart';

/// Internal helpers so the SDK's dialogs work under either a `package:material_ui` `MaterialApp`
/// or a plain `package:flutter/material.dart` one (they have distinct `MaterialLocalizations` and
/// `Theme` types, so a lookup of one inside the other app finds nothing).

bool _hasUiLocalizations(BuildContext c) =>
    Localizations.of<MaterialLocalizations>(c, MaterialLocalizations) != null;

/// "Update v1.4.6 (build 19)", or "Update build 19" when the manifest has no versionName.
String describeRelease(AppReleaseManifest m) => m.versionName.isEmpty
    ? 'Update build ${m.versionCode}'
    : 'Update v${m.versionName} (build ${m.versionCode})';

/// Brightness of the host app's theme, whichever Material flavour it uses.
Brightness hostBrightness(BuildContext c) {
  if (_hasUiLocalizations(c)) return Theme.of(c).brightness;
  if (Localizations.of<fm.MaterialLocalizations>(c, fm.MaterialLocalizations) !=
      null) {
    return fm.Theme.of(c).brightness;
  }
  return MediaQuery.maybePlatformBrightnessOf(c) ?? Brightness.light;
}

/// Wraps [child] so material_ui widgets (AlertDialog, buttons, SelectableText) find the
/// localizations and theme they need even when the host is not a material_ui app.
Widget ensureMaterialContext(BuildContext hostContext, Widget child) {
  if (_hasUiLocalizations(hostContext)) return child;
  return Localizations.override(
    context: hostContext,
    delegates: const [DefaultMaterialLocalizations.delegate],
    child: Theme(
      data: ThemeData(brightness: hostBrightness(hostContext)),
      child: child,
    ),
  );
}

/// Shows a dialog without needing any `MaterialLocalizations` on [context].
Future<T?> showUpdaterDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  if (navigator == null) {
    throw StateError(
      'No Navigator above the update widget - place CheckForUpdateTile / '
      'checkOnLaunch under MaterialApp home or a route, not MaterialApp.builder',
    );
  }
  final captured =
      w.InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(
    w.RawDialogRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Dismiss',
      barrierColor: const Color(0x8A000000),
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (routeContext, _, __) => captured.wrap(
        ensureMaterialContext(context, Builder(builder: builder)),
      ),
      transitionBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
