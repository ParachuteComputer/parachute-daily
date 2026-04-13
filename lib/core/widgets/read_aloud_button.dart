import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:parachute/core/providers/backend_health_provider.dart'
    show ttsApiServiceProvider;
import 'package:parachute/core/theme/design_tokens.dart';

/// Icon button that synthesizes speech via the TTS service and plays it.
///
/// Audio is ephemeral — written to a temp file, played, then deleted.
/// Shows a loading spinner while synthesizing.
class ReadAloudButton extends ConsumerStatefulWidget {
  final String text;

  const ReadAloudButton({super.key, required this.text});

  @override
  ConsumerState<ReadAloudButton> createState() => _ReadAloudButtonState();
}

enum _TtsPhase { idle, synthesizing, playing }

class _ReadAloudButtonState extends ConsumerState<ReadAloudButton> {
  _TtsPhase _phase = _TtsPhase.idle;
  AudioPlayer? _player;
  String? _tempPath;

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  Future<void> _cleanup() async {
    await _player?.stop();
    _player?.dispose();
    _player = null;
    if (_tempPath != null) {
      try {
        await File(_tempPath!).delete();
      } catch (_) {}
      _tempPath = null;
    }
  }

  Future<void> _readAloud() async {
    // If already playing, stop
    if (_phase == _TtsPhase.playing) {
      await _cleanup();
      if (mounted) setState(() => _phase = _TtsPhase.idle);
      return;
    }

    final ttsService = ref.read(ttsApiServiceProvider);
    if (ttsService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('TTS service not configured — check Settings'),
            backgroundColor: BrandColors.warning,
          ),
        );
      }
      return;
    }

    setState(() => _phase = _TtsPhase.synthesizing);

    try {
      final bytes = await ttsService.synthesize(widget.text);

      // Write to temp file
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.ogg');
      await file.writeAsBytes(bytes);
      _tempPath = file.path;

      // Play
      _player = AudioPlayer();
      await _player!.setFilePath(file.path);

      if (!mounted) {
        await _cleanup();
        return;
      }
      setState(() => _phase = _TtsPhase.playing);

      _player!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _cleanup();
          if (mounted) setState(() => _phase = _TtsPhase.idle);
        }
      });

      await _player!.play();
    } catch (e) {
      debugPrint('[ReadAloud] TTS error: $e');
      await _cleanup();
      if (mounted) {
        setState(() => _phase = _TtsPhase.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Read aloud failed: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ttsService = ref.watch(ttsApiServiceProvider);

    // Don't show the button if TTS isn't configured
    if (ttsService == null) return const SizedBox.shrink();

    switch (_phase) {
      case _TtsPhase.idle:
        return IconButton(
          icon: const Icon(Icons.volume_up_outlined),
          onPressed: _readAloud,
          tooltip: 'Read aloud',
        );
      case _TtsPhase.synthesizing:
        return const SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _TtsPhase.playing:
        return IconButton(
          icon: const Icon(Icons.stop_circle_outlined),
          onPressed: _readAloud,
          tooltip: 'Stop',
        );
    }
  }
}

/// Standalone function for triggering read-aloud from non-widget contexts
/// (e.g., popup menu callbacks). Shows a snackbar with progress.
Future<void> readAloudFromContext({
  required BuildContext context,
  required WidgetRef ref,
  required String text,
}) async {
  final ttsService = ref.read(ttsApiServiceProvider);
  if (ttsService == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('TTS service not configured — check Settings'),
        backgroundColor: BrandColors.warning,
      ),
    );
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(BrandColors.softWhite),
            ),
          ),
          const SizedBox(width: 12),
          const Text('Synthesizing speech...'),
        ],
      ),
      duration: const Duration(seconds: 30),
    ),
  );

  try {
    final bytes = await ttsService.synthesize(text);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.ogg');
    await file.writeAsBytes(bytes);

    final player = AudioPlayer();
    await player.setFilePath(file.path);

    if (context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        player.dispose();
        file.delete().catchError((_) => file);
      }
    });

    await player.play();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Read aloud failed: $e'),
          backgroundColor: BrandColors.error,
        ),
      );
    }
  }
}
