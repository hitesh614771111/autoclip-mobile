import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_plus/whisper_flutter_plus.dart';
import '../../core/models/transcript.dart';

/// On-Device Whisper Speech-to-Text Engine.
/// Runs 100% locally using quantized GGUF models with whisper.cpp.
class MobileWhisperEngine {
  static const String defaultModelName = 'ggml-tiny.bin';

  /// Ensures the offline Whisper model exists in the app's local storage.
  static Future<String> getOrExtractModelPath({String modelName = defaultModelName}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final modelFile = File('${modelDir.path}/$modelName');
    if (await modelFile.exists() && await modelFile.length() > 1000000) {
      return modelFile.path;
    }

    // Try loading bundled asset if packaged inside the app assets
    try {
      final byteData = await rootBundle.load('assets/models/$modelName');
      await modelFile.writeAsBytes(
        byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        flush: true,
      );
      return modelFile.path;
    } catch (_) {
      // Model not bundled in assets yet, will need initial one-time download
      return modelFile.path;
    }
  }

  /// Transcribes a 16kHz mono WAV file on-device without any API calls.
  static Future<Transcript> transcribeWav({
    required String wavPath,
    required String modelPath,
    String language = 'auto',
    Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0.1, "Initializing on-device Whisper...");

    final whisper = Whisper(
      whisperLib: WhisperLib.whisper,
      model: modelPath,
    );

    onProgress?.call(0.3, "Transcribing speech on mobile CPU/NPU...");

    final WhisperTranscriptionResult result = await whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wavPath,
        language: language == 'auto' ? null : language,
        isTranslate: false,
        isNoTimestamps: false,
        splitOnWord: true,
      ),
    );

    onProgress?.call(0.9, "Processing transcript word timestamps...");

    final List<TranscriptSegment> segments = [];
    final List<WordTimestamp> allWords = [];
    final StringBuffer fullText = StringBuffer();

    for (int i = 0; i < result.segments.length; i++) {
      final seg = result.segments[i];
      final segStart = seg.from.inMilliseconds / 1000.0;
      final segEnd = seg.to.inMilliseconds / 1000.0;
      final segText = seg.text.trim();

      fullText.write("$segText ");

      final List<WordTimestamp> segWords = [];
      if (seg.words != null && seg.words!.isNotEmpty) {
        for (final w in seg.words!) {
          final wStart = w.from.inMilliseconds / 1000.0;
          final wEnd = w.to.inMilliseconds / 1000.0;
          final wt = WordTimestamp(
            word: w.word.trim(),
            start: wStart,
            end: wEnd,
            probability: w.probability,
          );
          segWords.add(wt);
          allWords.add(wt);
        }
      } else {
        // Fallback: estimate word timestamps linearly across segment if word-level wasn't emitted
        final splitWords = segText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        if (splitWords.isNotEmpty) {
          final wordDur = (segEnd - segStart) / splitWords.length;
          for (int wIdx = 0; wIdx < splitWords.length; wIdx++) {
            final wt = WordTimestamp(
              word: splitWords[wIdx],
              start: segStart + wIdx * wordDur,
              end: segStart + (wIdx + 1) * wordDur,
            );
            segWords.add(wt);
            allWords.add(wt);
          }
        }
      }

      segments.add(
        TranscriptSegment(
          id: i,
          start: segStart,
          end: segEnd,
          text: segText,
          words: segWords,
        ),
      );
    }

    final double totalDuration = segments.isNotEmpty ? segments.last.end : 0.0;

    return Transcript(
      language: language,
      duration: totalDuration,
      text: fullText.toString().trim(),
      words: allWords,
      segments: segments,
    );
  }
}
