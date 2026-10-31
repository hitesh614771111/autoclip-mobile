import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/models/clip_candidate.dart';
import '../core/models/clip_options.dart';
import '../core/models/transcript.dart';
import '../engine/captions/ass_caption_generator.dart';
import '../engine/clipper/mobile_ffmpeg_clipper.dart';
import '../engine/selector/clip_selector.dart';
import '../engine/whisper/mobile_whisper_engine.dart';

enum PipelineStage {
  idle,
  extractingAudio,
  transcribing,
  selectingMoments,
  renderingClips,
  completed,
  error,
}

class PipelineCoordinator extends ChangeNotifier {
  PipelineStage _stage = PipelineStage.idle;
  double _stageProgress = 0.0;
  double _overallProgress = 0.0;
  String _statusMessage = "Ready";
  String? _errorMessage;

  List<GeneratedClip> _generatedClips = [];
  bool _isCancelled = false;

  PipelineStage get stage => _stage;
  double get stageProgress => _stageProgress;
  double get overallProgress => _overallProgress;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  List<GeneratedClip> get generatedClips => _generatedClips;

  void _updateProgress(PipelineStage stage, double stageFrac, String message) {
    _stage = stage;
    _stageProgress = stageFrac;
    _statusMessage = message;

    // Map stage into overall progress (0.0 to 1.0)
    double base = 0.0;
    double weight = 0.0;

    switch (stage) {
      case PipelineStage.idle:
        base = 0.0;
        weight = 0.0;
        break;
      case PipelineStage.extractingAudio:
        base = 0.02;
        weight = 0.15;
        break;
      case PipelineStage.transcribing:
        base = 0.17;
        weight = 0.50;
        break;
      case PipelineStage.selectingMoments:
        base = 0.67;
        weight = 0.08;
        break;
      case PipelineStage.renderingClips:
        base = 0.75;
        weight = 0.25;
        break;
      case PipelineStage.completed:
        base = 1.0;
        weight = 0.0;
        break;
      case PipelineStage.error:
        base = 0.0;
        weight = 0.0;
        break;
    }

    _overallProgress = (base + stageFrac * weight).clamp(0.0, 1.0);
    notifyListeners();
  }

  Future<void> processVideo({
    required String videoPath,
    required ClipGenerationConfig config,
  }) async {
    _isCancelled = false;
    _errorMessage = null;
    _generatedClips = [];

    try {
      final tempDir = await getTemporaryDirectory();
      final appDocsDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final outputDir = Directory('${appDocsDir.path}/clips/$timestamp');
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // Step 1: Extract 16kHz mono WAV for Whisper
      _updateProgress(PipelineStage.extractingAudio, 0.1, "Extracting audio from video...");
      final wavPath = '${tempDir.path}/extracted_$timestamp.wav';
      final audioExtracted = await MobileFFmpegClipper.extractAudioWav(
        videoPath: videoPath,
        outputWavPath: wavPath,
      );

      if (!audioExtracted || _isCancelled) {
        throw Exception("Failed to extract audio track from video.");
      }
      _updateProgress(PipelineStage.extractingAudio, 1.0, "Audio extracted successfully.");

      // Step 2: Transcribe Offline using Whisper
      _updateProgress(PipelineStage.transcribing, 0.0, "Loading on-device Whisper model...");
      final modelPath = await MobileWhisperEngine.getOrExtractModelPath();

      final transcript = await MobileWhisperEngine.transcribeWav(
        wavPath: wavPath,
        modelPath: modelPath,
        onProgress: (prog, msg) {
          if (!_isCancelled) {
            _updateProgress(PipelineStage.transcribing, prog, msg);
          }
        },
      );

      if (_isCancelled) return;

      // Step 3: Select Highlights using Heuristic Engine
      _updateProgress(PipelineStage.selectingMoments, 0.2, "Analyzing speech cadence & hooks...");

      final candidates = ClipSelector.selectClips(
        transcript: transcript,
        numClips: config.numClips,
        targetDuration: config.targetDuration,
        onProgress: (prog, msg) => _updateProgress(PipelineStage.selectingMoments, prog, msg),
      );

      if (candidates.isEmpty) {
        throw Exception("No suitable viral moments found. Try a longer talking video.");
      }

      _updateProgress(PipelineStage.selectingMoments, 1.0, "Selected ${candidates.length} highlight moments.");

      // Step 4: Render Each Clip with 9:16 Crop and Subtitles
      final List<GeneratedClip> results = [];
      final int totalClips = candidates.length;

      for (int i = 0; i < totalClips; i++) {
        if (_isCancelled) return;

        final candidate = candidates[i];
        final clipIndex = i + 1;
        final clipProgressBase = i / totalClips;

        _updateProgress(
          PipelineStage.renderingClips,
          clipProgressBase,
          "Rendering clip $clipIndex of $totalClips: '${candidate.title}'",
        );

        // Generate ASS Subtitle File
        String? assPath;
        if (config.enableCaptions) {
          final relevantWords = transcript.words
              .where((w) => w.end > candidate.start && w.start < candidate.end)
              .toList();

          if (relevantWords.isNotEmpty) {
            final assFile = File('${outputDir.path}/clip_$clipIndex.ass');
            await AssCaptionGenerator.buildAssFile(
              words: relevantWords,
              preset: config.captionStyle,
              videoWidth: 1080,
              videoHeight: 1920,
              outputFile: assFile,
              clipStart: candidate.start,
            );
            assPath = assFile.path;
          }
        }

        // Render video with FFmpeg
        final clipVideoPath = '${outputDir.path}/clip_$clipIndex.mp4';
        final renderSuccess = await MobileFFmpegClipper.renderClip(
          inputVideoPath: videoPath,
          startSeconds: candidate.start,
          endSeconds: candidate.end,
          outputVideoPath: clipVideoPath,
          assSubtitlesPath: assPath,
          aspectRatio: config.aspectRatio,
          onProgress: (prog, msg) {
            final overallClipProg = clipProgressBase + (prog / totalClips);
            _updateProgress(
              PipelineStage.renderingClips,
              overallClipProg,
              "Rendering clip $clipIndex/$totalClips: ${(prog * 100).toInt()}%",
            );
          },
        );

        if (renderSuccess) {
          results.add(
            GeneratedClip(
              id: 'clip_${timestamp}_$clipIndex',
              title: candidate.title,
              start: candidate.start,
              end: candidate.end,
              videoPath: clipVideoPath,
              subtitlePath: assPath,
              score: candidate.score,
            ),
          );
        }
      }

      _generatedClips = results;
      _updateProgress(PipelineStage.completed, 1.0, "Generated ${results.length} viral clips!");
    } catch (e) {
      _stage = PipelineStage.error;
      _errorMessage = e.toString();
      _statusMessage = "Processing failed";
      notifyListeners();
    }
  }

  void cancel() {
    _isCancelled = true;
    MobileFFmpegClipper.cancelAll();
    _stage = PipelineStage.idle;
    _statusMessage = "Cancelled";
    notifyListeners();
  }
}
