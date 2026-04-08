import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:parachute/core/config/app_config.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/providers/app_state_provider.dart'
    show apiKeyProvider;
import 'package:parachute/core/providers/feature_flags_provider.dart'
    show aiServerUrlProvider;
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/core/widgets/note_audio_cache.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';
import 'package:parachute/features/daily/journal/utils/journal_helpers.dart';

/// Inline audio player rendered on the note view when a note has an
/// `audio/*` attachment.
///
/// Fetches the note's attachments on first build and, if an audio attachment
/// exists, renders a mini player with:
/// - Play / pause button
/// - Scrubber with current position + total duration
/// - Playback speed control (1x, 1.25x, 1.5x, 2x)
///
/// Uses its own [AudioPlayer] instance so it doesn't conflict with the
/// app's shared `AudioService` (which is geared toward voice-memo recording /
/// single-track playback from the journal screen).
///
/// Renders nothing if:
/// - Attachment lookup fails
/// - The note has no `audio/*` attachment
/// - Server base URL or config isn't available yet
class NoteAudioPlayer extends ConsumerStatefulWidget {
  final Note note;

  const NoteAudioPlayer({super.key, required this.note});

  @override
  ConsumerState<NoteAudioPlayer> createState() => _NoteAudioPlayerState();
}

class _NoteAudioPlayerState extends ConsumerState<NoteAudioPlayer> {
  static const List<double> _speeds = [1.0, 1.25, 1.5, 2.0];

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _loading = true;
  String? _error;
  String? _audioUrl;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s.playing);
      // Auto-rewind to start when playback completes so the user can replay.
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
    });
    // Defer initial load until after first build so providers are available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    // Note: we intentionally do NOT delete the cached audio file on dispose.
    // Files live in NoteAudioCache (applicationSupportDirectory) and persist
    // across note opens so replay is instant. Eviction is handled by the
    // cache itself via an LRU-by-mtime pass at write time.
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(graphApiServiceProvider);
      final attachments = await api.getAttachments(widget.note.id);
      if (!mounted) return;

      if (attachments == null || attachments.isEmpty) {
        setState(() {
          _loading = false;
          _audioUrl = null;
        });
        return;
      }

      // Find the first audio attachment. Server may return either `mimeType`
      // (camelCase, as daily_api_service reads) or `mime_type` (snake_case).
      Map<String, dynamic>? audioAtt;
      for (final att in attachments) {
        final mime = (att['mimeType'] ?? att['mime_type']) as String? ?? '';
        if (mime.startsWith('audio/')) {
          audioAtt = att;
          break;
        }
      }

      if (audioAtt == null) {
        setState(() {
          _loading = false;
          _audioUrl = null;
        });
        return;
      }

      final relPath = audioAtt['path'] as String?;
      if (relPath == null || relPath.isEmpty) {
        setState(() {
          _loading = false;
          _audioUrl = null;
        });
        return;
      }

      final baseUrl = ref.read(aiServerUrlProvider).valueOrNull
          ?? AppConfig.defaultServerUrl;
      final apiKey = ref.read(apiKeyProvider).valueOrNull;
      final url = JournalHelpers.getAudioUrl(relPath, baseUrl);

      // Cache identity: attachmentId + createdAt. If the server regenerates
      // an audio attachment (e.g. tag-retriggered TTS hook), the createdAt
      // changes and we fetch fresh; the old file stays until LRU evicts it.
      // Fall back to URL hash if the attachment map is missing id/createdAt
      // so we still cache *something* rather than re-downloading forever.
      final attachmentId = (audioAtt['id'] ?? '').toString();
      final createdAt = (audioAtt['createdAt']
              ?? audioAtt['created_at']
              ?? '')
          .toString();
      // TODO: the `url_<hash>` + `'unknown'` fallback means that if an
      // attachment ever arrives without an `id` or `createdAt`, regenerated
      // versions of the same URL will serve stale cached bytes forever. The
      // Parachute Vault API reliably supplies both today, but if the shape
      // drifts, cache invalidation breaks silently. Reconsider if we hit it.
      final cacheKeyId = attachmentId.isNotEmpty
          ? attachmentId
          : 'url_${url.hashCode.toRadixString(36)}';
      final cacheKeyCreated = createdAt.isNotEmpty ? createdAt : 'unknown';
      final ext = _extFromUrl(url);

      // Cache hit? Skip the network entirely.
      String? localPath = await NoteAudioCache.lookup(
        attachmentId: cacheKeyId,
        createdAt: cacheKeyCreated,
        ext: ext,
      );

      // Cache miss — download the audio via Dart HTTP, write to cache,
      // then hand the local path to just_audio. Mirrors the pattern in
      // AudioService: ExoPlayer/AVPlayer HTTP clients can hit platform
      // networking restrictions (Android cleartext policy, macOS ATS)
      // and AudioSource.uri(headers:) is unreliable on iOS/macOS for
      // authenticated sources. Dart's http client bypasses all that.
      localPath ??= await _downloadAndCache(
        url: url,
        apiKey: apiKey,
        attachmentId: cacheKeyId,
        createdAt: cacheKeyCreated,
        ext: ext,
      );

      if (localPath == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _audioUrl = null;
        });
        return;
      }

      await _player.setFilePath(localPath);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _audioUrl = url;
      });
    } catch (e, st) {
      debugPrint('NoteAudioPlayer load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Download an audio URL and write it into the persistent note-audio cache.
  /// Returns the absolute cached file path, or null on failure.
  Future<String?> _downloadAndCache({
    required String url,
    required String? apiKey,
    required String attachmentId,
    required String createdAt,
    required String ext,
  }) async {
    try {
      final headers = <String, String>{};
      if (apiKey != null && apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) {
        debugPrint(
          'NoteAudioPlayer: download failed HTTP ${response.statusCode} for $url',
        );
        return null;
      }
      return await NoteAudioCache.write(
        attachmentId: attachmentId,
        createdAt: createdAt,
        ext: ext,
        bytes: response.bodyBytes,
      );
    } catch (e) {
      debugPrint('NoteAudioPlayer: download error: $e');
      return null;
    }
  }

  /// Pull a sensible file extension from the audio URL, guarding against
  /// URLs without a recognizable extension.
  static String _extFromUrl(String url) {
    final last = url.split('?').first.split('.').last;
    return last.length <= 5 ? last : 'mp3';
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seek(double ms) async {
    await _player.seek(Duration(milliseconds: ms.toInt()));
  }

  Future<void> _cycleSpeed() async {
    final idx = _speeds.indexOf(_speed);
    final next = _speeds[(idx + 1) % _speeds.length];
    await _player.setSpeed(next);
    if (mounted) setState(() => _speed = next);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // While loading OR if there's no audio, render nothing. The vast
    // majority of notes have no audio attachment — we don't want to
    // flash a "Loading audio..." placeholder on every note open.
    if (_loading || _audioUrl == null || _error != null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final curMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        border: Border.all(
          color: BrandColors.turquoise.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: BrandColors.turquoise,
                  size: 32,
                ),
                onPressed: _togglePlay,
                tooltip: _playing ? 'Pause' : 'Play',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
                    onChanged: _duration.inMilliseconds > 0 ? _seek : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _cycleSpeed,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: BrandColors.turquoise,
                ),
                child: Text(
                  _speedLabel(_speed),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 8),
            child: Row(
              children: [
                Text(
                  _fmt(_position),
                  style: TextStyle(
                    fontSize: 11,
                    color: BrandColors.driftwood,
                  ),
                ),
                const Spacer(),
                Text(
                  _fmt(_duration),
                  style: TextStyle(
                    fontSize: 11,
                    color: BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _speedLabel(double s) {
    if (s == s.roundToDouble()) return '${s.toInt()}x';
    return '${s}x';
  }
}
