import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/config/app_config.dart';
import 'package:parachute/core/providers/app_state_provider.dart';
import 'package:parachute/core/services/graph_api_service.dart';
import 'package:parachute/core/theme/design_tokens.dart';

export 'package:parachute/core/providers/app_state_provider.dart' show isDailyOnlyFlavor;

/// Steps in the onboarding flow.
enum _Step { welcome, server, apiKey, vault, done }

/// Onboarding flow: Welcome → Server → API Key → Vault → Done.
///
/// Collects the minimum config needed to reach a working Capture screen:
/// - Server URL (validated via /api/health)
/// - Optional API key (validated with auth header)
/// - Vault selection (from GET /vaults)
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;

  // Form state
  final _serverUrlController = TextEditingController(text: AppConfig.defaultServerUrl);
  final _apiKeyController = TextEditingController();

  // Probe results
  bool _serverReachable = false;
  List<String> _availableVaults = const [];
  String? _selectedVault;

  // UI state
  bool _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _serverUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  // ---- Step transitions ----

  void _goTo(_Step step) {
    setState(() {
      _step = step;
      _errorMessage = null;
    });
  }

  /// Probe the server: healthy? auth required? fetch vaults.
  Future<void> _testServer() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final url = _serverUrlController.text.trim();
    if (!ServerUrlNotifier.isValidServerUrl(url)) {
      setState(() {
        _busy = false;
        _errorMessage = 'Please enter a valid http:// or https:// URL';
      });
      return;
    }

    // Probe with no auth first to see if auth is required
    final probe = GraphApiService(baseUrl: url);
    final healthyNoAuth = await probe.isHealthy();

    if (!mounted) return;

    if (healthyNoAuth) {
      _serverReachable = true;
      // Try fetching vaults
      final vaults = await probe.fetchVaults();
      if (!mounted) return;
      _availableVaults = vaults ?? const [];
      setState(() {
        _busy = false;
      });
      // Save URL now so dependent screens work; move on.
      await ref.read(serverUrlProvider.notifier).setServerUrl(url);
      _goTo(_Step.apiKey); // User can skip if no auth needed
      return;
    }

    // Might need auth — assume so and let user enter key
    _serverReachable = false;
    setState(() {
      _busy = false;
      _errorMessage =
          'Could not reach server. Check the URL, or continue to enter an API key.';
    });
  }

  /// Test API key by making an authenticated health check.
  Future<void> _testApiKeyAndFetchVaults() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final url = _serverUrlController.text.trim();
    final key = _apiKeyController.text.trim();

    final probe = GraphApiService(
      baseUrl: url,
      apiKey: key.isEmpty ? null : key,
    );
    final healthy = await probe.isHealthy();
    if (!mounted) return;
    if (!healthy) {
      setState(() {
        _busy = false;
        _errorMessage = 'Server still unreachable with that key. Check both.';
      });
      return;
    }

    final vaults = await probe.fetchVaults();
    if (!mounted) return;

    _availableVaults = vaults ?? const [];
    _serverReachable = true;
    await ref.read(serverUrlProvider.notifier).setServerUrl(url);
    if (key.isNotEmpty) {
      await ref.read(apiKeyProvider.notifier).setApiKey(key);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _advanceAfterAuth();
  }

  /// Skip the API key step (use unauthenticated access).
  void _skipApiKey() {
    _advanceAfterAuth();
  }

  void _advanceAfterAuth() {
    // Auto-select if only one (or zero) vaults, then skip the picker.
    if (_availableVaults.length <= 1) {
      _selectedVault = _availableVaults.isNotEmpty ? _availableVaults.first : null;
      _saveVaultAndFinish();
      return;
    }
    _selectedVault = _availableVaults.first;
    _goTo(_Step.vault);
  }

  Future<void> _saveVaultAndFinish() async {
    setState(() => _busy = true);
    if (_selectedVault != null && _selectedVault!.isNotEmpty) {
      await ref.read(vaultNameProvider.notifier).setVaultName(_selectedVault);
    }
    if (!mounted) return;
    _goTo(_Step.done);
    setState(() => _busy = false);
  }

  Future<void> _completeOnboarding() async {
    await ref.read(onboardingCompleteProvider.notifier).markComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  /// Allow the user to continue without a working server (they can fix it
  /// in Settings later). Marks onboarding complete with whatever we have.
  Future<void> _continueAnyway() async {
    final url = _serverUrlController.text.trim();
    if (ServerUrlNotifier.isValidServerUrl(url)) {
      await ref.read(serverUrlProvider.notifier).setServerUrl(url);
    }
    await _completeOnboarding();
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? BrandColors.nightSurface : BrandColors.cream;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Spacing.xl),
          child: switch (_step) {
            _Step.welcome => _buildWelcome(isDark),
            _Step.server => _buildServer(isDark),
            _Step.apiKey => _buildApiKey(isDark),
            _Step.vault => _buildVault(isDark),
            _Step.done => _buildDone(isDark),
          },
        ),
      ),
    );
  }

  // ---- Step views ----

  Widget _buildWelcome(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        Icon(
          Icons.today,
          size: 80,
          color: isDark ? BrandColors.nightForest : BrandColors.forest,
        ),
        SizedBox(height: Spacing.xl),
        _title('Parachute Daily', isDark),
        SizedBox(height: Spacing.md),
        _subtitle('Your personal graph.\nJournal in, AI plugs in.', isDark),
        const Spacer(),
        _primaryButton('Get Started', isDark, () => _goTo(_Step.server)),
        SizedBox(height: Spacing.xl),
      ],
    );
  }

  Widget _buildServer(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        _stepHeader('Connect to your vault', isDark),
        SizedBox(height: Spacing.md),
        _subtitle(
          'Parachute Daily syncs with a Parachute Vault. '
          'Enter the URL where your vault is running.',
          isDark,
        ),
        SizedBox(height: Spacing.xl),
        TextField(
          controller: _serverUrlController,
          enabled: !_busy,
          autocorrect: false,
          keyboardType: TextInputType.url,
          style: TextStyle(
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
          decoration: InputDecoration(
            labelText: 'Server URL',
            hintText: 'http://localhost:1940',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            filled: true,
            fillColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
          ),
        ),
        if (_errorMessage != null) ...[
          SizedBox(height: Spacing.md),
          _errorText(_errorMessage!),
        ],
        const Spacer(),
        _primaryButton(
          _busy ? 'Testing…' : 'Test Connection',
          isDark,
          _busy ? null : _testServer,
        ),
        SizedBox(height: Spacing.sm),
        _secondaryButton('Back', isDark, _busy ? null : () => _goTo(_Step.welcome)),
        SizedBox(height: Spacing.xl),
      ],
    );
  }

  Widget _buildApiKey(bool isDark) {
    final skipLabel = _serverReachable ? 'Skip (no key needed)' : 'Skip';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        _stepHeader(
          _serverReachable ? 'Optional: API key' : 'Enter API key',
          isDark,
        ),
        SizedBox(height: Spacing.md),
        _subtitle(
          _serverReachable
              ? 'Your server is reachable without authentication. '
                  'If you want to secure it later, add a key here.'
              : 'The server may require authentication. '
                  'Paste your API key to continue.',
          isDark,
        ),
        SizedBox(height: Spacing.xl),
        TextField(
          controller: _apiKeyController,
          enabled: !_busy,
          autocorrect: false,
          obscureText: true,
          style: TextStyle(
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: 'para_…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            filled: true,
            fillColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
          ),
        ),
        if (_errorMessage != null) ...[
          SizedBox(height: Spacing.md),
          _errorText(_errorMessage!),
        ],
        const Spacer(),
        _primaryButton(
          _busy ? 'Testing…' : 'Test & Continue',
          isDark,
          _busy ? null : _testApiKeyAndFetchVaults,
        ),
        SizedBox(height: Spacing.sm),
        _secondaryButton(skipLabel, isDark, _busy ? null : _skipApiKey),
        SizedBox(height: Spacing.xl),
      ],
    );
  }

  Widget _buildVault(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        _stepHeader('Choose a vault', isDark),
        SizedBox(height: Spacing.md),
        _subtitle(
          'Your server has multiple vaults. Pick one to start with — '
          'you can change this anytime in Settings.',
          isDark,
        ),
        SizedBox(height: Spacing.xl),
        Container(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: BoxDecoration(
            color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: BrandColors.stone),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedVault,
              isExpanded: true,
              items: _availableVaults
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _selectedVault = v),
            ),
          ),
        ),
        const Spacer(),
        _primaryButton(
          _busy ? 'Saving…' : 'Continue',
          isDark,
          _busy ? null : _saveVaultAndFinish,
        ),
        SizedBox(height: Spacing.xl),
      ],
    );
  }

  Widget _buildDone(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        Icon(
          Icons.check_circle,
          size: 80,
          color: BrandColors.success,
        ),
        SizedBox(height: Spacing.xl),
        _title("You're ready", isDark),
        SizedBox(height: Spacing.md),
        _subtitle(
          _serverReachable
              ? 'Connected to your vault. Time to capture something.'
              : 'Setup saved. You can fix the server connection in Settings.',
          isDark,
        ),
        const Spacer(),
        _primaryButton('Start Capturing', isDark, _completeOnboarding),
        if (!_serverReachable) ...[
          SizedBox(height: Spacing.sm),
          _secondaryButton('Continue anyway', isDark, _continueAnyway),
        ],
        SizedBox(height: Spacing.xl),
      ],
    );
  }

  // ---- Shared widgets ----

  Widget _title(String text, bool isDark) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: TypographyTokens.headlineLarge,
          fontWeight: FontWeight.bold,
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
        ),
      );

  Widget _stepHeader(String text, bool isDark) => Text(
        text,
        style: TextStyle(
          fontSize: TypographyTokens.headlineMedium,
          fontWeight: FontWeight.bold,
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
        ),
      );

  Widget _subtitle(String text, bool isDark) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: TypographyTokens.bodyLarge,
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          height: 1.4,
        ),
      );

  Widget _errorText(String text) => Text(
        text,
        style: TextStyle(
          color: BrandColors.error,
          fontSize: TypographyTokens.bodyMedium,
        ),
      );

  Widget _primaryButton(String label, bool isDark, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
          padding: EdgeInsets.symmetric(vertical: Spacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _secondaryButton(String label, bool isDark, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
      ),
    );
  }
}
