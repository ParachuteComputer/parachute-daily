import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/core/services/transcription_api_service.dart';
import 'package:parachute/features/daily/recorder/providers/service_providers.dart';

/// Settings section for configuring an external Whisper-compatible transcription service.
class TranscriptionServiceSection extends ConsumerStatefulWidget {
  const TranscriptionServiceSection({super.key});

  @override
  ConsumerState<TranscriptionServiceSection> createState() =>
      _TranscriptionServiceSectionState();
}

class _TranscriptionServiceSectionState
    extends ConsumerState<TranscriptionServiceSection> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final url = await ref.read(transcriptionServiceUrlProvider.future);
    final apiKey = await ref.read(transcriptionServiceApiKeyProvider.future);
    if (mounted) {
      if (url != null) _urlController.text = url;
      if (apiKey != null) _apiKeyController.text = apiKey;
    }
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    await setTranscriptionServiceUrl(url.isEmpty ? null : url);
    ref.invalidate(transcriptionServiceUrlProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(url.isEmpty
              ? 'Transcription service URL cleared'
              : 'Transcription service URL saved'),
          backgroundColor: BrandColors.success,
        ),
      );
    }
  }

  Future<void> _saveApiKey({bool showSnackbar = true}) async {
    final key = _apiKeyController.text.trim();
    await ref.read(transcriptionServiceApiKeyProvider.notifier).setApiKey(
      key.isEmpty ? null : key,
    );
    if (showSnackbar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(key.isEmpty ? 'API key cleared' : 'API key saved'),
          backgroundColor: BrandColors.success,
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter a transcription service URL first'),
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
                valueColor:
                    AlwaysStoppedAnimation<Color>(BrandColors.softWhite),
              ),
            ),
            SizedBox(width: Spacing.md),
            const Text('Testing connection...'),
          ],
        ),
        duration: const Duration(seconds: 10),
      ),
    );

    final apiKey = _apiKeyController.text.trim();
    final service = TranscriptionApiService(
      baseUrl: url,
      apiKey: apiKey.isEmpty ? null : apiKey,
    );

    try {
      final result = await service.checkConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        final color = result.authOk
            ? BrandColors.success
            : result.reachable
                ? BrandColors.warning
                : BrandColors.error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: color,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } finally {
      service.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.record_voice_over,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
            SizedBox(width: Spacing.sm),
            Text(
              'Transcription Service',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: TypographyTokens.bodyLarge,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
          ],
        ),
        SizedBox(height: Spacing.sm),
        Text(
          'Connect to a Whisper-compatible transcription API '
          '(OpenAI, Groq, parachute-scribe, etc.).',
          style: TextStyle(
            fontSize: TypographyTokens.bodySmall,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
        SizedBox(height: Spacing.lg),

        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'Service URL',
            hintText: 'https://api.groq.com/openai',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.link),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _urlController.clear();
                _saveUrl();
              },
            ),
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _saveUrl(),
        ),
        SizedBox(height: Spacing.md),

        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(
            labelText: 'API Key (optional)',
            hintText: 'sk-...',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _apiKeyController.clear();
                _saveApiKey();
              },
            ),
          ),
          obscureText: true,
          onSubmitted: (_) => _saveApiKey(),
        ),
        SizedBox(height: Spacing.lg),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testConnection,
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Test Connection'),
              ),
            ),
            SizedBox(width: Spacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  await _saveUrl();
                  await _saveApiKey(showSnackbar: false);
                },
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Save'),
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.turquoise,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
