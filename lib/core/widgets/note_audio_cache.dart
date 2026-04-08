import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// On-disk cache for note audio attachments.
///
/// Cached files live under `<applicationSupportDirectory>/note_audio_cache/`
/// and are keyed by `attachmentId + createdAt`. The filesystem IS the index:
/// - Hit detection: `existsSync` on the deterministic path
/// - LRU-ish eviction: sort by mtime, delete oldest until under the soft cap
///
/// Unlike the previous scheme (which wrote to `getTemporaryDirectory()` and
/// deleted on dispose), files here persist across note opens so replaying a
/// note doesn't trigger a fresh download.
class NoteAudioCache {
  /// Soft ceiling — once total cache size exceeds this, we evict.
  static const int _maxBytes = 500 * 1024 * 1024; // 500 MB

  /// Target size after an eviction pass.
  static const int _targetBytes = 400 * 1024 * 1024; // 400 MB

  static const String _subdir = 'note_audio_cache';

  /// Return (and create) the cache directory.
  static Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_subdir');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Build a filesystem-safe cache filename from the attachment identity.
  ///
  /// Only the tuple (attachmentId, createdAt) is load-bearing — if the server
  /// regenerates an audio attachment, `createdAt` will change and we'll miss
  /// the old cache entry and fetch fresh.
  static String _buildFilename({
    required String attachmentId,
    required String createdAt,
    required String ext,
  }) {
    final safeId = attachmentId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeCreated = createdAt.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'att_${safeId}_$safeCreated.$ext';
  }

  /// Look up a cached file by attachment identity. Returns null on miss.
  ///
  /// Synchronous-fast: one `existsSync`, no stat beyond that. On hit, touches
  /// the file's mtime so LRU eviction reflects recent playback.
  static Future<String?> lookup({
    required String attachmentId,
    required String createdAt,
    required String ext,
  }) async {
    try {
      final dir = await _cacheDir();
      final path =
          '${dir.path}/${_buildFilename(attachmentId: attachmentId, createdAt: createdAt, ext: ext)}';
      final file = File(path);
      if (file.existsSync()) {
        // Touch mtime so this file counts as recently used for LRU eviction.
        try {
          file.setLastModifiedSync(DateTime.now());
        } catch (_) {
          // Non-fatal — fall through and return the hit regardless.
        }
        return path;
      }
      return null;
    } catch (e) {
      debugPrint('NoteAudioCache.lookup error: $e');
      return null;
    }
  }

  /// Write bytes into the cache and return the absolute path. Also kicks off
  /// a best-effort eviction pass if the cache has grown past the soft cap.
  static Future<String?> write({
    required String attachmentId,
    required String createdAt,
    required String ext,
    required List<int> bytes,
  }) async {
    try {
      final dir = await _cacheDir();
      final path =
          '${dir.path}/${_buildFilename(attachmentId: attachmentId, createdAt: createdAt, ext: ext)}';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      // Best-effort eviction — don't let a cleanup failure break playback.
      try {
        await _evictIfNeeded(dir);
      } catch (e) {
        debugPrint('NoteAudioCache eviction error: $e');
      }
      return path;
    } catch (e) {
      debugPrint('NoteAudioCache.write error: $e');
      return null;
    }
  }

  /// If the cache directory exceeds [_maxBytes], delete oldest-mtime files
  /// until it's under [_targetBytes]. Async so a large cache (hundreds of
  /// files) doesn't jank the UI thread at write time. Best-effort: per-file
  /// failures are caught and logged, never abort the pass.
  static Future<void> _evictIfNeeded(Directory dir) async {
    final raw = await dir.list(followLinks: false).toList();
    final entries = <_CacheEntry>[];
    for (final f in raw.whereType<File>()) {
      try {
        final stat = await f.stat();
        entries.add(
          _CacheEntry(file: f, size: stat.size, mtime: stat.modified),
        );
      } catch (e) {
        debugPrint('NoteAudioCache evict stat failed: $e');
      }
    }

    var total = entries.fold<int>(0, (sum, e) => sum + e.size);
    if (total <= _maxBytes) return;

    // Oldest first.
    entries.sort((a, b) => a.mtime.compareTo(b.mtime));

    for (final entry in entries) {
      if (total <= _targetBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (e) {
        debugPrint('NoteAudioCache evict delete failed: $e');
      }
    }
  }
}

class _CacheEntry {
  final File file;
  final int size;
  final DateTime mtime;

  _CacheEntry({required this.file, required this.size, required this.mtime});
}
