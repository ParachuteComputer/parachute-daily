import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:parachute/core/providers/backend_health_provider.dart'
    show ttsApiServiceProvider;
import 'package:parachute/core/theme/design_tokens.dart';

enum _TtsPhase { idle, synthesizing, playing }

/// Icon button that synthesizes speech via the TTS service and plays it.
///
/// In idle state, renders as a simple icon button in the AppBar.
/// When playing, shows a full inline player with pause/resume, scrubber,
/// and time display below the trigger button area.
class ReadAloudButton extends ConsumerStatefulWidget {
  final String text;

  const ReadAloudButton({super.key, required this.text});

  @override
  ConsumerState<ReadAloudButton> createState() => _ReadAloudButtonState();
}

class _ReadAloudButtonState extends ConsumerState<ReadAloudButton> {
  _TtsPhase _phase = _TtsPhase.idle;
  AudioPlayer? _player;
  String? _tempPath;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  @override
  void dispose() {
    _cancelSubs();
    _cleanup();
    super.dispose();
  }

  void _cancelSubs() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _positionSub = null;
    _durationSub = null;
    _stateSub = null;
  }

  Future<void> _cleanup() async {
    _cancelSubs();
    await _player?.stop();
    _player?.dispose();
    _player = null;
    if (_tempPath != null) {
      try {
        await File(_tempPath!).delete();
      } catch (_) {}
      _tempPath = null;
    }
    _position = Duration.zero;
    _duration = Duration.zero;
    _playing = false;
  }

  Future<void> _synthesizeAndPlay() async {
    if (_phase == _TtsPhase.synthesizing) return;

    // If already playing, stop and reset
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

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.ogg');
      await file.writeAsBytes(bytes);
      _tempPath = file.path;

      _player = AudioPlayer();
      await _player!.setFilePath(file.path);

      if (!mounted) {
        await _cleanup();
        return;
      }

      // Wire up streams
      _positionSub = _player!.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _durationSub = _player!.durationStream.listen((d) {
        if (mounted && d != null) setState(() => _duration = d);
      });
      _stateSub = _player!.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() => _playing = s.playing);
        if (s.processingState == ProcessingState.completed) {
          _player!.pause();
          _player!.seek(Duration.zero);
          setState(() => _playing = false);
        }
      });

      setState(() => _phase = _TtsPhase.playing);
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

  Future<void> _togglePlayPause() async {
    if (_player == null) return;
    if (_playing) {
      await _player!.pause();
    } else {
      await _player!.play();
    }
  }

  Future<void> _seek(double ms) async {
    await _player?.seek(Duration(milliseconds: ms.toInt()));
  }

  Future<void> _stop() async {
    await _cleanup();
    if (mounted) setState(() => _phase = _TtsPhase.idle);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ttsService = ref.watch(ttsApiServiceProvider);
    if (ttsService == null) return const SizedBox.shrink();

    switch (_phase) {
      case _TtsPhase.idle:
        return IconButton(
          icon: const Icon(Icons.volume_up_outlined),
          onPressed: _synthesizeAndPlay,
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
        return _buildPlayer(context);
    }
  }

  Widget _buildPlayer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final curMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/pause
          GestureDetector(
            onTap: _togglePlayPause,
            child: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: BrandColors.turquoise,
              size: 28,
            ),
          ),
          const SizedBox(width: 4),
          // Time + scrubber
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 16,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: BrandColors.turquoise,
                      inactiveTrackColor: BrandColors.turquoise.withValues(alpha: 0.2),
                      thumbColor: BrandColors.turquoise,
                    ),
                    child: Slider(
                      value: curMs,
                      max: maxMs,
                      onChanged: _duration.inMilliseconds > 0 ? _seek : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(_position),
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                        ),
                      ),
                      Text(
                        _fmt(_duration),
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Stop/close
          GestureDetector(
            onTap: _stop,
            child: Icon(
              Icons.close,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

/// Standalone function for triggering read-aloud from non-widget contexts
/// (e.g., popup menu callbacks). Shows a persistent player bar via SnackBar.
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
      // Show persistent player SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _SnackBarPlayer(player: player),
          duration: const Duration(minutes: 30),
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        player.pause();
        player.seek(Duration.zero);
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

/// Stateful player widget embedded in a SnackBar for the long-press context.
class _SnackBarPlayer extends StatefulWidget {
  final AudioPlayer player;
  const _SnackBarPlayer({required this.player});

  @override
  State<_SnackBarPlayer> createState() => _SnackBarPlayerState();
}

class _SnackBarPlayerState extends State<_SnackBarPlayer> {
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _posSub = widget.player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = widget.player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _stateSub = widget.player.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s.playing);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    widget.player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final curMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BrandColors.nightSurfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: BrandColors.turquoise.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (_playing) {
                    widget.player.pause();
                  } else {
                    widget.player.play();
                  }
                },
                child: Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: BrandColors.turquoise,
                  size: 32,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: BrandColors.turquoise,
                    inactiveTrackColor: BrandColors.turquoise.withValues(alpha: 0.2),
                    thumbColor: BrandColors.turquoise,
                  ),
                  child: Slider(
                    value: curMs,
                    max: maxMs,
                    onChanged: _duration.inMilliseconds > 0
                        ? (v) => widget.player.seek(Duration(milliseconds: v.toInt()))
                        : null,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  widget.player.stop();
                  ScaffoldMessenger.of(context).clearSnackBars();
                },
                child: const Icon(
                  Icons.close,
                  color: BrandColors.driftwood,
                  size: 20,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 40, right: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(_position),
                  style: const TextStyle(fontSize: 11, color: BrandColors.driftwood),
                ),
                const Text(
                  'Read aloud',
                  style: TextStyle(fontSize: 11, color: BrandColors.driftwood),
                ),
                Text(
                  _fmt(_duration),
                  style: const TextStyle(fontSize: 11, color: BrandColors.driftwood),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
