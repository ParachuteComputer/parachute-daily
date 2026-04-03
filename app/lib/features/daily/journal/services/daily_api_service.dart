import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:parachute/core/models/thing.dart';
import '../models/journal_entry.dart';

/// Raw search result from the server API.
class ApiSearchResult {
  final String id;
  final String createdAt;
  final String content;
  final String snippet;
  final int matchCount;
  final Map<String, dynamic> metadata;

  const ApiSearchResult({
    required this.id,
    required this.createdAt,
    required this.content,
    required this.snippet,
    required this.matchCount,
    required this.metadata,
  });

  factory ApiSearchResult.fromJson(Map<String, dynamic> json) {
    return ApiSearchResult(
      id: json['id'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? json['createdAt'] as String? ?? '',
      content: json['content'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      matchCount: (json['match_count'] as num?)?.toInt() ?? 0,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }
}

/// HTTP client for the v3 Daily API server.
///
/// Translates between the app's JournalEntry models and the v3 Notes/Tags API.
/// All endpoints are under /api/ on the server at [baseUrl].
///
/// Key mappings:
///   Journal entries = Notes tagged "daily"
///   Voice entries   = Notes tagged "daily" + "voice"
///   Audio files     = Attachments on notes
class DailyApiService {
  final String baseUrl;
  final String? apiKey;
  final http.Client _client;

  /// Optional callback for fast-fail / fast-recover health updates.
  void Function(bool reachable)? onReachabilityChanged;

  static const _timeout = Duration(seconds: 15);

  DailyApiService({required this.baseUrl, this.apiKey, this.onReachabilityChanged})
    : _client = http.Client();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'User-Agent': 'Parachute-Daily/1.0',
    if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };

  // ===========================================================================
  // Journal Entry CRUD — backed by Notes tagged "daily"
  // ===========================================================================

  /// Fetch notes for a specific date (YYYY-MM-DD).
  ///
  /// Returns `null` on network error — callers should fall back to cache.
  /// Returns `[]` when the server responds with no notes — authoritative empty.
  Future<List<Note>?> getNotes({required String date}) async {
    final nextDate = _nextDate(date);
    final uri = Uri.parse('$baseUrl/api/notes').replace(
      queryParameters: {
        'tag': 'daily',
        'date_from': '${date}T00:00:00.000Z',
        'date_to': '${nextDate}T00:00:00.000Z',
        'limit': '100',
      },
    );
    debugPrint('[DailyApiService] GET $uri');
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[DailyApiService] GET notes ${response.statusCode}');
        return null;
      }

      onReachabilityChanged?.call(true);
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((json) => Note.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[DailyApiService] getNotes error (offline?): $e');
      onReachabilityChanged?.call(false);
      return null;
    }
  }

  /// Create a new note on the server.
  Future<Note?> createNote({
    required String content,
    List<String> tags = const ['daily'],
  }) async {
    final uri = Uri.parse('$baseUrl/api/notes');
    debugPrint('[DailyApiService] POST $uri');
    try {
      final body = jsonEncode({
        'content': content,
        'tags': tags,
      });
      final response = await _client
          .post(uri, headers: _headers, body: body)
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[DailyApiService] POST notes ${response.statusCode}');
        return null;
      }

      onReachabilityChanged?.call(true);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return Note.fromJson(decoded);
    } catch (e) {
      debugPrint('[DailyApiService] createNote error: $e');
      onReachabilityChanged?.call(false);
      return null;
    }
  }

  /// Update content of an existing note.
  Future<Note?> updateNote(
    String noteId, {
    String? content,
  }) async {
    final uri = Uri.parse('$baseUrl/api/notes/$noteId');
    debugPrint('[DailyApiService] PATCH $uri');
    try {
      final patchBody = <String, dynamic>{};
      if (content != null) patchBody['content'] = content;

      final response = await _client
          .patch(uri, headers: _headers, body: jsonEncode(patchBody))
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[DailyApiService] PATCH notes/$noteId ${response.statusCode}');
        return null;
      }

      onReachabilityChanged?.call(true);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return Note.fromJson(decoded);
    } catch (e) {
      debugPrint('[DailyApiService] updateNote error: $e');
      onReachabilityChanged?.call(false);
      return null;
    }
  }

  /// Delete a note. Returns true on success (including 404 — already gone).
  Future<bool> deleteNote(String noteId) async {
    final uri = Uri.parse('$baseUrl/api/notes/$noteId');
    debugPrint('[DailyApiService] DELETE $uri');
    try {
      final response = await _client
          .delete(uri, headers: _headers)
          .timeout(_timeout);

      if (response.statusCode == 404 ||
          response.statusCode == 200 ||
          (response.statusCode >= 200 && response.statusCode < 300)) {
        onReachabilityChanged?.call(true);
        return true;
      }
      debugPrint('[DailyApiService] DELETE notes/$noteId ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[DailyApiService] deleteNote error: $e');
      onReachabilityChanged?.call(false);
      return false;
    }
  }

  // ===========================================================================
  // Audio & Voice
  // ===========================================================================

  /// Upload an audio file to the server.
  Future<String?> uploadAudio(File audioFile, {String? date}) async {
    final uri = Uri.parse('$baseUrl/api/storage/upload');
    debugPrint('[DailyApiService] POST $uri (audio upload)');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));
      if (apiKey != null && apiKey!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $apiKey';
      }
      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      if (streamed.statusCode == 201) {
        final body = jsonDecode(await streamed.stream.bytesToString())
            as Map<String, dynamic>;
        return body['path'] as String?;
      }
      debugPrint('[DailyApiService] uploadAudio ${streamed.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[DailyApiService] uploadAudio error: $e');
      return null;
    }
  }

  /// Upload audio and create a voice note with attachment.
  Future<Note?> uploadVoiceNote({
    required File audioFile,
    required int durationSeconds,
    String? date,
    String? replaceNoteId,
  }) async {
    // Upload audio first
    final audioPath = await uploadAudio(audioFile, date: date);
    if (audioPath == null) return null;

    // If replacing, delete old note
    if (replaceNoteId != null) {
      await deleteNote(replaceNoteId);
    }

    // Create a note tagged daily + voice
    final note = await createNote(
      content: '',
      tags: ['daily', 'voice'],
    );

    // Attach the audio file to the note
    if (note != null && audioPath.isNotEmpty) {
      await _addAttachment(note.id, audioPath, 'audio/wav');
    }

    return note;
  }

  /// Add an attachment to a note.
  Future<void> _addAttachment(String noteId, String path, String mimeType) async {
    final uri = Uri.parse('$baseUrl/api/notes/$noteId/attachments');
    try {
      await _client.post(
        uri,
        headers: _headers,
        body: jsonEncode({'path': path, 'mime_type': mimeType}),
      ).timeout(_timeout);
    } catch (e) {
      debugPrint('[DailyApiService] addAttachment error: $e');
    }
  }

  // ===========================================================================
  // Search
  // ===========================================================================

  /// Keyword search across all daily entries.
  Future<List<ApiSearchResult>> searchEntries(
    String query, {
    int limit = 30,
  }) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse('$baseUrl/api/search').replace(
      queryParameters: {'q': query, 'tag': 'daily', 'limit': '$limit'},
    );
    debugPrint('[DailyApiService] GET $uri');
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[DailyApiService] search ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((json) => _noteToSearchResult(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[DailyApiService] searchEntries error: $e');
      return [];
    }
  }

  // ===========================================================================
  // Backward-compatible aliases (consumers not yet migrated to Note API)
  // TODO(v3-cache): Remove these once journal_screen.dart and other consumers
  // are updated to use Note-based methods directly.
  // ===========================================================================

  /// Alias for [getNotes] — returns JournalEntry for old consumers.
  Future<List<JournalEntry>?> getEntries({required String date}) async {
    final notes = await getNotes(date: date);
    if (notes == null) return null;
    final entries = <JournalEntry>[];
    for (final note in notes) {
      String? audioPath;
      if (note.isVoice) {
        audioPath = await getAudioPath(note.id);
      }
      entries.add(_noteToEntry(note, audioPath: audioPath));
    }
    return entries;
  }

  /// Alias for [createNote].
  Future<JournalEntry?> createEntry({
    required String content,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
  }) async {
    final entryType = metadata?['type'] as String? ?? 'text';
    final tags = <String>['daily'];
    if (entryType == 'voice') tags.add('voice');
    final note = await createNote(content: content, tags: tags);
    if (note == null) return null;
    return _noteToEntry(note);
  }

  /// Alias for [updateNote].
  Future<JournalEntry?> updateEntry(
    String entryId, {
    String? content,
    Map<String, dynamic>? metadata,
  }) async {
    final note = await updateNote(entryId, content: content);
    if (note == null) return null;
    return _noteToEntry(note);
  }

  /// Alias for [deleteNote].
  Future<bool> deleteEntry(String entryId) => deleteNote(entryId);

  /// Alias for [uploadVoiceNote].
  Future<JournalEntry?> uploadVoiceEntry({
    required File audioFile,
    required int durationSeconds,
    String? date,
    String? replaceEntryId,
  }) async {
    final note = await uploadVoiceNote(
      audioFile: audioFile,
      durationSeconds: durationSeconds,
      date: date,
      replaceNoteId: replaceEntryId,
    );
    if (note == null) return null;
    return _noteToEntry(note);
  }

  /// No-op — kept for backward compatibility.
  Future<bool> cleanupEntry(String entryId) async => false;

  /// No-op — kept for backward compatibility.
  Future<bool> registerApp() async => true;

  /// Alias for getNote by ID.
  Future<JournalEntry?> getEntry(String entryId) async {
    final uri = Uri.parse('$baseUrl/api/notes/$entryId');
    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return _noteToEntry(Note.fromJson(decoded));
    } catch (e) {
      debugPrint('[DailyApiService] getEntry error: $e');
      return null;
    }
  }

  static JournalEntry _noteToEntry(Note note, {String? audioPath}) {
    final isVoice = note.hasTag('voice');
    return JournalEntry(
      id: note.id,
      title: note.path ?? '',
      content: note.content,
      type: isVoice ? JournalEntryType.voice : JournalEntryType.text,
      createdAt: note.createdAt,
      audioPath: audioPath,
    );
  }

  void dispose() => _client.close();

  /// Fetch the first audio attachment path for a note.
  Future<String?> getAudioPath(String noteId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/notes/$noteId/attachments');
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        for (final att in data) {
          final map = att as Map<String, dynamic>;
          final mime = map['mimeType'] as String? ?? '';
          if (mime.startsWith('audio/')) {
            return map['path'] as String;
          }
        }
      }
    } catch (e) {
      debugPrint('[DailyApiService] getAudioPath error: $e');
    }
    return null;
  }

  static ApiSearchResult _noteToSearchResult(Map<String, dynamic> json) {
    final content = json['content'] as String? ?? '';
    return ApiSearchResult(
      id: json['id'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      content: content,
      snippet: content.length > 200 ? '${content.substring(0, 200)}...' : content,
      matchCount: 1,
      metadata: {},
    );
  }

  /// Compute the next date string for date range queries.
  static String _nextDate(String date) {
    final dt = DateTime.parse(date);
    final next = dt.add(const Duration(days: 1));
    final y = next.year.toString().padLeft(4, '0');
    final m = next.month.toString().padLeft(2, '0');
    final d = next.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
