import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// Service for managing feature toggles
///
/// Controls which advanced features are enabled:
/// - Omi device integration (off by default)
/// - Server URL configuration
class FeatureFlagsService {
  static final FeatureFlagsService _instance = FeatureFlagsService._internal();
  factory FeatureFlagsService() => _instance;
  FeatureFlagsService._internal();

  static const String _omiEnabledKey = 'feature_omi_enabled';
  /// Canonical key — shared with ServerUrlNotifier in app_state_provider.dart.
  static const String _aiServerUrlKey = 'parachute_server_url';

  /// Legacy key — migrated to _aiServerUrlKey on first read.
  static const String _legacyAiServerUrlKey = 'feature_ai_server_url';

  // Default values
  static const bool _defaultOmiEnabled = false;
  static const String _defaultAiServerUrl = AppConfig.defaultServerUrl;

  // Cache for quick access
  bool? _omiEnabled;
  String? _aiServerUrl;

  /// Check if Omi device integration is enabled
  Future<bool> isOmiEnabled() async {
    if (_omiEnabled != null) return _omiEnabled!;

    final prefs = await SharedPreferences.getInstance();
    _omiEnabled = prefs.getBool(_omiEnabledKey) ?? _defaultOmiEnabled;
    return _omiEnabled!;
  }

  /// Set Omi device integration enabled state
  Future<void> setOmiEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_omiEnabledKey, enabled);
    _omiEnabled = enabled;
  }

  /// Get server URL. Migrates from legacy key on first read.
  Future<String> getAiServerUrl() async {
    if (_aiServerUrl != null) return _aiServerUrl!;

    final prefs = await SharedPreferences.getInstance();

    // Migrate from legacy key if present
    final legacyUrl = prefs.getString(_legacyAiServerUrlKey);
    if (legacyUrl != null && legacyUrl != _defaultAiServerUrl) {
      final canonicalUrl = prefs.getString(_aiServerUrlKey);
      if (canonicalUrl == null) {
        await prefs.setString(_aiServerUrlKey, legacyUrl);
      }
      await prefs.remove(_legacyAiServerUrlKey);
    }

    _aiServerUrl = prefs.getString(_aiServerUrlKey) ?? _defaultAiServerUrl;
    return _aiServerUrl!;
  }

  /// Set server URL
  Future<void> setAiServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiServerUrlKey, url);
    _aiServerUrl = url;
  }

  /// Clear all cached values (call when settings change)
  void clearCache() {
    _omiEnabled = null;
    _aiServerUrl = null;
  }

  /// Reset all features to defaults
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_omiEnabledKey, _defaultOmiEnabled);
    await prefs.setString(_aiServerUrlKey, _defaultAiServerUrl);
    clearCache();
  }
}
