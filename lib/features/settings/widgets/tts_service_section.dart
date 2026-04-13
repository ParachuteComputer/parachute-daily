import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/core/services/tts_api_service.dart';
import 'package:parachute/features/daily/recorder/providers/service_providers.dart';

/// Settings section for configuring a TTS service (Narrate / OpenAI TTS-compatible).
class TtsServiceSection extends ConsumerStatefulWidget {
  const TtsServiceSection({super.key});

  @override
  ConsumerState<TtsServiceSection> createState() => _TtsServiceSectionState();
}

class _TtsServiceSectionState extends ConsumerState<TtsServiceSection> {
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
    final url = await ref.read(ttsServiceUrlProvider.future);
    final apiKey = await ref.read(ttsServiceApiKeyProvider.future);
    if (mounted) {
      if (url != null) _urlController.text = url;
      if (apiKey != null) _apiKeyController.text = apiKey;
    }
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    await setTtsServiceUrl(url.isEmpty ? null : url);
    ref.invalidate(ttsServiceUrlProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(url.isEmpty
              ? 'TTS service URL cleared'
              : 'TTS service URL saved'),
          backgroundColor: BrandColors.success,
        ),
      );
    }
  }

  Future<void> _saveApiKey({bool showSnackbar = true}) async {
    final key = _apiKeyController.text.trim();
    await ref.read(ttsServiceApiKeyProvider.notifier).setApiKey(
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
          content: const Text('Enter a TTS service URL first'),
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
    final service = TtsApiService(
      baseUrl: url,
      apiKey: apiKey.isEmpty ? null : apiKey,
    );

    try {
      final ok = await service.checkConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Connected to TTS service' : 'TTS service not reachable'),
            backgroundColor: ok ? BrandColors.success : BrandColors.error,
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
              Icons.volume_up,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
            SizedBox(width: Spacing.sm),
            Text(
              'Read Aloud (Narrate)',
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
          'Connect to an OpenAI TTS-compatible endpoint '
          '(Narrate, OpenAI, etc.) to read notes aloud.',
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
            hintText: 'http://192.168.1.100:5912',
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
