import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/models/clip_options.dart';
import '../../services/pipeline_coordinator.dart';
import 'processing_screen.dart';

class HomePickerScreen extends StatefulWidget {
  const HomePickerScreen({super.key});

  @override
  State<HomePickerScreen> createState() => _HomePickerScreenState();
}

class _HomePickerScreenState extends State<HomePickerScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedVideo;

  int _numClips = 3;
  double? _targetDuration; // null = Auto
  AspectRatioOption _aspectRatio = AspectRatioOption.vertical916;
  CaptionStylePreset _captionStyle = CaptionStylePreset.hormozi;
  bool _enableCaptions = true;

  Future<void> _pickVideo() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _selectedVideo = File(file.path);
      });
    }
  }

  void _startGeneration() {
    if (_selectedVideo == null) return;

    final config = ClipGenerationConfig(
      numClips: _numClips,
      targetDuration: _targetDuration,
      aspectRatio: _aspectRatio,
      captionStyle: _captionStyle,
      enableCaptions: _enableCaptions,
    );

    final coordinator = context.read<PipelineCoordinator>();
    coordinator.processVideo(
      videoPath: _selectedVideo!.path,
      config: config,
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProcessingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.movie_filter_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'AutoClip Mobile',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off_rounded, size: 14, color: Colors.greenAccent),
                  SizedBox(width: 4),
                  Text("100% Offline", style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video Picker Area
            InkWell(
              onTap: _pickVideo,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2230),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedVideo != null ? const Color(0xFF6366F1) : const Color(0xFF2E344A),
                    width: 2,
                  ),
                ),
                child: _selectedVideo == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF282D42),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.video_library_rounded, size: 36, color: Color(0xFF818CF8)),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Select Video from Gallery",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Podcasts, interviews, tutorials (MP4, MOV)",
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 44, color: Colors.greenAccent),
                          const SizedBox(height: 8),
                          Text(
                            _selectedVideo!.path.split(Platform.pathSeparator).last,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _pickVideo,
                            child: const Text("Change Video", style: TextStyle(color: Color(0xFF818CF8))),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // Settings Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF181C28),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF282D42)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CLIP SETTINGS", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 16),

                  // Number of clips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Number of clips:", style: TextStyle(color: Colors.white, fontSize: 15)),
                      Text("$_numClips clips", style: const TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  Slider(
                    value: _numClips.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    activeColor: const Color(0xFF6366F1),
                    inactiveColor: const Color(0xFF282D42),
                    onChanged: (v) => setState(() => _numClips = v.toInt()),
                  ),
                  const Divider(color: Color(0xFF282D42), height: 24),

                  // Clip Duration Preset
                  const Text("Target Duration:", style: TextStyle(color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildDurationChip("Auto (30-50s)", null),
                      const SizedBox(width: 8),
                      _buildDurationChip("30s", 30.0),
                      const SizedBox(width: 8),
                      _buildDurationChip("45s", 45.0),
                      const SizedBox(width: 8),
                      _buildDurationChip("60s", 60.0),
                    ],
                  ),
                  const Divider(color: Color(0xFF282D42), height: 24),

                  // Caption Style
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Burn Captions:", style: TextStyle(color: Colors.white, fontSize: 15)),
                      Switch(
                        value: _enableCaptions,
                        activeColor: const Color(0xFF6366F1),
                        onChanged: (v) => setState(() => _enableCaptions = v),
                      ),
                    ],
                  ),

                  if (_enableCaptions) ...[
                    const SizedBox(height: 8),
                    const Text("Caption Style Preset:", style: TextStyle(color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildStyleChip("Hormozi (Yellow)", CaptionStylePreset.hormozi),
                        _buildStyleChip("Beast (Emerald)", CaptionStylePreset.beast),
                        _buildStyleChip("Neon Cyan", CaptionStylePreset.neonGlow),
                        _buildStyleChip("Karaoke Bounce", CaptionStylePreset.karaoke),
                        _buildStyleChip("Clean White", CaptionStylePreset.cleanWhite),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Action Button
            ElevatedButton(
              onPressed: _selectedVideo == null ? null : _startGeneration,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor: const Color(0xFF282D42),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    "Generate Viral Shorts",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip(String label, double? duration) {
    final bool isSelected = _targetDuration == duration;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _targetDuration = duration),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF232838),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? Colors.transparent : const Color(0xFF2E344A)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyleChip(String label, CaptionStylePreset preset) {
    final bool isSelected = _captionStyle == preset;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF6366F1),
      backgroundColor: const Color(0xFF232838),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (_) => setState(() => _captionStyle = preset),
    );
  }
}
