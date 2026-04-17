import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/config/app_config.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/core/providers/app_state_provider.dart'
    show serverUrlProvider, apiKeyProvider, vaultNameProvider;
import 'package:parachute/core/providers/feature_flags_provider.dart';
import 'package:parachute/core/services/backend_health_service.dart';
import 'package:parachute/core/services/graph_api_service.dart';
import 'package:parachute/features/settings/services/oauth_service.dart';

/// Server connection settings section — vault URL, API key, vault picker.
class ServerSettingsSection extends ConsumerStatefulWidget {
  const ServerSettingsSection({super.key});

  @override
  ConsumerState<ServerSettingsSection> createState() => _ServerSettingsSectionState();
}

class _ServerSettingsSectionState extends ConsumerState<ServerSettingsSection> {
  final _serverUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _vaultNameController = TextEditingController();

  List<String>? _availableVaults;
  String? _selectedVault;
  bool _loadingVaults = false;
  bool _showManualToken = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _apiKeyController.dispose();
    _vaultNameController.dispose();
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
        if (apiKey != null) {
          _apiKeyController.text = apiKey;
          _showManualToken = true;
        }
        _selectedVault = vaultName;
        _vaultNameController.text = vaultName ?? '';
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

  Future<void> _connectOAuth() async {
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

    // Persist the URL + any manually-entered vault name before launching
    // the browser, so they survive the round-trip and the resulting token
    // binds to the right vault in settings.
    await _saveServerUrl();
    final requestedVault = _vaultNameController.text.trim();
    if (requestedVault.isNotEmpty) {
      await _saveVaultName(requestedVault);
    }

    setState(() => _connecting = true);
    final oauth = OAuthService();
    try {
      final result = await oauth.connect(
        serverUrl: url,
        vaultName: requestedVault.isEmpty ? null : requestedVault,
      );
      _apiKeyController.text = result.token;
      await ref.read(apiKeyProvider.notifier).setApiKey(result.token);

      // Auto-select the vault the token was minted against (server-reported
      // first, falling back to the name the user typed). This keeps the
      // app-wide vault selection coherent with the token the user just got.
      // _saveVaultName handles null/empty by clearing the selection, matching
      // how the clear button calls it.
      await _saveVaultName(result.vaultName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.vaultName != null
                ? 'Connected to ${result.vaultName}'
                : 'Connected to vault'),
            backgroundColor: BrandColors.success,
          ),
        );
        _fetchVaults(url);
      }
    } on OAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${e.message}'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } finally {
      oauth.dispose();
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _saveVaultName(String? name) async {
    final cleaned = (name == null || name.isEmpty) ? null : name;
    if (mounted) {
      setState(() {
        _selectedVault = cleaned;
        _vaultNameController.text = cleaned ?? '';
      });
    } else {
      _selectedVault = cleaned;
      _vaultNameController.text = cleaned ?? '';
    }
    await ref.read(vaultNameProvider.notifier).setVaultName(cleaned);
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

    final apiKey = _apiKeyController.text.trim();
    final vaultName = _vaultNameController.text.trim();
    final healthService = BackendHealthService(
      baseUrl: url,
      apiKey: apiKey.isEmpty ? null : apiKey,
      vaultName: vaultName.isEmpty ? null : vaultName,
    );
    try {
      final result = await healthService.verifyConnection();

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      final (message, color) = _messageForVerify(result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
        ),
      );
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

  /// Map a typed verify result to a user-facing message + color.
  ///
  /// The key case is `unauthorized`/`wrong_vault`: the server is up and
  /// talking to us, but the stored token isn't valid for this vault. Tell
  /// the user to re-run Connect to Vault against the right vault, not some
  /// generic "check your connection".
  (String, Color) _messageForVerify(VerifyConnectionResult result) {
    final v = result.vaultName;
    final vaultLabel = (v == null || v.isEmpty) ? 'the default vault' : 'vault "$v"';
    switch (result.kind) {
      case VerifyResultKind.ok:
        return (
          'Connected — $vaultLabel is reachable and authorized.',
          BrandColors.success,
        );
      case VerifyResultKind.unauthorized:
      case VerifyResultKind.wrongVault:
        return (
          'Server reachable but your token isn\'t authorized for $vaultLabel. '
          'Re-run Connect to Vault.',
          BrandColors.error,
        );
      case VerifyResultKind.unreachable:
        return (
          'Cannot reach the server. Check the URL and your network.',
          BrandColors.error,
        );
      case VerifyResultKind.serverError:
        final code = result.statusCode;
        return (
          'Server returned an error${code == null ? '' : ' ($code)'}. Try again in a moment.',
          BrandColors.error,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Watch the current token + vault so the "Connected to vault X" status
    // row updates as soon as OAuth writes them. Without this, the OAuth
    // success indicator is a transient snackbar and first-time users retry
    // the flow thinking it didn't work.
    final apiKey = ref.watch(apiKeyProvider).valueOrNull;
    final vaultName = ref.watch(vaultNameProvider).valueOrNull;
    final isConnected = apiKey != null &&
        apiKey.isNotEmpty &&
        vaultName != null &&
        vaultName.isNotEmpty;

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

        // Connected status row — only when token + vault are both set.
        // Replaces the "Connect to Vault" CTA so first-time users see a clear
        // persistent success indicator instead of relying on the transient
        // snackbar alone.
        if (isConnected)
          _buildConnectedStatusRow(isDark, vaultName)
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _connecting ? null : _connectOAuth,
              icon: _connecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_open, size: 18),
              label: Text(_connecting ? 'Connecting...' : 'Connect to Vault'),
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.turquoise,
              ),
            ),
          ),
        SizedBox(height: Spacing.xs),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              setState(() => _showManualToken = !_showManualToken);
            },
            child: Text(
              _showManualToken ? 'Hide manual token' : 'Use manual token',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),

        // API Key (manual fallback)
        if (_showManualToken) ...[
          SizedBox(height: Spacing.xs),
          TextField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'pvt_... or para_...',
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
        ],
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

  /// One-line "Connected to vault X" status with a subtle Disconnect button.
  ///
  /// Shown instead of the "Connect to Vault" CTA when the user has both a
  /// token and a vault name configured. Disconnect clears the token (and only
  /// the token — the URL and vault name stay so the user can re-Connect
  /// without re-typing).
  Widget _buildConnectedStatusRow(bool isDark, String vaultName) {
    final bg = isDark
        ? BrandColors.success.withValues(alpha: 0.15)
        : BrandColors.success.withValues(alpha: 0.08);
    final fg = isDark ? BrandColors.nightText : BrandColors.charcoal;

    return Container(
      key: const ValueKey('connected-status-row'),
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BrandColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: BrandColors.success,
            size: 20,
          ),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Connected to vault "$vaultName"',
              style: TextStyle(
                fontSize: TypographyTokens.bodyMedium,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: Spacing.sm),
          TextButton(
            onPressed: _connecting ? null : _disconnect,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: Spacing.sm),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Disconnect',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    // Clear the token only; leave the server URL and vault name so the user
    // can re-Connect without retyping. Matches the "reconnect" mental model.
    _apiKeyController.clear();
    await ref.read(apiKeyProvider.notifier).setApiKey(null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Disconnected from vault'),
          backgroundColor: BrandColors.warning,
        ),
      );
    }
  }

  Widget _buildVaultPicker(bool isDark) {
    // Always render a manual text field so the user can pick a vault before
    // Connect to Vault (needed for per-vault-scoped OAuth). When the server
    // happens to expose `/vaults`, also offer it as a dropdown on the side.
    final manualField = TextField(
      controller: _vaultNameController,
      decoration: InputDecoration(
        labelText: 'Vault name',
        hintText: 'Leave blank for default',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.inventory_2_outlined),
        suffixIcon: _vaultNameController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _saveVaultName(null),
              ),
      ),
      onSubmitted: (value) => _saveVaultName(value.trim()),
      onChanged: (_) => setState(() {}), // refresh suffix icon
    );

    final helpText = Padding(
      padding: EdgeInsets.only(top: Spacing.xs),
      child: Text(
        'Scopes Connect to Vault and Test Connection to this vault. '
        'Leave blank to use the server default.',
        style: TextStyle(
          fontSize: TypographyTokens.bodySmall,
          color: isDark
              ? BrandColors.nightTextSecondary
              : BrandColors.driftwood,
        ),
      ),
    );

    if (_loadingVaults) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          manualField,
          SizedBox(height: Spacing.xs),
          Row(
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: Spacing.sm),
              Text(
                'Loading vault list...',
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
            ],
          ),
        ],
      );
    }

    final vaults = _availableVaults;
    if (vaults == null || vaults.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [manualField, helpText],
      );
    }

    // Show the manual field plus a picker so the user can switch between
    // known vaults without retyping.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        manualField,
        SizedBox(height: Spacing.sm),
        DropdownButtonFormField<String>(
          initialValue: vaults.contains(_selectedVault) ? _selectedVault : null,
          decoration: const InputDecoration(
            labelText: 'Known vaults on this server',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.list_alt_outlined),
          ),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Default'),
            ),
            ...vaults.map((name) => DropdownMenuItem(
                  value: name,
                  child: Text(name),
                )),
          ],
          onChanged: (name) => _saveVaultName(name),
        ),
        helpText,
      ],
    );
  }
}
