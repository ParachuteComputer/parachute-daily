import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// File-based cache for TTS audio, keyed by note ID + content hash.
///
/// Audio files are stored in the app's persistent support directory under
/// `tts_cache/`. If the note content changes, the hash changes and a fresh
/// synthesis is required.
class TtsAudioCache {
  static const _cacheDir = 'tts_cache';

  /// Returns the cached audio file path if it exists, or null.
  Future<String?> get(String noteId, String content) async {
    final path = await _filePath(noteId, content);
    final file = File(path);
    if (await file.exists()) {
      return path;
    }
    return null;
  }

  /// Saves audio bytes to the cache and returns the file path.
  Future<String> put(String noteId, String content, Uint8List bytes) async {
    final path = await _filePath(noteId, content);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    debugPrint('[TtsCache] Cached ${bytes.length} bytes for note $noteId');
    return path;
  }

  /// Build a deterministic file path: `<appSupport>/tts_cache/<noteId>_<hash>.ogg`
  Future<String> _filePath(String noteId, String content) async {
    final dir = await getApplicationSupportDirectory();
    final hash = _contentHash(content);
    // Sanitize noteId for filesystem safety
    final safeId = noteId.replaceAll(RegExp(r'[^\w-]'), '_');
    return '${dir.path}/$_cacheDir/${safeId}_$hash.ogg';
  }

  /// SHA-256 of the content, truncated to 12 hex chars.
  static String _contentHash(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 12);
  }
}
