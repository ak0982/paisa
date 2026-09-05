import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens an https URL in the system browser via Android `ACTION_VIEW`.
///
/// Deliberately **not** `url_launcher`: that plugin merges `INTERNET` into the
/// release APK, which would break the Play-honest "no network permission"
/// promise (SEC-1). Handing the URL to Chrome / the default browser needs no
/// network permission on Paisa itself.
class ExternalLink {
  const ExternalLink({
    MethodChannel channel = _defaultChannel,
    bool? isSupportedPlatform,
  })  : _channel = channel,
        _isSupportedPlatform = isSupportedPlatform;

  static const _defaultChannel = MethodChannel('com.paisa.paisa_app/security');

  @visibleForTesting
  static bool? debugSupportedPlatformOverride;

  final MethodChannel _channel;
  final bool? _isSupportedPlatform;

  bool get _supported =>
      _isSupportedPlatform ??
      debugSupportedPlatformOverride ??
      Platform.isAndroid;

  /// Returns true when the platform started an external viewer.
  Future<bool> open(String url) async {
    if (!_supported) return false;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openExternalUrl',
        {'url': trimmed},
      );
      return opened == true;
    } catch (_) {
      return false;
    }
  }
}
