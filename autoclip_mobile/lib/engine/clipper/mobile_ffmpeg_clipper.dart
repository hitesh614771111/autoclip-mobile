import 'dart:io';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import '../../core/models/clip_options.dart';

class MobileFFmpegClipper {
  /// Extracts 16kHz mono 16-bit PCM WAV for Whisper speech recognition.
  static Future<bool> extractAudioWav({
    required String videoPath,
    required String outputWavPath,
    Function(double progress)? onProgress,
  }) async {
    final command = '-y -i "$videoPath" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$outputWavPath"';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    return ReturnCode.isSuccess(returnCode);
  }

  /// Renders a single viral short with 9:16 crop and burned ASS subtitles.
  static Future<bool> renderClip({
    required String inputVideoPath,
    required double startSeconds,
    required double endSeconds,
    required String outputVideoPath,
    String? assSubtitlesPath,
    AspectRatioOption aspectRatio = AspectRatioOption.vertical916,
    Function(double progress, String message)? onProgress,
  }) async {
    final double duration = endSeconds - startSeconds;
    if (duration <= 0) return false;

    // Build video filter graph
    final List<String> vfFilters = [];

    // 1. Aspect Ratio Cropping
    switch (aspectRatio) {
      case AspectRatioOption.vertical916:
        // Scale and crop to 9:16 vertical canvas (1080x1920)
        vfFilters.add("scale=-2:1920,crop=1080:1920:(iw-1080)/2:0");
        break;
      case AspectRatioOption.square11:
        // Center crop to 1:1 square
        vfFilters.add("crop=min(iw\\,ih):min(iw\\,ih)");
        break;
      case AspectRatioOption.landscape169:
        // Keep landscape, scale to 1920x1080
        vfFilters.add("scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2");
        break;
    }

    // 2. ASS Subtitle Burning (via libass)
    if (assSubtitlesPath != null && await File(assSubtitlesPath).exists()) {
      // Escape Windows or Unix backslashes for FFmpeg filter syntax
      final escapedPath = assSubtitlesPath.replaceAll('\\', '/').replaceAll(':', '\\:');
      vfFilters.add("ass='$escapedPath'");
    }

    final String vfString = vfFilters.join(",");

    // FFmpeg execution command
    final command = '-y -ss ${startSeconds.toStringAsFixed(3)} '
        '-to ${endSeconds.toStringAsFixed(3)} '
        '-i "$inputVideoPath" '
        '-vf "$vfString" '
        '-c:v libx264 -preset ultrafast -crf 23 '
        '-c:a aac -b:a 128k '
        '"$outputVideoPath"';

    FFmpegKitConfig.enableStatisticsCallback((statistics) {
      if (onProgress != null && duration > 0) {
        final double currentSeconds = statistics.getTime() / 1000.0;
        final double fraction = (currentSeconds / duration).clamp(0.0, 1.0);
        onProgress(fraction, "Rendering clip: ${(fraction * 100).toInt()}%");
      }
    });

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    return ReturnCode.isSuccess(returnCode);
  }

  /// Cancels any currently running FFmpeg tasks.
  static Future<void> cancelAll() async {
    await FFmpegKit.cancel();
  }
}
