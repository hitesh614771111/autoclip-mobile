import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../core/models/clip_candidate.dart';
import '../../services/pipeline_coordinator.dart';

class ClipsLibraryScreen extends StatefulWidget {
  const ClipsLibraryScreen({super.key});

  @override
  State<ClipsLibraryScreen> createState() => _ClipsLibraryScreenState();
}

class _ClipsLibraryScreenState extends State<ClipsLibraryScreen> {
  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final clips = context.read<PipelineCoordinator>().generatedClips;
    if (clips.isNotEmpty) {
      _initPlayer(clips.first.videoPath);
    }
  }

  Future<void> _initPlayer(String path) async {
    await _videoController?.dispose();
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    controller.setLooping(true);
    controller.play();

    if (mounted) {
      setState(() {
        _videoController = controller;
        _isPlaying = true;
      });
    }
  }

  Future<void> _saveToGallery(String videoPath) async {
    setState(() => _isSaving = true);
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }
      await Gal.putVideo(videoPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text("Saved short to Photos / Camera Roll! 🎉"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text("Failed to save to gallery: $e"),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clips = context.watch<PipelineCoordinator>().generatedClips;

    if (clips.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        appBar: AppBar(title: const Text("Your Clips")),
        body: const Center(
          child: Text("No clips generated yet.", style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    final currentClip = clips[_currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Clip ${_currentIndex + 1} of ${clips.length}",
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
      body: Column(
        children: [
          // 9:16 Video Player Container
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF282D42)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_videoController != null && _videoController!.value.isInitialized)
                        GestureDetector(
                          onTap: () {
                            if (_videoController!.value.isPlaying) {
                              _videoController!.pause();
                              setState(() => _isPlaying = false);
                            } else {
                              _videoController!.play();
                              setState(() => _isPlaying = true);
                            }
                          },
                          child: VideoPlayer(_videoController!),
                        )
                      else
                        const CircularProgressIndicator(color: Color(0xFF6366F1)),

                      if (!_isPlaying && _videoController != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, size: 48, color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Title & Duration
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Text(
                  currentClip.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "${currentClip.duration.toStringAsFixed(1)}s • Score: ${currentClip.score.toStringAsFixed(1)}",
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Thumbnails / Carousel bar
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: clips.length,
              itemBuilder: (context, idx) {
                final isSelected = idx == _currentIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() => _currentIndex = idx);
                    _initPlayer(clips[idx].videoPath);
                  },
                  child: Container(
                    width: 45,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1E2230),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Colors.white : const Color(0xFF2E344A),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "#${idx + 1}",
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white60,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Save / Share Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : () => _saveToGallery(currentClip.videoPath),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_rounded, color: Colors.white),
                    label: Text(
                      _isSaving ? "Saving..." : "Save to Camera Roll",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
