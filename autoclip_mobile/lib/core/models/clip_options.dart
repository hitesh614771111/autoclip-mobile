enum AspectRatioOption {
  vertical916, // 1080x1920 (TikTok, Reels, Shorts)
  square11,    // 1080x1080 (Square reel)
  landscape169 // 1920x1080 (YouTube landscape)
}

enum CaptionStylePreset {
  hormozi,   // Yellow highlight, bold uppercase, black outline
  beast,     // Emerald green highlight, bold impact font
  neonGlow,  // Purple/cyan glow effect
  karaoke,   // Word-by-word bouncing karaoke
  cleanWhite,// Minimalist white with clean drop shadow
}

class ClipGenerationConfig {
  final int numClips;
  final double? targetDuration; // null for Auto mode (30-50s)
  final AspectRatioOption aspectRatio;
  final CaptionStylePreset captionStyle;
  final bool enableCaptions;
  final bool enableFaceTracking;
  final bool removeSilence;
  final String? whisperModelTier; // 'tiny' or 'base'

  const ClipGenerationConfig({
    this.numClips = 3,
    this.targetDuration, // Auto by default
    this.aspectRatio = AspectRatioOption.vertical916,
    this.captionStyle = CaptionStylePreset.hormozi,
    this.enableCaptions = true,
    this.enableFaceTracking = true,
    this.removeSilence = true,
    this.whisperModelTier = 'tiny',
  });
}
