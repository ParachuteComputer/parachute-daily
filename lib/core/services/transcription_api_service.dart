import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Whisper-compatible transcription API client.
///
/// Sends audio to any endpoint that speaks the OpenAI Whisper API shape:
///   POST {baseUrl}/v1/audio/transcriptions
///   multipart form: file (audio), model (string), language (optional)
///   response: { "text": "..." }
///
/// Compatible with: OpenAI, Groq, whisper.cpp server, parachute-scribe.
class TranscriptionApiService {
  final String baseUrl;
  final String? apiKey;
  final String model;
  final http.Client _client;
  final Duration _timeout;

  TranscriptionApiService({
    required this.baseUrl,
    this.apiKey,
    this.model = 'whisper-large-v3',
    http.Client? client,
    Duration timeout = const Duration(minutes: 10),
  })  : _client = client ?? http.Client(),
        _timeout = timeout;

  /// Transcribe an audio file. Returns the transcribed text.
  Future<String> transcribe(String audioFilePath, {String? language}) async {
    final uri = Uri.parse('$baseUrl/v1/audio/transcriptions');
    final request = http.MultipartRequest('POST', uri);

    // Auth header
    if (apiKey != null && apiKey!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }

    // Form fields
    request.fields['model'] = model;
    if (language != null) {
      request.fields['language'] = language;
    }

    // Audio file
    final file = File(audioFilePath);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $audioFilePath');
    }
    request.files.add(await http.MultipartFile.fromPath('file', audioFilePath));

    // Send
    final streamedResponse = await _client.send(request).timeout(_timeout);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      debugPrint('[TranscriptionApi] Error ${response.statusCode}: ${response.body}');
      throw Exception(
        'Transcription failed (${response.statusCode}): ${response.reasonPhrase}',
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final text = data['text'] as String?;
    if (text == null) {
      throw Exception('Transcription response missing "text" field');
    }

    return text.trim();
  }

  /// Check if the transcription endpoint is reachable via GET /v1/models.
  Future<ConnectionResult> checkConnection() async {
    try {
      final uri = Uri.parse('$baseUrl/v1/models');
      final headers = <String, String>{
        if (apiKey != null && apiKey!.isNotEmpty)
          'Authorization': 'Bearer $apiKey',
      };
      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return ConnectionResult.ok('Transcription service connected');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return ConnectionResult.authError(
          'Server reachable but authentication failed — check your API key',
        );
      } else {
        return ConnectionResult.error('Server returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[TranscriptionApi] Connection check failed: $e');
      return ConnectionResult.error('Could not reach transcription service');
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Result of a transcription service connection check.
class ConnectionResult {
  final bool reachable;
  final bool authOk;
  final String message;

  const ConnectionResult._({
    required this.reachable,
    required this.authOk,
    required this.message,
  });

  factory ConnectionResult.ok(String message) =>
      ConnectionResult._(reachable: true, authOk: true, message: message);

  factory ConnectionResult.authError(String message) =>
      ConnectionResult._(reachable: true, authOk: false, message: message);

  factory ConnectionResult.error(String message) =>
      ConnectionResult._(reachable: false, authOk: false, message: message);
}
