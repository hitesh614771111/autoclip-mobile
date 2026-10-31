import 'dart:math' as math;
import '../../core/models/transcript.dart';
import '../../core/models/clip_candidate.dart';

/// Fully local Clip Selection Engine ported 1:1 from AutoClip's heuristic scorer.
/// Analyzes spoken cadence, sentence bounds, narrative hooks, and payoffs
/// with zero cloud API keys.
class ClipSelector {
  static const double minClipLen = 25.0;
  static const double maxClipLen = 55.0;
  static const double idealClipLen = 40.0;
  static const double autoSweetMin = 30.0;
  static const double autoSweetMax = 50.0;
  static const int autoCandidatesPerAnchor = 5;

  static const List<String> sentEnds = [".", "!", "?", "।", "…"];
  static const double topicPauseGap = 0.5;
  static const double topicOverlapMax = 0.25;

  static const Set<String> strongWords = {
    "how", "why", "what", "when", "who", "where", "best", "worst", "never",
    "always", "secret", "mistake", "biggest", "important", "actually", "truth",
    "realize", "realise", "amazing", "incredible", "stop", "avoid", "must",
    "everyone", "nobody", "money", "free", "new", "first", "tip", "tips",
  };

  static const Set<String> hangingTailWords = {
    "and", "but", "or", "so", "because", "if", "when", "though", "although",
    "like", "that", "which", "where", "while", "then", "with", "to", "as",
    "than", "whether", "since", "until", "unless",
  };

  static final RegExp fillerOpeningRegex = RegExp(
    r"^(?:"
    r"um\b|uh\b|er\b|ah\b|"
    r"so\s+basically\b|basically\b|"
    r"like\s+i\s+(?:was\s+)?saying\b|as\s+i\s+(?:was\s+)?saying\b|like\s+i\s+said\b|"
    r"you\s+know\b|well\s+anyway\b|anyway\b|"
    r"in\s+this\s+video\b|today\s+we(?:'re|\s+are)\s+going\s+to\b|"
    r"welcome\s+back(?:\s+to)?\b|what's\s+up\s+guys\b|hey\s+guys\b|"
    r"before\s+we\s+start\b"
    r")",
    caseSensitive: false,
  );

  static final RegExp hookOpeningRegex = RegExp(
    r"^(?:"
    r"why\b|how\b|what\s+if\b|have\s+you\s+ever\b|did\s+you\s+know\b|can\s+you\s+believe\b|"
    r"the\s+(?:biggest|real|secret|only|truth|worst|number\s+one)\b|"
    r"nobody\s+(?:knows|talks\s+about|realizes)\b|"
    r"stop\s+(?:doing|wasting|making)\b|"
    r"here(?:'s|\s+is)\s+(?:why|the|how|what)\b|"
    r"i\s+(?:realized|discovered|almost|never|decided|found\s+out)\b|"
    r"what\s+happens\s+when\b|this\s+is\s+why\b"
    r")",
    caseSensitive: false,
  );

  static final RegExp payoffRegex = RegExp(
    r"\b(?:"
    r"turns\s+out|"
    r"that(?:'s|\s+is)\s+why|"
    r"and\s+that(?:'s|\s+is)\s+how|"
    r"the\s+point\s+is|"
    r"the\s+lesson\s+(?:is|was)|"
    r"in\s+the\s+end|"
    r"at\s+the\s+end\s+of\s+the\s+day|"
    r"it\s+actually\s+worked|"
    r"the\s+result\s+(?:is|was)|"
    r"and\s+finally|"
    r"which\s+means\s+that|"
    r"that\s+is\s+the\s+secret|"
    r"that\s+is\s+how|"
    r"we\s+finally|"
    r"and\s+that\s+changed\s+everything"
    r")\b",
    caseSensitive: false,
  );

  static final RegExp narrativeRegex = RegExp(
    r"\b(?:"
    r"i\s+(?:realized|noticed|decided|discovered|learned|failed|found|felt)|"
    r"we\s+(?:discovered|decided|found|noticed|realized)|"
    r"for\s+the\s+first\s+time|"
    r"what\s+happened\s+was|"
    r"the\s+problem\s+was|"
    r"suddenly|unexpectedly|"
    r"years\s+ago|months\s+ago"
    r")\b",
    caseSensitive: false,
  );

  static final RegExp concreteNumbersRegex = RegExp(
    r"(?:\$\d+(?:,\d+)*(?:\.\d+)?|\b\d+(?:\.\d+)?%|\b\d+\s*(?:dollars|years|months|days|hours|minutes|seconds|miles|km|percent|people|times)\b)",
    caseSensitive: false,
  );

  static final RegExp wordExtractRegex = RegExp(r"\b[\w'-]+\b");

  /// Selects up to `numClips` non-overlapping highlight moments from the transcript.
  static List<ClipCandidate> selectClips({
    required Transcript transcript,
    required int numClips,
    double? targetDuration,
    Function(double progress, String message)? onProgress,
  }) {
    final segments = transcript.segments;
    if (segments.isEmpty || transcript.duration <= 0) {
      return [];
    }

    final bool userFixedLen = targetDuration != null && targetDuration > 0;
    final double targetLen = userFixedLen ? targetDuration : idealClipLen;

    final candidates = _buildCandidateWindows(
      segments: segments,
      targetLen: targetLen,
      userFixedLen: userFixedLen,
    );

    if (candidates.isEmpty) {
      return _fallbackEvenSplit(transcript, numClips, targetDuration);
    }

    onProgress?.call(0.5, "Analyzed ${candidates.length} moment candidates...");

    return _selectHeuristic(candidates, numClips);
  }

  static List<ClipCandidate> _buildCandidateWindows({
    required List<TranscriptSegment> segments,
    required double targetLen,
    required bool userFixedLen,
  }) {
    final int n = segments.length;
    if (n == 0) return [];

    final double minLen = userFixedLen ? math.max(8.0, targetLen * 0.78) : minClipLen;
    final double upperLimit = userFixedLen ? targetLen * 1.22 : maxClipLen;

    // 1. Identify starting anchors
    final List<int> anchors = [];
    int lastAnchor = -999;

    for (int i = 0; i < n; i++) {
      final segText = segments[i].text.trim();
      if (segText.isEmpty) continue;

      bool isAnchor = false;
      if (i == 0) {
        isAnchor = true;
      } else {
        final prevSeg = segments[i - 1];
        final prevText = prevSeg.text.trim();
        final pause = segments[i].start - prevSeg.end;

        if (sentEnds.any((e) => prevText.endsWith(e)) || pause >= 0.4) {
          isAnchor = true;
        } else if (segText.isNotEmpty &&
            segText[0].toUpperCase() == segText[0] &&
            !_startsWithConjunction(segText.toLowerCase())) {
          isAnchor = true;
        } else if (i - lastAnchor >= 3) {
          isAnchor = true;
        }
      }

      if (isAnchor) {
        anchors.add(i);
        lastAnchor = i;
      }
    }

    if (anchors.isEmpty) {
      for (int i = 0; i < n; i += 2) anchors.add(i);
      if (anchors.isEmpty) anchors.add(0);
    }

    // 2. Build candidate windows from each anchor
    final List<ClipCandidate> candidates = [];
    final Set<String> seenRanges = {};

    for (final i in anchors) {
      final double start = segments[i].start;
      final List<String> textParts = [];
      int? bestJ;
      double bestDiff = 9999.0;
      int? fallbackJ;
      double fallbackDiff = 9999.0;
      final List<MapEntry<int, double>> naturalEnds = [];

      for (int j = i; j < n; j++) {
        final seg = segments[j];
        final double end = seg.end;
        final String segText = seg.text.trim();
        textParts.add(segText);

        final double length = end - start;
        if (length < minLen) continue;
        if (!userFixedLen && length > upperLimit) break;

        final double diffToTarget = (length - targetLen).abs();
        final bool endsSentence = sentEnds.any((e) => segText.endsWith(e));
        bool isPause = false;

        if (j + 1 < n) {
          final nextStart = segments[j + 1].start;
          if (nextStart - end >= topicPauseGap) {
            isPause = true;
          }
        } else {
          isPause = true;
        }

        final bool topicBoundary = _isTopicBoundary(segments, j + 1, textParts);
        final bool isNaturalEnd = endsSentence || isPause || topicBoundary;

        if (isNaturalEnd) {
          if (userFixedLen) {
            if (diffToTarget < bestDiff) {
              bestDiff = diffToTarget;
              bestJ = j + 1;
            }
          } else {
            double boundaryBonus = 0.0;
            if (j + 1 >= n) {
              boundaryBonus += 0.18;
            } else {
              final gap = segments[j + 1].start - end;
              if (gap >= 1.2) {
                boundaryBonus += 0.24;
              } else if (gap >= topicPauseGap) {
                boundaryBonus += 0.14;
              }
              if (topicBoundary) boundaryBonus += 0.08;

              final nextText = segments[j + 1].text.trim().toLowerCase();
              if (RegExp(r"^(?:and|but|because|so|then|which|that|therefore|however|or|though)\b")
                  .hasMatch(nextText)) {
                boundaryBonus -= 0.35;
              }
            }
            naturalEnds.add(MapEntry(j + 1, boundaryBonus));
          }
        }

        if (diffToTarget < fallbackDiff) {
          fallbackDiff = diffToTarget;
          fallbackJ = j + 1;
        }

        if (length >= upperLimit) break;
      }

      List<MapEntry<int?, double>> chosenEnds;
      if (userFixedLen) {
        chosenEnds = [MapEntry(bestJ ?? fallbackJ, 0.0)];
      } else if (naturalEnds.isNotEmpty) {
        chosenEnds = naturalEnds.map((e) => MapEntry<int?, double>(e.key, e.value)).toList();
      } else {
        chosenEnds = [MapEntry(fallbackJ, 0.0)];
      }

      final List<ClipCandidate> localCandidates = [];
      for (final entry in chosenEnds) {
        final chosenEndJ = entry.key;
        final boundaryBonus = entry.value;

        if (chosenEndJ == null || chosenEndJ <= i) continue;

        final candSegs = segments.sublist(i, chosenEndJ);
        final candStart = _round2(candSegs.first.start);
        final candEnd = _round2(candSegs.last.end);
        final candLen = candEnd - candStart;

        if (candLen >= minLen * 0.85) {
          final rangeKey = "$candStart-$candEnd";
          if (!seenRanges.contains(rangeKey)) {
            final candText = candSegs.map((s) => s.text.trim()).where((t) => t.isNotEmpty).join(" ");
            if (candText.isNotEmpty) {
              final score = _scoreWindow(
                    text: candText,
                    length: candLen,
                    targetLen: targetLen,
                    windowSegs: candSegs,
                    adaptiveDuration: !userFixedLen,
                  ) +
                  boundaryBonus;

              localCandidates.add(
                ClipCandidate(
                  start: candStart,
                  end: candEnd,
                  title: deriveTitle(candText),
                  text: candText,
                  score: score,
                  segments: candSegs,
                ),
              );
            }
          }
        }
      }

      if (!userFixedLen) {
        localCandidates.sort((a, b) => b.score.compareTo(a.score));
        final topAnchors = localCandidates.take(autoCandidatesPerAnchor);
        for (final cand in topAnchors) {
          final rangeKey = "${cand.start}-${cand.end}";
          if (!seenRanges.contains(rangeKey)) {
            seenRanges.add(rangeKey);
            candidates.add(cand);
          }
        }
      } else {
        for (final cand in localCandidates) {
          final rangeKey = "${cand.start}-${cand.end}";
          if (!seenRanges.contains(rangeKey)) {
            seenRanges.add(rangeKey);
            candidates.add(cand);
          }
        }
      }
    }

    return candidates;
  }

  static bool _startsWithConjunction(String text) {
    for (final c in ["and", "but", "because", "so", "which", "while", "then", "or", "though"]) {
      if (text.startsWith("$c ")) return true;
    }
    return false;
  }

  static bool _isTopicBoundary(List<TranscriptSegment> segments, int j, List<String> windowTextParts) {
    if (j >= segments.length) return true;
    final prevEnd = segments[j - 1].end;
    final nxt = segments[j];
    if (nxt.start - prevEnd >= topicPauseGap) return true;

    final windowWords = _extractWords(windowTextParts.join(" ").toLowerCase());
    final nextWords = _extractWords(nxt.text.toLowerCase());
    if (windowWords.isEmpty || nextWords.isEmpty) return false;

    final intersection = windowWords.intersection(nextWords);
    final familiar = intersection.length / nextWords.length;
    return familiar < topicOverlapMax;
  }

  static Set<String> _extractWords(String text) {
    final matches = wordExtractRegex.allMatches(text);
    return matches.map((m) => m.group(0)!).toSet();
  }

  static double _scoreWindow({
    required String text,
    required double length,
    required double targetLen,
    required List<TranscriptSegment> windowSegs,
    required bool adaptiveDuration,
  }) {
    final words = wordExtractRegex.allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();
    final int wordCount = words.length;
    if (wordCount == 0) return 0.0;

    final double effectiveLength = math.max(length, 1.0);
    final double wps = wordCount / effectiveLength;

    // 1) Base Word Density
    final double densityScore = math.min(wps / 3.0, 1.0);

    // 2) Opening Quality
    double openingScore = 0.0;
    final firstWords = words.take(14).toList();
    final openingSnippet = firstWords.join(" ");
    final firstWord = words.isNotEmpty ? words.first : "";

    if (["and", "but", "because", "so", "which", "while", "then", "or", "though"].contains(firstWord)) {
      openingScore -= 0.35;
    } else if (fillerOpeningRegex.hasMatch(openingSnippet)) {
      openingScore -= 0.40;
    } else {
      if (hookOpeningRegex.hasMatch(openingSnippet)) {
        openingScore += 0.45;
      }
      if (openingSnippet.contains("?")) {
        openingScore += 0.35;
      }
    }

    // 3) Payoff & Completeness
    double payoffScore = 0.0;
    final cleanText = text.trimRight();
    final bool hasTerminalPunct = sentEnds.any((e) => cleanText.endsWith(e));
    final bool hasTrailingEllipsis =
        cleanText.endsWith("...") || cleanText.endsWith("…") || cleanText.endsWith("--") || cleanText.endsWith(",");

    final lastWords = words.length >= 8 ? words.sublist(words.length - 8) : words;
    final lastWord = lastWords.isNotEmpty ? lastWords.last : "";

    if (hasTrailingEllipsis || hangingTailWords.contains(lastWord)) {
      payoffScore -= 0.55;
    } else if (!hasTerminalPunct) {
      payoffScore -= 0.30;
    } else {
      payoffScore += 0.35;
    }

    final closingSnippet = (words.length >= 20 ? words.sublist(words.length - 20) : words).join(" ");
    if (payoffRegex.hasMatch(closingSnippet)) {
      payoffScore += 0.40;
    }

    // 4) Pacing & Speech Flow
    double pacingScore = 1.0;
    if (wps >= 2.0 && wps <= 3.8) {
      pacingScore = 1.0;
    } else if (wps < 1.3) {
      pacingScore = 0.4;
    } else if (wps > 4.5) {
      pacingScore = 0.7;
    }

    if (windowSegs.length > 1) {
      double deadAirSeconds = 0.0;
      for (int k = 0; k < windowSegs.length - 1; k++) {
        final gap = windowSegs[k + 1].start - windowSegs[k].end;
        if (gap > 1.8) deadAirSeconds += gap;
      }
      if (deadAirSeconds > 3.0) {
        pacingScore = math.max(0.2, pacingScore - 0.40);
      } else if (deadAirSeconds > 1.8) {
        pacingScore = math.max(0.3, pacingScore - 0.20);
      }
    }

    // 5) Substantive Content
    double contentScore = 0.0;
    final uniqueRatio = words.toSet().length / wordCount;
    if (uniqueRatio > 0.65) {
      contentScore += 0.25;
    } else if (uniqueRatio < 0.40) {
      contentScore -= 0.25;
    }

    if (narrativeRegex.hasMatch(text)) contentScore += 0.35;
    if (concreteNumbersRegex.hasMatch(text)) contentScore += 0.25;

    final strongHits = words.where((w) => strongWords.contains(w)).length;
    contentScore += math.min(strongHits * 0.07, 0.35);

    if (text.contains("?")) contentScore += 0.20;

    // 6) Length Fit
    double lengthFit;
    double lengthWeight;

    if (adaptiveDuration) {
      if (length >= autoSweetMin && length <= autoSweetMax) {
        lengthFit = 1.0;
      } else if (length < autoSweetMin) {
        final span = math.max(1.0, autoSweetMin - minClipLen);
        lengthFit = 0.72 + 0.28 * math.max(0.0, (length - minClipLen) / span);
      } else {
        final span = math.max(1.0, maxClipLen - autoSweetMax);
        lengthFit = 1.0 - 0.28 * math.min(1.0, (length - autoSweetMax) / span);
      }
      lengthWeight = 0.25;
    } else {
      final effectiveTarget = math.max(10.0, targetLen);
      lengthFit = 1.0 - math.min((length - effectiveTarget).abs() / effectiveTarget, 1.0);
      lengthWeight = 0.8;
    }

    // 7) Transcription Confidence
    double confidenceScore = 0.0;
    final logprobs = windowSegs.where((s) => s.avgLogprob != null).map((s) => s.avgLogprob!).toList();
    if (logprobs.isNotEmpty) {
      final avgLp = logprobs.reduce((a, b) => a + b) / logprobs.length;
      confidenceScore = math.max(0.0, math.min(1.0, (avgLp + 1.5) / 1.3));
    }

    final finalScore = 1.5 * densityScore +
        1.5 * (0.5 + openingScore) +
        1.5 * (0.5 + payoffScore) +
        1.0 * pacingScore +
        1.2 * (0.5 + contentScore) +
        lengthWeight * lengthFit +
        0.3 * confidenceScore;

    return math.max(0.0, _round3(finalScore));
  }

  static List<ClipCandidate> _selectHeuristic(List<ClipCandidate> candidates, int numClips) {
    final ranked = List<ClipCandidate>.from(candidates)..sort((a, b) => b.score.compareTo(a.score));
    final List<ClipCandidate> chosen = [];

    // Pass 1: Highest scoring non-overlapping, non-duplicate
    for (final cand in ranked) {
      if (chosen.length >= numClips) break;
      if (chosen.any((c) => _overlaps(cand, c))) continue;
      if (chosen.any((c) => _isNearDuplicate(cand, c))) continue;
      chosen.add(cand);
    }

    // Pass 2: Relaxed near-duplicate check
    if (chosen.length < numClips) {
      for (final cand in ranked) {
        if (chosen.length >= numClips) break;
        if (chosen.any((c) => _overlaps(cand, c))) continue;
        if (!chosen.contains(cand)) chosen.add(cand);
      }
    }

    // Pass 3: Chronological fallback
    if (chosen.length < numClips) {
      final chronological = List<ClipCandidate>.from(candidates)..sort((a, b) => a.start.compareTo(b.start));
      for (final cand in chronological) {
        if (chosen.length >= numClips) break;
        if (chosen.any((c) => _overlaps(cand, c))) continue;
        if (!chosen.contains(cand)) chosen.add(cand);
      }
    }

    chosen.sort((a, b) => a.start.compareTo(b.start));
    return chosen;
  }

  static bool _overlaps(ClipCandidate a, ClipCandidate b) {
    return a.start < b.end && b.start < a.end;
  }

  static bool _isNearDuplicate(ClipCandidate a, ClipCandidate b, [double threshold = 0.65]) {
    final wordsA = _extractWords(a.text.toLowerCase());
    final wordsB = _extractWords(b.text.toLowerCase());
    if (wordsA.isEmpty || wordsB.isEmpty) return false;
    final intersection = wordsA.intersection(wordsB).length;
    final union = wordsA.union(wordsB).length;
    return union > 0 && (intersection / union) >= threshold;
  }

  static String deriveTitle(String text, [int maxWords = 7]) {
    final cleaned = text.replaceAll(RegExp(r"\s+"), " ").trim();
    final words = cleaned.split(" ");
    var title = words.take(maxWords).join(" ").replaceAll(RegExp(r"^[ ,.;:-]+|[ ,.;:-]+$"), "");
    if (title.isEmpty) return "Clip";
    if (title == title.toLowerCase() || title == title.toUpperCase()) {
      title = title[0].toUpperCase() + title.substring(1);
    }
    return title;
  }

  static List<ClipCandidate> _fallbackEvenSplit(Transcript transcript, int numClips, double? clipLength) {
    final duration = transcript.duration;
    if (duration <= 0) return [];

    final double clipLen;
    final int n;

    if (clipLength != null && clipLength > 0) {
      clipLen = clipLength;
      n = math.max(1, math.min(numClips, (duration / clipLen).floor()));
    } else {
      n = math.max(1, math.min(numClips, 10));
      clipLen = math.min(45.0, math.max(minClipLen, math.min(maxClipLen, duration / n)));
    }

    final List<ClipCandidate> clips = [];
    double cursor = 0.0;
    int idx = 1;

    while (cursor < duration && clips.length < n) {
      final end = math.min(cursor + clipLen, duration);
      if (end - cursor < 3.0) break;

      clips.add(
        ClipCandidate(
          start: _round2(cursor),
          end: _round2(end),
          title: "Clip $idx",
          text: "",
          score: 1.0,
        ),
      );
      cursor = end;
      idx++;
    }

    return clips;
  }

  static double _round2(double val) => (val * 100).roundToDouble() / 100.0;
  static double _round3(double val) => (val * 1000).roundToDouble() / 100.0;
}
