import 'package:flutter_tts/flutter_tts.dart';

/// Handles text-to-speech audio feedback during workouts.
/// Includes a cooldown timer so the same message is not
/// repeated too rapidly, which would be chaotic during exercise.
class AudioFeedbackService {
  final FlutterTts _tts = FlutterTts();

  // Minimum milliseconds between any two spoken messages.
  // 4 seconds gives enough time for the message to finish
  // and not overlap with the next one.
  static const int _cooldownMs = 1500;

  DateTime? _lastSpokenAt;
  String    _lastMessage = '';
  bool      _isEnabled   = false;

  AudioFeedbackService() {
    _initialiseTts();
  }

  Future<void> _initialiseTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45); // Slightly slower than default for clarity
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  /// Enable or disable audio feedback.
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) _tts.stop();
  }

  bool get isEnabled => _isEnabled;

  /// Speak a feedback message, subject to cooldown and deduplication.
  /// Will not speak if:
  /// - Audio is disabled
  /// - The same message was just spoken
  /// - Cooldown period has not elapsed
  Future<void> speak(String message) async {
    if (!_isEnabled) return;
    if (message.isEmpty) return;

    final now = DateTime.now();

    // Skip if within cooldown window
    if (_lastSpokenAt != null) {
      final elapsed = now.difference(_lastSpokenAt!).inMilliseconds;
      if (elapsed < _cooldownMs) return;
    }

    // Skip if identical to last message (avoids repeating same correction)
    if (message == _lastMessage) return;

    _lastSpokenAt = now;
    _lastMessage  = message;
    await _tts.speak(message);
  }

/// Speaks a priority message — used for encouragement and
/// half rep warnings. Bypasses deduplication so the same
/// message can fire again after the cooldown elapses.
Future<void> speakPriority(String message) async {
  if (!_isEnabled) return;
  if (message.isEmpty) return;

  final now = DateTime.now();
  if (_lastSpokenAt != null) {
    final elapsed = now.difference(_lastSpokenAt!).inMilliseconds;
    if (elapsed < _cooldownMs) return;
  }

  _lastSpokenAt = now;
  _lastMessage  = message;
  await _tts.speak(message);
}

  /// Speak rep count milestones called when rep count changes.
  /// Only announces at meaningful milestones to avoid constant chatter.
  Future<void> announceRepCount(int repCount) async {
    if (!_isEnabled) return;
    if (repCount <= 0) return;

    // Announce every 5 reps and every single rep up to 10
    final shouldAnnounce = repCount <= 10 || repCount % 5 == 0;
    if (!shouldAnnounce) return;

    final now = DateTime.now();
    if (_lastSpokenAt != null) {
      final elapsed = now.difference(_lastSpokenAt!).inMilliseconds;
      if (elapsed < _cooldownMs) return;
    }

    _lastSpokenAt = now;
    _lastMessage  = repCount.toString();
    await _tts.speak(repCount.toString());
  }

  /// Release TTS resources when the screen is disposed.
  Future<void> dispose() async {
    await _tts.stop();
  }
}