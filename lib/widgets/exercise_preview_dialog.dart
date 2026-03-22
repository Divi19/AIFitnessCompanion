import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// Maps each exercise key to its YouTube video ID and display info.
const Map<String, Map<String, String>> exerciseInfo = {
  'squat': {
    'videoId': 'P-yaD24bUE8',
    'name': 'Squat',
    'tip': 'Keep your chest up and knees behind your toes.',
  },
  'sit_up': {
    'videoId': 'jDwoBqPH0jk',
    'name': 'Sit Up',
    'tip': 'Engage your core and avoid pulling your neck.',
  },
  'plank': {
    'videoId': 'mwlp75MS6Rg',
    'name': 'Plank',
    'tip': 'Keep your hips level and breathe steadily.',
  },
  'pushup': {
    'videoId': 'WDIpL0pjun0',
    'name': 'Push Up',
    'tip': 'Keep your body in a straight line from head to toe.',
  },
  'lunge_right': {
    'videoId': 'NcUF3GJfh2Y',
    'name': 'Right Lunge',
    'tip': 'Keep your front knee directly above your ankle.',
  },
  'lunge_left': {
    'videoId': 'NcUF3GJfh2Y',
    'name': 'Left Lunge',
    'tip': 'Keep your front knee directly above your ankle.',
  },
  'glute_bridge': {
    'videoId': 'L9KZfxT654Y',
    'name': 'Glute Bridge',
    'tip': 'Squeeze your glutes at the top of the movement.',
  },
  'jumping_jack': {
    'videoId': 'uLVt6u15L98',
    'name': 'Jumping Jack',
    'tip': 'Land softly and keep a steady rhythm.',
  },
  'bicep_curl': {
    'videoId': '6DeLZ6cbgWQ',
    'name': 'Bicep Curl',
    'tip': 'Keep your elbows close to your torso.',
  },
};

/// Shows the exercise preview popup with a YouTube video.
/// Closes automatically when the video ends, or when the user
/// taps the X button. The workout only starts after this closes.
Future<void> showExercisePreview(
  BuildContext context,
  String exerciseKey,
) async {
  final info = exerciseInfo[exerciseKey];
  if (info == null) return;

  await showDialog(
    context: context,
    barrierDismissible: false, // Force user to use X button or finish video
    builder: (_) => _ExercisePreviewDialog(info: info),
  );
}

class _ExercisePreviewDialog extends StatefulWidget {
  final Map<String, String> info;

  const _ExercisePreviewDialog({required this.info});

  @override
  State<_ExercisePreviewDialog> createState() => _ExercisePreviewDialogState();
}

class _ExercisePreviewDialogState extends State<_ExercisePreviewDialog> {
  late YoutubePlayerController _controller;
  bool _videoEnded = false;

  @override
  void initState() {
    super.initState();

    _controller = YoutubePlayerController(
      initialVideoId: widget.info['videoId']!,
      flags: const YoutubePlayerFlags(
        autoPlay: true, // Start playing immediately on open
        mute: false, // Audio on by default
        disableDragSeek: false,
        loop: false, // Don't loop - close when video ends
        enableCaption: false,
        controlsVisibleAtStart: true,
      ),
    );

    // Listen for video ending — auto-close the dialog when video finishes
    _controller.addListener(_onPlayerStateChanged);
  }

  void _onPlayerStateChanged() {
    if (!mounted) return;

    // PlayerState.ended fires when the video reaches the end
    if (_controller.value.playerState == PlayerState.ended && !_videoEnded) {
      _videoEnded = true;
      // Small delay so user sees the video reach the end before dismissing
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onPlayerStateChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              children: [
                // Exercise name
                Text(
                  widget.info['name']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                // X close button - always visible
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── YouTube Player ──────────────────────────────────────────
          // YoutubePlayer must not be inside a scrollable widget
          ClipRRect(
            borderRadius: BorderRadius.zero,
            child: YoutubePlayer(
              controller: _controller,
              showVideoProgressIndicator: true,
              progressIndicatorColor: const Color(0xFFB9FF2B),
              progressColors: const ProgressBarColors(
                playedColor: Color(0xFFB9FF2B),
                handleColor: Color(0xFFB9FF2B),
                bufferedColor: Colors.white24,
                backgroundColor: Colors.black26,
              ),
            ),
          ),

          // ── Tip banner ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFB9FF2B).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFB9FF2B).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tips_and_updates,
                    color: Color(0xFFB9FF2B),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.info['tip']!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Let's Go Button ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB9FF2B),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_run, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Let's get on the move!",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
