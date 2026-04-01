import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/thing.dart';

/// Service for communicating with the Parachute Daily v3 API.
/// Targets /api/* on the local server.
class GraphApiService {
  final String baseUrl;
  final http.Client _client;
  final String? _apiKey;
  final Duration _timeout;

  /// Callback for instant network state changes
  void Function(bool reachable)? onReachabilityChanged;

  GraphApiService({
    required this.baseUrl,
    String? apiKey,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    this.onReachabilityChanged,
  })  : _apiKey = apiKey,
        _client = client ?? http.Client(),
        _timeout = timeout;

  // ---- Notes ----

  /// Query notes by tags, date range, etc.
  Future<List<Note>?> queryNotes({
    String? tag,
    String? excludeTag,
    String? dateFrom,
    String? dateTo,
    String? sort,
    int? limit,
  }) async {
    final params = <String, String>{};
    if (tag != null) params['tag'] = tag;
    if (excludeTag != null) params['exclude_tag'] = excludeTag;
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;
    if (sort != null) params['sort'] = sort;
    if (limit != null) params['limit'] = limit.toString();

    final data = await _get('/notes', params);
    if (data == null) return null;
    return (data as List).map((j) => Note.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Create a note with optional tags and path.
  Future<Note?> createNote(
    String content, {
    String? id,
    String? path,
    List<String>? tags,
  }) async {
    final body = <String, dynamic>{
      'content': content,
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (tags != null) 'tags': tags,
    };
    final data = await _post('/notes', body);
    if (data == null) return null;
    return Note.fromJson(data as Map<String, dynamic>);
  }

  /// Get a note by ID.
  Future<Note?> getNote(String id) async {
    final data = await _get('/notes/$id', {});
    if (data == null) return null;
    return Note.fromJson(data as Map<String, dynamic>);
  }

  /// Update a note's content and/or path.
  Future<Note?> updateNote(
    String id, {
    String? content,
    String? path,
  }) async {
    final body = <String, dynamic>{};
    if (content != null) body['content'] = content;
    if (path != null) body['path'] = path;
    final data = await _patch('/notes/$id', body);
    if (data == null) return null;
    return Note.fromJson(data as Map<String, dynamic>);
  }

  /// Delete a note.
  Future<bool> deleteNote(String id) async {
    final data = await _delete('/notes/$id');
    return data != null;
  }

  /// Tag a note.
  Future<Note?> tagNote(String id, List<String> tags) async {
    final data = await _post('/notes/$id/tags', {'tags': tags});
    if (data == null) return null;
    return Note.fromJson(data as Map<String, dynamic>);
  }

  /// Untag a note.
  Future<Note?> untagNote(String id, List<String> tags) async {
    final data = await _deleteWithBody('/notes/$id/tags', {'tags': tags});
    if (data == null) return null;
    return Note.fromJson(data as Map<String, dynamic>);
  }

  /// Get links for a note.
  Future<List<NoteLink>?> getLinks(
    String noteId, {
    String direction = 'both',
  }) async {
    final params = <String, String>{'direction': direction};
    final data = await _get('/notes/$noteId/links', params);
    if (data == null) return null;
    return (data as List).map((j) => NoteLink.fromJson(j as Map<String, dynamic>)).toList();
  }

  // ---- Search ----

  /// Full-text search across notes.
  Future<List<Note>?> searchNotes(
    String query, {
    String? tag,
    int? limit,
  }) async {
    final params = <String, String>{'q': query};
    if (tag != null) params['tag'] = tag;
    if (limit != null) params['limit'] = limit.toString();

    final data = await _get('/search', params);
    if (data == null) return null;
    return (data as List).map((j) => Note.fromJson(j as Map<String, dynamic>)).toList();
  }

  // ---- Links ----

  /// Create a link between two notes.
  Future<NoteLink?> createLink(
    String sourceId,
    String targetId,
    String relationship,
  ) async {
    final data = await _post('/links', {
      'source_id': sourceId,
      'target_id': targetId,
      'relationship': relationship,
    });
    if (data == null) return null;
    return NoteLink.fromJson(data as Map<String, dynamic>);
  }

  // ---- Tags ----

  /// List all tags with usage counts.
  Future<List<Map<String, dynamic>>?> getTags() async {
    final data = await _get('/tags', {});
    if (data == null) return null;
    return (data as List).map((j) => j as Map<String, dynamic>).toList();
  }

  // ---- Attachments ----

  /// Add an attachment to a note.
  Future<Map<String, dynamic>?> addAttachment(
    String noteId,
    String path,
    String mimeType,
  ) async {
    final data = await _post('/notes/$noteId/attachments', {
      'path': path,
      'mime_type': mimeType,
    });
    return data as Map<String, dynamic>?;
  }

  /// Get attachments for a note.
  Future<List<Map<String, dynamic>>?> getAttachments(String noteId) async {
    final data = await _get('/notes/$noteId/attachments', {});
    if (data == null) return null;
    return (data as List).map((j) => j as Map<String, dynamic>).toList();
  }

  // ---- Storage ----

  /// Upload an audio file, returns the relative storage path.
  Future<String?> uploadAudio(Uint8List data, String filename) async {
    try {
      final uri = Uri.parse('$baseUrl/storage/upload');
      final request = http.MultipartRequest('POST', uri);
      _addAuthHeaders(request.headers);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        data,
        filename: filename,
      ));

      final response = await request.send().timeout(_timeout);
      if (response.statusCode == 201) {
        final body = await response.stream.bytesToString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        _notifyReachable(true);
        return json['path'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('[GraphApiService] Upload error: $e');
      _notifyReachable(false);
      return null;
    }
  }

  // ---- Health ----

  /// Check server health.
  Future<bool> isHealthy() async {
    try {
      final uri = Uri.parse('$baseUrl/health');
      final response = await _client.get(uri, headers: _headers()).timeout(
        const Duration(seconds: 5),
      );
      final healthy = response.statusCode == 200;
      _notifyReachable(healthy);
      return healthy;
    } catch (_) {
      _notifyReachable(false);
      return false;
    }
  }

  // ---- HTTP Helpers ----

  Future<dynamic> _get(String path, Map<String, String> params) async {
    try {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await _client.get(uri, headers: _headers()).timeout(_timeout);
      _notifyReachable(true);
      if (response.statusCode == 200) return jsonDecode(response.body);
      if (response.statusCode == 404) return null;
      debugPrint('[GraphApiService] GET $path: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[GraphApiService] GET $path error: $e');
      _notifyReachable(false);
      return null;
    }
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode(body),
      ).timeout(_timeout);
      _notifyReachable(true);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      debugPrint('[GraphApiService] POST $path: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      debugPrint('[GraphApiService] POST $path error: $e');
      _notifyReachable(false);
      return null;
    }
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await _client.patch(
        uri,
        headers: _headers(),
        body: jsonEncode(body),
      ).timeout(_timeout);
      _notifyReachable(true);
      if (response.statusCode == 200) return jsonDecode(response.body);
      debugPrint('[GraphApiService] PATCH $path: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[GraphApiService] PATCH $path error: $e');
      _notifyReachable(false);
      return null;
    }
  }

  Future<dynamic> _delete(String path) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await _client.delete(uri, headers: _headers()).timeout(_timeout);
      _notifyReachable(true);
      if (response.statusCode == 200) return jsonDecode(response.body);
      debugPrint('[GraphApiService] DELETE $path: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[GraphApiService] DELETE $path error: $e');
      _notifyReachable(false);
      return null;
    }
  }

  Future<dynamic> _deleteWithBody(String path, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = http.Request('DELETE', uri);
      request.headers.addAll(_headers());
      request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(_timeout);
      _notifyReachable(true);
      if (streamed.statusCode == 200) {
        final responseBody = await streamed.stream.bytesToString();
        return jsonDecode(responseBody);
      }
      debugPrint('[GraphApiService] DELETE $path: ${streamed.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[GraphApiService] DELETE $path error: $e');
      _notifyReachable(false);
      return null;
    }
  }

  Map<String, String> _headers() {
    final headers = {'Content-Type': 'application/json'};
    if (_apiKey != null) headers['Authorization'] = 'Bearer $_apiKey';
    return headers;
  }

  void _addAuthHeaders(Map<String, String> headers) {
    if (_apiKey != null) headers['Authorization'] = 'Bearer $_apiKey';
  }

  void _notifyReachable(bool reachable) {
    onReachabilityChanged?.call(reachable);
  }
}
