# AutoClip Mobile — 100% Offline AI Video Clipper

AutoClip Mobile is a standalone native mobile application (Android & iOS) that converts landscape videos into viral 9:16 vertical shorts (Reels, TikTok, YouTube Shorts) with animated captions and smart highlight detection.

**Key Feature**: **0 API keys required**. All speech recognition, highlight selection, subtitle styling, and video rendering run **locally on-device**.

---

## 🏗 Architecture

```
[Camera Roll / Gallery]
           │
           ▼
[MobileFFmpegClipper.extractAudioWav] ──> 16kHz Mono WAV
           │
           ▼
[MobileWhisperEngine (whisper.cpp)]   ──> On-device Speech-to-Text (Word timestamps)
           │
           ▼
[ClipSelector (Dart Heuristics)]      ──> Hooks, payoffs, pacing & viral scoring
           │
           ▼
[AssCaptionGenerator]                 ──> Word-level ASS subtitles (Hormozi, Beast, etc.)
           │
           ▼
[MobileFFmpegClipper (libass + crop)]  ──> Rendered 9:16 Shorts with burned captions
           │
           ▼
[Gal / Photo Gallery]                 ──> Direct save to Camera Roll
```

---

## 📁 Project Structure

```
autoclip_mobile/
├── lib/
│   ├── main.dart                             # App entrypoint & theme setup
│   ├── core/
│   │   └── models/
│   │       ├── transcript.dart               # Transcript, segments, and word timestamps
│   │       ├── clip_candidate.dart           # Selected clip window & metadata
│   │       └── clip_options.dart             # Aspect ratio, duration, and style presets
│   ├── engine/
│   │   ├── selector/
│   │   │   └── clip_selector.dart            # Ported 1:1 local heuristic scoring engine
│   │   ├── captions/
│   │   │   └── ass_caption_generator.dart    # Subtitle generator with ASS styles
│   │   ├── whisper/
│   │   │   └── mobile_whisper_engine.dart    # whisper.cpp on-device STT integration
│   │   └── clipper/
│   │       └── mobile_ffmpeg_clipper.dart    # FFmpeg 9:16 cropping & subtitle burn-in
│   ├── services/
│   │   └── pipeline_coordinator.dart         # Background pipeline coordinator & progress
│   └── ui/
│       └── screens/
│           ├── home_picker_screen.dart       # Video picker & generation settings
│           ├── processing_screen.dart        # Live multi-stage progress indicator
│           └── clips_library_screen.dart     # 9:16 video player & camera roll export
├── assets/
│   ├── models/                               # ggml-tiny.bin / ggml-base.bin (Offline Whisper)
│   └── fonts/                                # Montserrat, Anton, Roboto, Bebas Neue
└── pubspec.yaml                              # Dependencies: ffmpeg_kit, whisper_flutter, gal
```

---

## ⚡ How It Works Without Any API Key

1. **Speech-to-Text (`MobileWhisperEngine`)**:
   Runs quantized GGUF Whisper models (`ggml-tiny.bin` ~75MB or `ggml-base.bin` ~140MB) using `whisper.cpp` via native ARM NEON / GPU acceleration.
2. **AI Highlight Selection (`ClipSelector`)**:
   Ported directly from AutoClip's Python heuristics engine. Analyzes conversational cadence, hook opening triggers (`"why"`, `"did you know"`, `"the real secret"`), penalizes filler words (`"um"`, `"basically"`), and snaps cuts to natural topic boundaries.
3. **Burned Captions (`AssCaptionGenerator` + `MobileFFmpegClipper`)**:
   Creates standard `.ass` subtitle files formatted for TikTok/Reels (Hormozi yellow highlight, Beast emerald, neon cyan) and renders them into the video frame using FFmpeg's `libass` filter.

---

## 🚀 Quick Start & Build

### 1. Requirements
- Flutter SDK `>= 3.0.0`
- Android SDK (API 26+) or Xcode for iOS

### 2. Download Offline Whisper Model (One-Time)
Place the quantized GGUF model into `assets/models/`:
```bash
# Download whisper tiny (~75 MB)
curl -L -o assets/models/ggml-tiny.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin
```

### 3. Run on Device / Simulator
```bash
flutter pub get
flutter run
```

### 4. Build Release APK (Android)
```bash
flutter build apk --release
```
The APK will be generated at `build/app/outputs/flutter-apk/app-release.apk`.
