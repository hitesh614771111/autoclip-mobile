import 'package:flutter_test/flutter_test.dart';
import 'package:autoclip_mobile/core/models/transcript.dart';
import 'package:autoclip_mobile/engine/selector/clip_selector.dart';

void main() {
  group('ClipSelector Heuristics & Moment Selection', () {
    test('Selects high-scoring hook moments over filler openings', () {
      final segments = [
        TranscriptSegment(
          id: 0,
          start: 0.0,
          end: 15.0,
          text: "Um so basically welcome back guys, today we are going to talk about random stuff.",
        ),
        TranscriptSegment(
          id: 1,
          start: 15.2,
          end: 30.0,
          text: "and you know it was kind of like I said before.",
        ),
        TranscriptSegment(
          id: 2,
          start: 35.0,
          end: 55.0,
          text: "Why does nobody talk about the real secret behind 12 billion dollars in debt?",
        ),
        TranscriptSegment(
          id: 3,
          start: 55.4,
          end: 75.0,
          text: "I realized for the first time that this fatal flaw changed everything. In the end, that is how it worked.",
        ),
      ];

      final transcript = Transcript(
        language: 'en',
        duration: 80.0,
        text: segments.map((s) => s.text).join(" "),
        words: [],
        segments: segments,
      );

      final clips = ClipSelector.selectClips(
        transcript: transcript,
        numClips: 1,
      );

      expect(clips.isNotEmpty, true);
      final bestClip = clips.first;

      // The hook opening segment starting at ~35s should be chosen over the filler at 0s!
      expect(bestClip.start >= 30.0, true);
      expect(bestClip.text.contains("Why does nobody talk about"), true);
    });

    test('Derives concise titles cleanly', () {
      final title = ClipSelector.deriveTitle("Why nobody realized the true truth about money in 1939");
      expect(title, "Why nobody realized the true truth about");
    });
  });
}
