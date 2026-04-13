import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/config/app_config.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/core/providers/app_state_provider.dart'
    show serverUrlProvider, apiKeyProvider, vaultNameProvider;
import 'package:parachute/core/providers/feature_flags_provider.dart';
import 'package:parachute/core/services/backend_health_service.dart';
import 'package:parachute/core/services/graph_api_service.dart';

/// Server connection settings section — vault URL, API key, vault picker.
class ServerSettingsSection extends ConsumerStatefulWidget {
  const ServerSettingsSection({super.key});

  @override
  ConsumerState<ServerSettingsSection> createState() => _ServerSettingsSectionState();
}

class _ServerSettingsSectionState extends ConsumerState<ServerSettingsSection> {
  final _serverUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();

  List<String>? _availableVaults;
  String? _selectedVault;
  bool _loadingVaults = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final featureFlags = ref.read(featureFlagsServiceProvider);
    final serverUrl = await featureFlags.getAiServerUrl();
    final apiKey = ref.read(apiKeyProvider).valueOrNull;
    final vaultName = ref.read(vaultNameProvider).valueOrNull;

    if (mounted) {
      setState(() {
        _serverUrlController.text = serverUrl;
        if (apiKey != null) _apiKeyController.text = apiKey;
        _selectedVault = vaultName;
      });

      // Fetch vaults if we have a URL
      if (serverUrl.isNotEmpty) {
        _fetchVaults(serverUrl);
      }
    }
  }

  Future<void> _fetchVaults(String url) async {
    if (url.isEmpty) return;
    setState(() => _loadingVaults = true);

    final api = GraphApiService(
      baseUrl: url,
      apiKey: _apiKeyController.text.trim().isEmpty
          ? null
          : _apiKeyController.text.trim(),
    );

    try {
      final vaults = await api.fetchVaults();
      if (mounted) {
        setState(() {
          _availableVaults = vaults;
          _loadingVaults = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingVaults = false);
    }
  }

  Future<void> _saveServerUrl() async {
    final url = _serverUrlController.text.trim();
    final featureFlags = ref.read(featureFlagsServiceProvider);

    try {
      await featureFlags.setAiServerUrl(
          url.isEmpty ? AppConfig.defaultServerUrl : url);
      featureFlags.clearCache();
      ref.invalidate(aiServerUrlProvider);
      await ref.read(serverUrlProvider.notifier).setServerUrl(
          url.isEmpty ? null : url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(url.isEmpty
                ? 'Server URL cleared - offline mode'
                : 'Server URL saved'),
            backgroundColor: BrandColors.success,
          ),
        );
      }

      // Refresh vault list with new URL
      if (url.isNotEmpty) _fetchVaults(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid URL: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveApiKey({bool showSnackbar = true}) async {
    final key = _apiKeyController.text.trim();
    await ref.read(apiKeyProvider.notifier).setApiKey(key.isEmpty ? null : key);
    if (showSnackbar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(key.isEmpty ? 'API key cleared' : 'API key saved'),
          backgroundColor: BrandColors.success,
        ),
      );
    }
  }

  Future<void> _saveVaultName(String? name) async {
    setState(() => _selectedVault = name);
    await ref
        .read(vaultNameProvider.notifier)
        .setVaultName(name == null || name.isEmpty ? null : name);
  }

  Future<void> _saveAll() async {
    await _saveServerUrl();
    await _saveApiKey(showSnackbar: false);
  }

  Future<void> _testServerConnection() async {
    final url = _serverUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter a server URL first'),
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

    final healthService = BackendHealthService(baseUrl: url);
    try {
      final status = await healthService.checkHealth();

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        if (status.isHealthy) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(status.serverVersion != null
                  ? 'Connected to Parachute Computer v${status.serverVersion}'
                  : 'Connected to Parachute Computer'),
              backgroundColor: BrandColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${status.message}: ${status.helpText}'),
              backgroundColor: BrandColors.error,
            ),
          );
        }
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
      healthService.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(
              Icons.cloud_outlined,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
            SizedBox(width: Spacing.sm),
            Text(
              'Parachute Computer',
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
          'Connect to a Parachute Vault for sync and search. '
          'Leave empty for offline mode.',
          style: TextStyle(
            fontSize: TypographyTokens.bodySmall,
            color: isDark
                ? BrandColors.nightTextSecondary
                : BrandColors.driftwood,
          ),
        ),
        SizedBox(height: Spacing.lg),

        // Server URL
        TextField(
          controller: _serverUrlController,
          decoration: InputDecoration(
            labelText: 'Server URL',
            hintText: AppConfig.defaultServerUrl,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.link),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _serverUrlController.clear();
                _saveServerUrl();
              },
            ),
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _saveServerUrl(),
        ),
        SizedBox(height: Spacing.md),

        // API Key
        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: 'para_... or pvk_...',
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
        SizedBox(height: Spacing.md),

        // Vault picker
        _buildVaultPicker(isDark),
        SizedBox(height: Spacing.lg),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testServerConnection,
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Test Connection'),
              ),
            ),
            SizedBox(width: Spacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saveAll,
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

  Widget _buildVaultPicker(bool isDark) {
    if (_loadingVaults) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: Spacing.sm),
          Text(
            'Loading vaults...',
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
        ],
      );
    }

    if (_availableVaults == null || _availableVaults!.isEmpty) {
      return const SizedBox.shrink();
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedVault,
      decoration: const InputDecoration(
        labelText: 'Vault',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.inventory_2_outlined),
      ),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('Default'),
        ),
        ..._availableVaults!.map((name) => DropdownMenuItem(
              value: name,
              child: Text(name),
            )),
      ],
      onChanged: (name) => _saveVaultName(name),
    );
  }
}
