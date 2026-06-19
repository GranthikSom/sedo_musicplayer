import 'dart:async';
import 'package:flutter/services.dart';

/// Dart service that bridges Flutter UI to native iOS media controls
/// via a MethodChannel. Wraps all system media commands and metadata fetching.
class MediaController {
  static const MethodChannel _channel = MethodChannel('music/bridge');

  /// Registers a callback invoked when the native side detects a
  /// now-playing metadata change (e.g. track skip). [onChanged] should
  /// trigger a fresh call to [nowPlaying].
  void setOnNowPlayingChanged(void Function() onChanged) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'nowPlayingChanged') onChanged();
    });
  }

  /// Toggles system play/pause for the active audio session.
  Future<void> playPause() async {
    try {
      await _channel.invokeMethod('playPause');
    } on PlatformException catch (e) {
      _log('playPause failed: ${e.message}');
    } on MissingPluginException catch (e) {
      _log('MissingPluginException on playPause: ${e.message}');
    }
  }

  /// Sends the "next track" command to the active system audio session.
  Future<void> next() async {
    try {
      await _channel.invokeMethod('next');
    } on PlatformException catch (e) {
      _log('next failed: ${e.message}');
    } on MissingPluginException catch (e) {
      _log('MissingPluginException on next: ${e.message}');
    }
  }

  /// Sends the "previous track" command to the active system audio session.
  Future<void> previous() async {
    try {
      await _channel.invokeMethod('previous');
    } on PlatformException catch (e) {
      _log('previous failed: ${e.message}');
    } on MissingPluginException catch (e) {
      _log('MissingPluginException on previous: ${e.message}');
    }
  }

  /// Fetches Now Playing metadata from the system.
  ///
  /// Returns a map with:
  ///   - "title"  : track title (or "Unknown")
  ///   - "artist" : artist name (or "Unknown")
  ///
  /// Never throws — returns a safe fallback map on any error.
  Future<Map<String, dynamic>> nowPlaying() async {
    try {
      final result = await _channel.invokeMethod<Map>('nowPlaying');
      if (result == null) return _unknown();

      return {
        'title': (result['title'] as String?) ?? 'Unknown',
        'artist': (result['artist'] as String?) ?? 'Unknown',
      };
    } on PlatformException catch (e) {
      _log('nowPlaying failed: ${e.message}');
      return _unknown();
    } on MissingPluginException catch (e) {
      _log('MissingPluginException on nowPlaying: ${e.message}');
      return _unknown();
    }
  }

  Map<String, dynamic> _unknown() => {'title': 'Unknown', 'artist': 'Unknown'};

  void _log(String msg) {
    // ignore: avoid_print
    print('[MediaController] $msg');
  }
}
