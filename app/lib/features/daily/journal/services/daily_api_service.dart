import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  /// Fetch entries for a specific date (YYYY-MM-DD).
  ///
  /// Returns `null` on network error — callers should fall back to cache.
  /// Returns `[]` when the server responds with no entries — authoritative empty.
  Future<List<JournalEntry>?> getEntries({required String date}) async {
    // Query notes tagged "daily" within the date range
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
        debugPrint('[DailyApiService] GET entries ${response.statusCode}');
        return null;
      }

      onReachabilityChanged?.call(true);
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((json) => _noteToEntry(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[DailyApiService] getEntries error (offline?): $e');
      onReachabilityChanged?.call(false);
      return null;
    }
  }

  /// Create a new entry on the server.
  Future<JournalEntry?> createEntry({
    required String content,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
  }) async {
    final uri = Uri.parse('$baseUrl/api/notes');
    debugPrint('[DailyApiService] POST $uri');
    try {
      final entryType = metadata?['type'] as String? ?? 'text';

      // Build tags list
      final tags = <String>['daily'];
      if (entryType == 'voice') tags.add('voice');

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
      return _noteToEntry(decoded);
    } catch (e) {
      debugPrint('[DailyApiService] createEntry error: $e');
      onReachabilityChanged?.call(false);
      return null;
    }
  }

  /// Update content of an existing entry.
  Future<JournalEntry?> updateEntry(
    String entryId, {
    String? content,
    Map<String, dynamic>? metadata,
  }) async {
    final uri = Uri.parse('$baseUrl/api/notes/$entryId');
    debugPrint('[DailyApiService] PATCH $uri');
    try {
      final patchBody = <String, dynamic>{};
      if (content != null) patchBody['content'] = content;

      final response = await _client
          .patch(uri, headers: _headers, body: jsonEncode(patchBody))
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[DailyApiService] PATCH notes/$entryId ${response.statusCode}');
        return null;
      }

      onReachabilityChanged?.call(true);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return _noteToEntry(decoded);
    } catch (e) {
      debugPrint('[DailyApiService] updateEntry error: $e');
      onReachabilityChanged?.call(false);
      return null;
    }
  }

  /// Delete an entry. Returns true on success (including 404 — already gone).
  Future<bool> deleteEntry(String entryId) async {
    final uri = Uri.parse('$baseUrl/api/notes/$entryId');
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
      debugPrint('[DailyApiService] DELETE notes/$entryId ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[DailyApiService] deleteEntry error: $e');
      onReachabilityChanged?.call(false);
      return false;
    }
  }

  /// Get a single entry by ID.
  Future<JournalEntry?> getEntry(String entryId) async {
    final uri = Uri.parse('$baseUrl/api/notes/$entryId');
    debugPrint('[DailyApiService] GET $uri');
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[DailyApiService] GET notes/$entryId ${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return _noteToEntry(decoded);
    } catch (e) {
      debugPrint('[DailyApiService] getEntry error: $e');
      return null;
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

  /// Upload audio and create a voice entry with attachment.
  Future<JournalEntry?> uploadVoiceEntry({
    required File audioFile,
    required int durationSeconds,
    String? date,
    String? replaceEntryId,
  }) async {
    // Upload audio first
    final audioPath = await uploadAudio(audioFile, date: date);
    if (audioPath == null) return null;

    // If replacing, delete old entry
    if (replaceEntryId != null) {
      await deleteEntry(replaceEntryId);
    }

    // Create a note tagged daily + voice
    final entry = await createEntry(
      content: '',
      metadata: {'type': 'voice'},
    );

    // Attach the audio file to the note
    if (entry != null && audioPath.isNotEmpty) {
      await _addAttachment(entry.id, audioPath, 'audio/wav');
    }

    return entry;
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

  /// Trigger LLM cleanup on an existing entry's content.
  ///
  /// Not yet supported — returns false.
  Future<bool> cleanupEntry(String entryId) async {
    debugPrint('[DailyApiService] cleanupEntry: not yet supported');
    return false;
  }

  // ===========================================================================
  // Search
  // ===========================================================================

  /// Keyword search across all entries.
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
  // Registration — no longer needed in v3, tags are seeded by the server
  // ===========================================================================

  /// No-op in v3 — builtin tags are seeded automatically by the server.
  Future<bool> registerApp() async {
    debugPrint('[DailyApiService] registerApp: no-op in v3 (tags seeded by server)');
    return true;
  }

  void dispose() => _client.close();

  // ===========================================================================
  // Translation helpers — v3 Note → app models
  // ===========================================================================

  /// Convert a Note JSON (from v3 API) to a [JournalEntry].
  ///
  /// Tags are flat strings: ["daily", "voice"], not typed objects.
  static JournalEntry _noteToEntry(Map<String, dynamic> json) {
    final tags = (json['tags'] as List<dynamic>?)
            ?.map((t) => t as String)
            .toList() ??
        [];

    final isVoice = tags.contains('voice');
    final entryType = isVoice ? 'voice' : 'text';

    return JournalEntry(
      id: json['id'] as String,
      title: '',
      content: json['content'] as String? ?? '',
      type: JournalEntry.parseType(entryType),
      createdAt: JournalEntry.parseDateTime(json['createdAt'] as String?),
      audioPath: null, // Audio is now in attachments, not tag fields
      durationSeconds: null,
      isPendingTranscription: false,
      serverTranscriptionStatus: null,
    );
  }

  /// Convert a Note JSON (from search results) to an [ApiSearchResult].
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
