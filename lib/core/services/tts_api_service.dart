import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// OpenAI TTS-compatible API client for Narrate.
///
/// Sends text to any endpoint that speaks the OpenAI TTS API shape:
///   POST {baseUrl}/v1/audio/speech
///   body: { "input": "...", "model": "...", "voice": "..." }
///   response: audio bytes (OGG Opus)
///
/// Compatible with: OpenAI, Narrate (parachute-narrate).
class TtsApiService {
  final String baseUrl;
  final String? apiKey;
  final http.Client _client;
  final Duration _timeout;

  TtsApiService({
    required this.baseUrl,
    this.apiKey,
    http.Client? client,
    Duration timeout = const Duration(seconds: 60),
  })  : _client = client ?? http.Client(),
        _timeout = timeout;

  /// Synthesize speech from text. Returns audio bytes (OGG Opus).
  Future<Uint8List> synthesize(String text) async {
    final uri = Uri.parse('$baseUrl/v1/audio/speech');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (apiKey != null && apiKey!.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
    };

    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode({'input': text}),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      debugPrint('[TtsApi] Error ${response.statusCode}: ${response.body}');
      throw Exception(
        'TTS failed (${response.statusCode}): ${response.reasonPhrase}',
      );
    }

    return response.bodyBytes;
  }

  /// Check if the TTS endpoint is reachable.
  Future<bool> checkConnection() async {
    try {
      final uri = Uri.parse('$baseUrl/v1/models');
      final headers = <String, String>{
        if (apiKey != null && apiKey!.isNotEmpty)
          'Authorization': 'Bearer $apiKey',
      };

      final response = await _client.get(uri, headers: headers).timeout(
        const Duration(seconds: 5),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[TtsApi] Connection check failed: $e');
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}
