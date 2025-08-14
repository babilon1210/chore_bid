import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> init() async {
    // Ensure we await completion so quick, short phrases don’t cut off
    await _tts.awaitSpeakCompletion(true);

    // Language & defaults (tweak to taste)
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48); // 0.0–1.0
    await _tts.setPitch(0.75);      // <1.0 = deeper, >1.0 = higher
    await _tts.setVolume(1.0);

    // iOS: make sure it plays even in silent mode, and ducks other audio slightly
    if (Platform.isIOS) {
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }

    // Try to pick a deeper US English voice if available (device-dependent)
    // This just picks the first en-US voice that mentions "male" (many engines don’t expose gender; it’s best-effort).
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        final enUs = voices.where((v) {
          final lang = (v['locale'] ?? v['language'] ?? '').toString().toLowerCase();
          return lang.startsWith('en-us');
        }).toList();

        // Prefer names that hint at a deeper/standard male voice if present.
        final preferred = enUs.firstWhere(
          (v) {
            final name = (v['name'] ?? '').toString().toLowerCase();
            return name.contains('male') || name.contains('standard') || name.contains('baritone');
          },
          orElse: () => enUs.isNotEmpty ? enUs.first : null,
        );

        if (preferred != null) {
          await _tts.setVoice({
            'name': preferred['name'],
            'locale': (preferred['locale'] ?? preferred['language'] ?? 'en-US').toString(),
          });
        }
      }
    } catch (_) {
      // Fallback silently if the engine doesn’t expose voices
    }

    // Optional warm-up to avoid the first-utterance delay on some engines
    await _tts.speak(' '); // say a space
    await _tts.stop();

    _ready = true;
  }

  Future<void> sayAwesome() async {
    if (!_ready) await init();
    // One, clean word—short and punchy
    await _tts.speak('Awesome!');
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
