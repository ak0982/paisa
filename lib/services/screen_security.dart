import 'dart:io';

import 'package:flutter/services.dart';

/// Screenshot / screen-recording / recents-thumbnail protection (SEC-2).
///
/// `MainActivity.onCreate` sets Android's `FLAG_SECURE` before the first frame,
/// so the app is protected from launch. This service is how the customer's
/// preference reaches the window afterwards: applying `false` clears the flag,
/// applying `true` re-adds it.
///
/// Everything is a no-op off Android (the flag is an Android window flag) and
/// a failed channel call never throws — losing the toggle must not break the
/// app, and the default (protected) is the safe direction to fail in.
class ScreenSecurity {
  const ScreenSecurity({
    MethodChannel channel = _defaultChannel,
    bool? isSupportedPlatform,
  })  : _channel = channel,
        _isSupportedPlatform = isSupportedPlatform;

  static const _defaultChannel = MethodChannel('com.paisa.paisa_app/security');

  final MethodChannel _channel;
  final bool? _isSupportedPlatform;

  bool get _supported => _isSupportedPlatform ?? Platform.isAndroid;

  /// Returns true when the platform confirmed the new state.
  Future<bool> apply({required bool blockScreenshots}) async {
    if (!_supported) return false;
    try {
      await _channel.invokeMethod<bool>(
        'setSecureScreen',
        {'enabled': blockScreenshots},
      );
      return true;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }
}
