import 'transcript.dart';

class ClipCandidate {
  final double start;
  final double end;
  final String title;
  final String text;
  final double score;
  final List<TranscriptSegment> segments;

  ClipCandidate({
    required this.start,
    required this.end,
    required this.title,
    required this.text,
    required this.score,
    this.segments = const [],
  });

  double get duration => end - start;

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'title': title,
        'text': text,
        'score': score,
      };
}

class GeneratedClip {
  final String id;
  final String title;
  final double start;
  final double end;
  final String videoPath;
  final String? subtitlePath;
  final double score;

  GeneratedClip({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.videoPath,
    this.subtitlePath,
    required this.score,
  });

  double get duration => end - start;
}
