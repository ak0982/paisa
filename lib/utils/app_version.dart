import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';

/// Fallback when [PackageInfo.fromPlatform] is unavailable (e.g. plain unit
/// tests). Keep in sync with `version:` in `pubspec.yaml` (name part only).
const fallbackAppVersionName = '1.0.1';

/// Resolves the marketing version from the platform package info.
Future<String> resolveAppVersionName() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    if (version.isNotEmpty) return version;
  } catch (_) {
    // MissingPluginException in some test hosts, etc.
  }
  return fallbackAppVersionName;
}

String formatAppVersionLabel(String version) => 'My Paisa · version $version';

/// Footer-style version stamp used on Help / You.
class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({super.key, this.textStyle});

  final TextStyle? textStyle;

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  late Future<String> _label;

  @override
  void initState() {
    super.initState();
    _label = resolveAppVersionName().then(formatAppVersionLabel);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.textStyle ??
        PaisaTheme.manrope(
          size: 11.5,
          color: PaisaColors.muted,
        );
    return FutureBuilder<String>(
      future: _label,
      builder: (context, snapshot) {
        final text = snapshot.data ??
            formatAppVersionLabel(fallbackAppVersionName);
        return Text(text, style: style, textAlign: TextAlign.center);
      },
    );
  }
}
