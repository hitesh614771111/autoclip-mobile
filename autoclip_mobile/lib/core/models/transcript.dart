class WordTimestamp {
  final String word;
  final double start;
  final double end;
  final double? probability;

  WordTimestamp({
    required this.word,
    required this.start,
    required this.end,
    this.probability,
  });

  factory WordTimestamp.fromJson(Map<String, dynamic> json) {
    return WordTimestamp(
      word: json['word']?.toString() ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      probability: (json['probability'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'word': word,
        'start': start,
        'end': end,
        if (probability != null) 'probability': probability,
      };
}

class TranscriptSegment {
  final int id;
  final double start;
  final double end;
  final String text;
  final double? avgLogprob;
  final List<WordTimestamp> words;

  TranscriptSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
    this.avgLogprob,
    this.words = const [],
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    final rawWords = json['words'] as List<dynamic>? ?? [];
    return TranscriptSegment(
      id: json['id'] as int? ?? 0,
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      text: json['text']?.toString().trim() ?? '',
      avgLogprob: (json['avg_logprob'] as num?)?.toDouble(),
      words: rawWords
          .map((w) => WordTimestamp.fromJson(Map<String, dynamic>.from(w as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start,
        'end': end,
        'text': text,
        if (avgLogprob != null) 'avg_logprob': avgLogprob,
        'words': words.map((w) => w.toJson()).toList(),
      };
}

class Transcript {
  final String language;
  final double duration;
  final String text;
  final List<WordTimestamp> words;
  final List<TranscriptSegment> segments;

  Transcript({
    required this.language,
    required this.duration,
    required this.text,
    required this.words,
    required this.segments,
  });

  factory Transcript.fromJson(Map<String, dynamic> json) {
    final rawWords = json['words'] as List<dynamic>? ?? [];
    final rawSegments = json['segments'] as List<dynamic>? ?? [];

    return Transcript(
      language: json['language']?.toString() ?? 'en',
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      text: json['text']?.toString() ?? '',
      words: rawWords
          .map((w) => WordTimestamp.fromJson(Map<String, dynamic>.from(w as Map)))
          .toList(),
      segments: rawSegments
          .map((s) => TranscriptSegment.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'language': language,
        'duration': duration,
        'text': text,
        'words': words.map((w) => w.toJson()).toList(),
        'segments': segments.map((s) => s.toJson()).toList(),
      };
}
