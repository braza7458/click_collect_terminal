import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Gets a new-order arrival noticed in a kitchen: a real bundled chime
/// (`assets/audio/new_order_alert.wav`) looped until staff dismiss it with
/// [stopAlarm], or after a 5-minute safety cutoff, plus a vibration on
/// start.
///
/// Deliberately NOT built on `dart:ui`'s `SystemSound.play` — its `alert`
/// type has no audible effect on Android (only `click` reliably produces
/// sound there), which is why the terminal used to receive orders silently.
/// A bundled asset through a real audio player is the only way to
/// guarantee a sound actually plays.
class AlertService {
  const AlertService._();

  static final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
  static Timer? _safetyTimer;

  static const _safetyCutoff = Duration(minutes: 5);

  /// Starts (or restarts, if already ringing) the looping alarm. Restarting
  /// resets the 5-minute cutoff, so a fresh order arriving while a previous
  /// one is still unacknowledged keeps the alarm going for another 5
  /// minutes rather than letting it cut off early.
  ///
  /// [onAutoStop] fires if the safety cutoff is reached without anyone
  /// calling [stopAlarm], so the caller can clear its own "dismiss" UI in
  /// step.
  static Future<void> startAlarm({VoidCallback? onAutoStop}) async {
    try {
      HapticFeedback.vibrate();
    } catch (_) {
      // No vibration motor (e.g. desktop) — fine, the sound still plays.
    }
    _safetyTimer?.cancel();
    try {
      await _player.stop();
      await _player.setVolume(1.0);
      await _player.play(AssetSource('audio/new_order_alert.wav'));
    } catch (_) {
      // No audio output on this device/platform — the visual banner on
      // ReceptionScreen still covers it.
    }
    _safetyTimer = Timer(_safetyCutoff, () {
      _safetyTimer = null;
      unawaited(_player.stop());
      onAutoStop?.call();
    });
  }

  static Future<void> stopAlarm() async {
    _safetyTimer?.cancel();
    _safetyTimer = null;
    try {
      await _player.stop();
    } catch (_) {
      // No audio output on this device/platform.
    }
  }
}
