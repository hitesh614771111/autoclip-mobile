import 'dart:io';
import 'dart:math' as math;
import '../../core/models/transcript.dart';
import '../../core/models/clip_options.dart';

class AssCaptionGenerator {
  /// Builds a complete ASS subtitle file matching AutoClip styles.
  static Future<File> buildAssFile({
    required List<WordTimestamp> words,
    required CaptionStylePreset preset,
    required int videoWidth,
    required int videoHeight,
    required File outputFile,
    double clipStart = 0.0,
  }) async {
    final assContent = generateAssContent(
      words: words,
      preset: preset,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      clipStart: clipStart,
    );

    await outputFile.writeAsString(assContent);
    return outputFile;
  }

  static String generateAssContent({
    required List<WordTimestamp> words,
    required CaptionStylePreset preset,
    required int videoWidth,
    required int videoHeight,
    double clipStart = 0.0,
  }) {
    final styleConfig = _getStyleConfig(preset);
    final double scale = videoHeight / 1920.0;
    final int fontSize = math.max(16, (styleConfig.fontSize * scale).round());
    final int outline = math.max(1, (styleConfig.outline * scale).round());
    final int shadow = (styleConfig.shadow * scale).round();

    final String primaryAssColor = _hexToAss(styleConfig.primaryColor);
    final String highlightAssColor = _hexToAss(styleConfig.highlightColor);
    final String outlineAssColor = _hexToAss(styleConfig.outlineColor);
    final String shadowAssColor = "&H80000000";

    final int marginV = (videoHeight * 0.16).round(); // Place at bottom 16% of screen
    final int marginH = (videoWidth * 0.06).round();

    final header = '''[Script Info]
Title: AutoClip Mobile Captions
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
PlayResX: $videoWidth
PlayResY: $videoHeight

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,${styleConfig.fontFamily},$fontSize,$primaryAssColor,$highlightAssColor,$outlineAssColor,$shadowAssColor,${styleConfig.bold ? -1 : 0},0,0,0,100,100,1,0,1,$outline,$shadow,2,$marginH,$marginH,$marginV,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
''';

    final groupedEvents = _groupEvents(words, maxChars: styleConfig.maxChars, maxLines: styleConfig.maxLines);
    final buffer = StringBuffer(header);

    for (final ev in groupedEvents) {
      final double start = ev.start - clipStart;
      final double end = ev.end - clipStart;
      if (end <= 0) continue;
      final double safeStart = math.max(0.0, start);

      final String dialogueText;
      switch (styleConfig.animation) {
        case 'one_word':
          dialogueText = _buildOneWordText(ev.lines.first.first, styleConfig.uppercase);
          break;
        case 'karaoke':
          dialogueText = _buildKaraokeText(ev.lines, styleConfig.uppercase);
          break;
        case 'highlight':
          dialogueText = _buildHighlightText(ev, styleConfig, highlightAssColor, primaryAssColor);
          break;
        default:
          dialogueText = _buildPlainText(ev.lines, styleConfig.uppercase);
      }

      final startStr = _formatAssTime(safeStart);
      final endStr = _formatAssTime(end);
      buffer.writeln("Dialogue: 0,$startStr,$endStr,Default,,0,0,0,,$dialogueText");
    }

    return buffer.toString();
  }

  static String _buildHighlightText(
    _CaptionEvent ev,
    _PresetConfig cfg,
    String highlightAss,
    String primaryAss,
  ) {
    final buffer = StringBuffer();
    for (int l = 0; l < ev.lines.length; l++) {
      if (l > 0) buffer.write("\\N");
      final line = ev.lines[l];
      for (int w = 0; w < line.length; w++) {
        final wordObj = line[w];
        final wordStr = cfg.uppercase ? wordObj.word.toUpperCase() : wordObj.word;
        if (w > 0) buffer.write(" ");

        // Dynamic word highlight using ASS color change
        // For standard ASS, word highlight is split into consecutive sub-events or ASS transform
        buffer.write("{\\c$primaryAss}$wordStr");
      }
    }
    return buffer.toString();
  }

  static String _buildKaraokeText(List<List<WordTimestamp>> lines, bool uppercase) {
    final buffer = StringBuffer();
    for (int l = 0; l < lines.length; l++) {
      if (l > 0) buffer.write("\\N");
      final line = lines[l];
      for (int w = 0; w < line.length; w++) {
        final word = line[w];
        final int centiseconds = math.max(1, ((word.end - word.start) * 100).round());
        final wordStr = uppercase ? word.word.toUpperCase() : word.word;
        buffer.write("{\\k$centiseconds}$wordStr ");
      }
    }
    return buffer.toString().trimRight();
  }

  static String _buildOneWordText(WordTimestamp word, bool uppercase) {
    return uppercase ? word.word.toUpperCase() : word.word;
  }

  static String _buildPlainText(List<List<WordTimestamp>> lines, bool uppercase) {
    return lines
        .map((l) => l.map((w) => uppercase ? w.word.toUpperCase() : w.word).join(" "))
        .join("\\N");
  }

  static List<_CaptionEvent> _groupEvents(
    List<WordTimestamp> words, {
    int maxChars = 20,
    int maxLines = 2,
    double maxSpan = 2.8,
  }) {
    final List<_CaptionEvent> events = [];
    if (words.isEmpty) return events;

    List<List<WordTimestamp>> currentLines = [[]];

    void flush() {
      final allWords = currentLines.expand((l) => l).toList();
      if (allWords.isNotEmpty) {
        events.add(_CaptionEvent(
          start: allWords.first.start,
          end: allWords.last.end,
          lines: currentLines,
        ));
      }
      currentLines = [[]];
    }

    for (final w in words) {
      final allCurrent = currentLines.expand((l) => l).toList();
      if (allCurrent.isNotEmpty && (w.end - allCurrent.first.start) > maxSpan) {
        flush();
      }

      final curLine = currentLines.last;
      final currentLineLen = curLine.fold<int>(0, (sum, item) => sum + item.word.length) + (curLine.isNotEmpty ? curLine.length - 1 : 0);
      final tentative = currentLineLen + (curLine.isNotEmpty ? 1 : 0) + w.word.length;

      if (curLine.isNotEmpty && tentative > maxChars) {
        if (currentLines.length < maxLines) {
          currentLines.add([w]);
        } else {
          flush();
          currentLines = [
            [w]
          ];
        }
      } else {
        curLine.add(w);
      }
    }

    flush();
    return events;
  }

  static String _hexToAss(String hex) {
    var c = hex.replaceAll("#", "").trim();
    if (c.length == 6) {
      // #RRGGBB -> &H00BBGGRR
      final r = c.substring(0, 2);
      final g = c.substring(2, 4);
      final b = c.substring(4, 6);
      return "&H00$b$g$r&";
    }
    return "&H00FFFFFF&";
  }

  static String _formatAssTime(double seconds) {
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds.toInt() % 60;
    final int cs = ((seconds - seconds.toInt()) * 100).round();
    return "$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}";
  }

  static _PresetConfig _getStyleConfig(CaptionStylePreset preset) {
    switch (preset) {
      case CaptionStylePreset.hormozi:
        return _PresetConfig(
          fontFamily: "Montserrat",
          bold: true,
          fontSize: 94,
          primaryColor: "#FFFFFF",
          highlightColor: "#FFD400",
          outlineColor: "#000000",
          outline: 6,
          shadow: 2,
          animation: "highlight",
          uppercase: true,
          maxChars: 16,
          maxLines: 2,
        );
      case CaptionStylePreset.beast:
        return _PresetConfig(
          fontFamily: "Anton",
          bold: false,
          fontSize: 104,
          primaryColor: "#FFFFFF",
          highlightColor: "#22C55E",
          outlineColor: "#000000",
          outline: 8,
          shadow: 3,
          animation: "highlight",
          uppercase: true,
          maxChars: 15,
          maxLines: 2,
        );
      case CaptionStylePreset.neonGlow:
        return _PresetConfig(
          fontFamily: "Roboto",
          bold: true,
          fontSize: 90,
          primaryColor: "#F3F4F6",
          highlightColor: "#22D3EE",
          outlineColor: "#0F172A",
          outline: 6,
          shadow: 2,
          animation: "highlight",
          uppercase: true,
          maxChars: 18,
          maxLines: 2,
        );
      case CaptionStylePreset.karaoke:
        return _PresetConfig(
          fontFamily: "Montserrat",
          bold: true,
          fontSize: 92,
          primaryColor: "#FFFFFF",
          highlightColor: "#FFE600",
          outlineColor: "#000000",
          outline: 6,
          shadow: 2,
          animation: "karaoke",
          uppercase: true,
          maxChars: 18,
          maxLines: 2,
        );
      case CaptionStylePreset.cleanWhite:
        return _PresetConfig(
          fontFamily: "Roboto",
          bold: true,
          fontSize: 84,
          primaryColor: "#FFFFFF",
          highlightColor: "#FFFFFF",
          outlineColor: "#000000",
          outline: 4,
          shadow: 3,
          animation: "plain",
          uppercase: false,
          maxChars: 22,
          maxLines: 2,
        );
    }
  }
}

class _CaptionEvent {
  final double start;
  final double end;
  final List<List<WordTimestamp>> lines;

  _CaptionEvent({required this.start, required this.end, required this.lines});
}

class _PresetConfig {
  final String fontFamily;
  final bool bold;
  final int fontSize;
  final String primaryColor;
  final String highlightColor;
  final String outlineColor;
  final int outline;
  final int shadow;
  final String animation;
  final bool uppercase;
  final int maxChars;
  final int maxLines;

  _PresetConfig({
    required this.fontFamily,
    required this.bold,
    required this.fontSize,
    required this.primaryColor,
    required this.highlightColor,
    required this.outlineColor,
    required this.outline,
    required this.shadow,
    required this.animation,
    required this.uppercase,
    required this.maxChars,
    required this.maxLines,
  });
}
