import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/pipeline_coordinator.dart';
import 'clips_library_screen.dart';

class ProcessingScreen extends StatelessWidget {
  const ProcessingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PipelineCoordinator>(
      builder: (context, coordinator, child) {
        if (coordinator.stage == PipelineStage.completed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ClipsLibraryScreen()),
            );
          });
        }

        return WillPopScope(
          onWillPop: () async {
            if (coordinator.stage != PipelineStage.completed && coordinator.stage != PipelineStage.error) {
              final shouldCancel = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E2230),
                  title: const Text("Cancel Generation?", style: TextStyle(color: Colors.white)),
                  content: const Text(
                    "Are you sure you want to stop processing?",
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text("Keep Going"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text("Cancel", style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );

              if (shouldCancel == true) {
                coordinator.cancel();
                return true;
              }
              return false;
            }
            return true;
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF0F1117),
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: const Text(
                "Processing Shorts",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              actions: [
                if (coordinator.stage != PipelineStage.completed && coordinator.stage != PipelineStage.error)
                  TextButton(
                    onPressed: () {
                      coordinator.cancel();
                      Navigator.of(context).pop();
                    },
                    child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
                  ),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Circular Progress Indicator / Percentage
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: CircularProgressIndicator(
                            value: coordinator.overallProgress,
                            strokeWidth: 8,
                            backgroundColor: const Color(0xFF232838),
                            color: const Color(0xFF6366F1),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${(coordinator.overallProgress * 100).toInt()}%",
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              "PROGRESS",
                              style: TextStyle(fontSize: 10, color: Colors.white54, letterSpacing: 1.2),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Status message
                  Text(
                    coordinator.statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Step Stepper
                  _buildStepRow(
                    label: "1. Extract Audio Track",
                    active: coordinator.stage == PipelineStage.extractingAudio,
                    completed: coordinator.stage.index > PipelineStage.extractingAudio.index,
                  ),
                  const SizedBox(height: 14),
                  _buildStepRow(
                    label: "2. Offline Whisper Speech-to-Text",
                    active: coordinator.stage == PipelineStage.transcribing,
                    completed: coordinator.stage.index > PipelineStage.transcribing.index,
                  ),
                  const SizedBox(height: 14),
                  _buildStepRow(
                    label: "3. Analyze Hooks & Select Clips",
                    active: coordinator.stage == PipelineStage.selectingMoments,
                    completed: coordinator.stage.index > PipelineStage.selectingMoments.index,
                  ),
                  const SizedBox(height: 14),
                  _buildStepRow(
                    label: "4. Render 9:16 Video & Burn Subtitles",
                    active: coordinator.stage == PipelineStage.renderingClips,
                    completed: coordinator.stage.index > PipelineStage.renderingClips.index,
                  ),

                  if (coordinator.stage == PipelineStage.error) ...[
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withOpacity(0.4)),
                      ),
                      child: Text(
                        coordinator.errorMessage ?? "An unknown error occurred.",
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF282D42)),
                      child: const Text("Go Back"),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStepRow({required String label, required bool active, required bool completed}) {
    final Color color;
    final Widget icon;

    if (completed) {
      color = Colors.greenAccent;
      icon = const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20);
    } else if (active) {
      color = const Color(0xFF818CF8);
      icon = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)),
      );
    } else {
      color = Colors.white24;
      icon = const Icon(Icons.circle_outlined, color: Colors.white24, size: 20);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF1E2230) : const Color(0xFF141722),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? const Color(0xFF6366F1).withOpacity(0.6) : Colors.transparent),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: active || completed ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
