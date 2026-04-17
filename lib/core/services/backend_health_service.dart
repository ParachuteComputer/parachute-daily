import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Connection state enum for server health
enum ServerConnectionState {
  connected,
  connecting,
  networkError,
  serverOffline,
  timeout,
  unknown,
}

/// Outcome of a full end-to-end verification of the configured server,
/// token, and vault binding.
///
/// Distinguishes the cases the user actually needs to act on differently:
/// - [ok]: we hit `/api/health` AND `/api/notes` with the stored auth and
///   both returned 200.
/// - [unreachable]: can't reach the server at all (network/DNS/timeout, or
///   a non-HTTP failure).
/// - [unauthorized]: server replied 401 to health or notes — token missing
///   or rejected.
/// - [wrongVault]: server is reachable and auth is accepted for *something*,
///   but not for the configured vault (403/404 on the vault-scoped path).
/// - [serverError]: server returned 5xx or an otherwise broken response.
enum VerifyResultKind { ok, unreachable, unauthorized, wrongVault, serverError }

/// Typed result of [BackendHealthService.verifyConnection].
class VerifyConnectionResult {
  final VerifyResultKind kind;

  /// HTTP status code of the failing request, if any.
  final int? statusCode;

  /// Raw error message for debugging / snackbar fallback.
  final String? detail;

  /// Vault the verify was scoped to (null = default vault).
  final String? vaultName;

  const VerifyConnectionResult({
    required this.kind,
    this.statusCode,
    this.detail,
    this.vaultName,
  });

  bool get isOk => kind == VerifyResultKind.ok;
}

/// Server health status model
class ServerHealthStatus {
  final bool isHealthy;
  final ServerConnectionState connectionState;
  final String message;
  final String helpText;
  final DateTime timestamp;
  final String? serverVersion;
  final Map<String, dynamic>? additionalInfo;

  /// Whether the server has transcription capability (Parakeet MLX etc.)
  final bool transcriptionAvailable;

  ServerHealthStatus({
    required this.isHealthy,
    required this.connectionState,
    required this.message,
    this.helpText = '',
    DateTime? timestamp,
    this.serverVersion,
    this.additionalInfo,
    this.transcriptionAvailable = false,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ServerHealthStatus.healthy({
    String? version,
    bool transcriptionAvailable = false,
  }) => ServerHealthStatus(
    isHealthy: true,
    connectionState: ServerConnectionState.connected,
    message: 'Connected',
    serverVersion: version,
    transcriptionAvailable: transcriptionAvailable,
  );

  factory ServerHealthStatus.offline() => ServerHealthStatus(
    isHealthy: false,
    connectionState: ServerConnectionState.serverOffline,
    message: 'Server offline',
    helpText: 'Parachute Computer is not responding.',
  );

  factory ServerHealthStatus.networkError(String error) => ServerHealthStatus(
    isHealthy: false,
    connectionState: ServerConnectionState.networkError,
    message: 'Network error',
    helpText: 'Unable to connect. Check your network connection.',
  );

  factory ServerHealthStatus.timeout() => ServerHealthStatus(
    isHealthy: false,
    connectionState: ServerConnectionState.timeout,
    message: 'Connection timeout',
    helpText: 'Server is taking too long to respond.',
  );

  factory ServerHealthStatus.unknown() => ServerHealthStatus(
    isHealthy: false,
    connectionState: ServerConnectionState.unknown,
    message: 'Unknown status',
    helpText: 'Unable to determine server status.',
  );
}

/// Backend health checking service
class BackendHealthService {
  final String baseUrl;
  final String? apiKey;

  /// Optional vault scope — when set, health and verify requests route to
  /// `/vaults/<name>/api/*` so they exercise the path the app actually uses.
  final String? vaultName;
  final Duration timeout;
  final http.Client _client;

  BackendHealthService({
    required this.baseUrl,
    this.apiKey,
    this.vaultName,
    this.timeout = const Duration(seconds: 3),
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> get _authHeaders => {
    if (apiKey != null && apiKey!.isNotEmpty)
      'Authorization': 'Bearer $apiKey',
  };

  /// API path prefix — matches GraphApiService / DailyApiService routing.
  String get _apiPrefix {
    final name = vaultName;
    if (name != null && name.isNotEmpty) {
      return '/vaults/${Uri.encodeComponent(name)}/api';
    }
    return '/api';
  }

  /// Check server health
  Future<ServerHealthStatus> checkHealth() async {
    if (baseUrl.isEmpty) {
      return ServerHealthStatus(
        isHealthy: false,
        connectionState: ServerConnectionState.unknown,
        message: 'No server URL configured',
        helpText: 'Configure a server URL in Settings.',
      );
    }

    try {
      final uri = Uri.parse('$baseUrl$_apiPrefix/health');
      final response = await _client.get(uri, headers: _authHeaders).timeout(timeout);

      if (response.statusCode == 200) {
        String? version;
        bool transcriptionAvailable = false;
        try {
          final data = json.decode(response.body);
          version = data['version']?.toString();
          transcriptionAvailable = data['transcription_available'] == true;
        } catch (_) {
          // Ignore JSON parse errors
        }
        return ServerHealthStatus.healthy(
          version: version,
          transcriptionAvailable: transcriptionAvailable,
        );
      } else {
        return ServerHealthStatus(
          isHealthy: false,
          connectionState: ServerConnectionState.serverOffline,
          message: 'Server error (${response.statusCode})',
          helpText: 'Server returned an error response.',
        );
      }
    } on TimeoutException {
      return ServerHealthStatus.timeout();
    } catch (e) {
      debugPrint('[BackendHealthService] Health check error: $e');
      return ServerHealthStatus.networkError(e.toString());
    }
  }

  /// Verify the configured server, token, and vault binding end-to-end.
  ///
  /// Runs two requests against the same base/auth/vault the rest of the app
  /// uses:
  ///   1. `GET $baseUrl[/vaults/<name>]/api/health`
  ///   2. `GET $baseUrl[/vaults/<name>]/api/notes?limit=1`
  ///
  /// Returns a typed [VerifyConnectionResult] so the UI can distinguish
  /// "server is down" from "your token isn't authorized for this vault" and
  /// tell the user what to actually fix.
  Future<VerifyConnectionResult> verifyConnection() async {
    if (baseUrl.isEmpty) {
      return VerifyConnectionResult(
        kind: VerifyResultKind.unreachable,
        detail: 'No server URL configured',
        vaultName: vaultName,
      );
    }

    // 1. Health. This is the authoritative reachability signal — if we can't
    // hit /health on the configured vault prefix, none of the data routes
    // will work either.
    try {
      final uri = Uri.parse('$baseUrl$_apiPrefix/health');
      final resp = await _client.get(uri, headers: _authHeaders).timeout(timeout);
      final code = resp.statusCode;
      // 403/404 on a vault-scoped path means the server is up but our token
      // isn't accepted for *this* vault (either the vault name is wrong or
      // the token was minted for a different vault). Report wrong_vault so
      // the user gets actionable text — "re-run Connect to Vault against
      // the right vault" — instead of a generic "unauthorized" that suggests
      // their whole token is bad.
      if ((code == 403 || code == 404) &&
          vaultName != null &&
          vaultName!.isNotEmpty) {
        return VerifyConnectionResult(
          kind: VerifyResultKind.wrongVault,
          statusCode: code,
          vaultName: vaultName,
        );
      }
      if (code == 401 || code == 403) {
        return VerifyConnectionResult(
          kind: VerifyResultKind.unauthorized,
          statusCode: code,
          vaultName: vaultName,
        );
      }
      if (code >= 500) {
        return VerifyConnectionResult(
          kind: VerifyResultKind.serverError,
          statusCode: code,
          vaultName: vaultName,
        );
      }
      if (code != 200) {
        return VerifyConnectionResult(
          kind: VerifyResultKind.serverError,
          statusCode: code,
          detail: resp.body.isNotEmpty ? resp.body : null,
          vaultName: vaultName,
        );
      }
    } on TimeoutException {
      return VerifyConnectionResult(
        kind: VerifyResultKind.unreachable,
        detail: 'timeout',
        vaultName: vaultName,
      );
    } catch (e) {
      debugPrint('[BackendHealthService] verify health error: $e');
      return VerifyConnectionResult(
        kind: VerifyResultKind.unreachable,
        detail: e.toString(),
        vaultName: vaultName,
      );
    }

    // 2. Notes probe. Some servers gate /health looser than the data routes
    // (e.g. health is public, notes requires auth), so a successful /health
    // isn't enough to prove the token works end-to-end.
    try {
      final uri = Uri.parse('$baseUrl$_apiPrefix/notes?limit=1');
      final resp = await _client.get(uri, headers: _authHeaders).timeout(timeout);
      final code = resp.statusCode;
      if (code == 200) {
        return VerifyConnectionResult(
          kind: VerifyResultKind.ok,
          statusCode: code,
          vaultName: vaultName,
        );
      }
      // See comment above: 403/404 on a vault-scoped path means wrong vault,
      // not wrong token.
      if ((code == 403 || code == 404) &&
          vaultName != null &&
          vaultName!.isNotEmpty) {
        return VerifyConnectionResult(
          kind: VerifyResultKind.wrongVault,
          statusCode: code,
          vaultName: vaultName,
        );
      }
      if (code == 401 || code == 403) {
        return VerifyConnectionResult(
          kind: VerifyResultKind.unauthorized,
          statusCode: code,
          vaultName: vaultName,
        );
      }
      if (code >= 500) {
        return VerifyConnectionResult(
          kind: VerifyResultKind.serverError,
          statusCode: code,
          vaultName: vaultName,
        );
      }
      return VerifyConnectionResult(
        kind: VerifyResultKind.serverError,
        statusCode: code,
        detail: resp.body.isNotEmpty ? resp.body : null,
        vaultName: vaultName,
      );
    } on TimeoutException {
      return VerifyConnectionResult(
        kind: VerifyResultKind.unreachable,
        detail: 'timeout on /notes',
        vaultName: vaultName,
      );
    } catch (e) {
      debugPrint('[BackendHealthService] verify notes error: $e');
      return VerifyConnectionResult(
        kind: VerifyResultKind.unreachable,
        detail: e.toString(),
        vaultName: vaultName,
      );
    }
  }

  /// Dispose resources
  void dispose() {
    _client.close();
  }
}
