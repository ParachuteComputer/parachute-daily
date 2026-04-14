import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Result of a successful OAuth flow.
class OAuthResult {
  final String token;
  final String? scope;
  final String? vaultName;

  const OAuthResult({required this.token, this.scope, this.vaultName});
}

/// Raised when the user cancels the flow, the server rejects auth,
/// or discovery/registration/token exchange fails.
class OAuthException implements Exception {
  final String message;
  final String? code;
  OAuthException(this.message, {this.code});

  @override
  String toString() => code == null ? 'OAuthException: $message' : 'OAuthException($code): $message';
}

/// OAuth 2.1 + PKCE client for Parachute Vault.
///
/// Implements just enough of OAuth for the connect-to-vault flow:
///   1. Discover endpoints via `/.well-known/oauth-authorization-server`
///   2. Dynamic client registration (RFC 7591)
///   3. Launch the browser to the authorization endpoint
///   4. Receive the redirect via the app's `parachute://oauth/callback` deep link
///   5. Exchange the code for a token at the token endpoint
///
/// The returned token is a standard `pvt_` vault token — identical to manually
/// created API keys, and stored the same way.
class OAuthService {
  static const String redirectUri = 'parachute://oauth/callback';
  static const String clientName = 'Parachute Daily';

  final http.Client _http;
  final AppLinks _appLinks;

  OAuthService({http.Client? httpClient, AppLinks? appLinks})
      : _http = httpClient ?? http.Client(),
        _appLinks = appLinks ?? AppLinks();

  /// Run the full OAuth flow. Returns the resulting token on success.
  /// Throws [OAuthException] if cancelled, timed out, or rejected.
  ///
  /// [serverUrl] is the vault base URL (e.g. `https://parachute.example.ts.net`).
  /// [timeout] applies to the whole browser + redirect window.
  Future<OAuthResult> connect({
    required String serverUrl,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final normalizedUrl = _normalizeServerUrl(serverUrl);

    // 1. Discovery
    final discovery = await _discover(normalizedUrl);

    // 2. Dynamic client registration
    final clientId = await _register(discovery.registrationEndpoint);

    // 3. PKCE
    final verifier = _generateCodeVerifier();
    final challenge = _codeChallenge(verifier);
    final state = _randomString(32);

    // 4. Start listening for the redirect BEFORE launching the browser,
    //    so we don't miss a fast callback.
    final callbackFuture = _waitForCallback(state: state, timeout: timeout);

    // 5. Launch browser
    final authUri = Uri.parse(discovery.authorizationEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      },
    );
    final launched = await launchUrl(authUri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw OAuthException('Could not open browser for authorization', code: 'launch_failed');
    }

    // 6. Await the redirect
    final callback = await callbackFuture;

    if (callback.error != null) {
      throw OAuthException(
        callback.errorDescription ?? callback.error!,
        code: callback.error,
      );
    }
    final code = callback.code;
    if (code == null) {
      throw OAuthException('Authorization callback missing code', code: 'invalid_response');
    }

    // 7. Exchange code for token
    return await _exchange(
      tokenEndpoint: discovery.tokenEndpoint,
      code: code,
      verifier: verifier,
      clientId: clientId,
    );
  }

  Future<_Discovery> _discover(String serverUrl) async {
    // Try RFC 8414 authorization-server metadata first.
    final authServerUrl = Uri.parse('$serverUrl/.well-known/oauth-authorization-server');
    try {
      final resp = await _http.get(authServerUrl).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final auth = data['authorization_endpoint'] as String?;
        final token = data['token_endpoint'] as String?;
        final reg = data['registration_endpoint'] as String?;
        if (auth != null && token != null && reg != null) {
          return _Discovery(
            authorizationEndpoint: auth,
            tokenEndpoint: token,
            registrationEndpoint: reg,
          );
        }
      }
    } catch (e) {
      debugPrint('[OAuth] authorization-server discovery failed: $e');
    }

    // Fallback: protected-resource discovery points at an authorization server.
    final prUrl = Uri.parse('$serverUrl/.well-known/oauth-protected-resource');
    try {
      final resp = await _http.get(prUrl).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final authServers = (data['authorization_servers'] as List?)?.cast<String>();
        if (authServers != null && authServers.isNotEmpty) {
          // Recurse once using the first advertised AS.
          return await _discover(authServers.first.replaceAll(RegExp(r'/$'), ''));
        }
      }
    } catch (e) {
      debugPrint('[OAuth] protected-resource discovery failed: $e');
    }

    throw OAuthException(
      'Server does not advertise OAuth metadata. Is this a Parachute Vault?',
      code: 'discovery_failed',
    );
  }

  Future<String> _register(String registrationEndpoint) async {
    final resp = await _http.post(
      Uri.parse(registrationEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'client_name': clientName,
        'redirect_uris': [redirectUri],
        'token_endpoint_auth_method': 'none',
        'grant_types': ['authorization_code'],
        'response_types': ['code'],
      }),
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw OAuthException(
        'Client registration failed (${resp.statusCode}): ${resp.body}',
        code: 'registration_failed',
      );
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final clientId = data['client_id'] as String?;
    if (clientId == null) {
      throw OAuthException('Registration response missing client_id', code: 'registration_failed');
    }
    return clientId;
  }

  Future<OAuthResult> _exchange({
    required String tokenEndpoint,
    required String code,
    required String verifier,
    required String clientId,
  }) async {
    final resp = await _http.post(
      Uri.parse(tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': clientId,
        'code_verifier': verifier,
      },
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      String message = 'Token exchange failed (${resp.statusCode})';
      try {
        final err = json.decode(resp.body) as Map<String, dynamic>;
        final desc = err['error_description'] ?? err['error'];
        if (desc != null) message = desc.toString();
      } catch (_) {}
      throw OAuthException(message, code: 'token_exchange_failed');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    if (token == null) {
      throw OAuthException('Token response missing access_token', code: 'token_exchange_failed');
    }
    return OAuthResult(
      token: token,
      scope: data['scope'] as String?,
      vaultName: data['vault'] as String? ?? data['vault_name'] as String?,
    );
  }

  /// Listen for a `parachute://oauth/callback?...` deep link.
  Future<_CallbackParams> _waitForCallback({
    required String state,
    required Duration timeout,
  }) async {
    final completer = Completer<_CallbackParams>();
    StreamSubscription<Uri>? sub;
    Timer? timer;

    void finish(_CallbackParams params) {
      if (completer.isCompleted) return;
      sub?.cancel();
      timer?.cancel();
      completer.complete(params);
    }

    void fail(Object error) {
      if (completer.isCompleted) return;
      sub?.cancel();
      timer?.cancel();
      completer.completeError(error);
    }

    sub = _appLinks.uriLinkStream.listen(
      (uri) {
        if (uri.scheme != 'parachute' || uri.host != 'oauth') return;
        if (!uri.path.startsWith('/callback')) return;

        final params = uri.queryParameters;
        final returnedState = params['state'];
        if (returnedState != state) {
          fail(OAuthException('State mismatch in OAuth callback', code: 'state_mismatch'));
          return;
        }
        finish(_CallbackParams(
          code: params['code'],
          error: params['error'],
          errorDescription: params['error_description'],
        ));
      },
      onError: (e) => fail(OAuthException('Deep link error: $e', code: 'deep_link_error')),
    );

    timer = Timer(timeout, () {
      fail(OAuthException('Timed out waiting for authorization', code: 'timeout'));
    });

    return completer.future;
  }

  String _normalizeServerUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) throw OAuthException('Server URL is empty', code: 'invalid_url');
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  // PKCE helpers.
  String _generateCodeVerifier() => _randomString(64);

  String _codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  String _randomString(int length) {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = Random.secure();
    return List.generate(length, (_) => charset[rng.nextInt(charset.length)]).join();
  }

  void dispose() {
    _http.close();
  }
}

class _Discovery {
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String registrationEndpoint;
  _Discovery({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.registrationEndpoint,
  });
}

class _CallbackParams {
  final String? code;
  final String? error;
  final String? errorDescription;
  _CallbackParams({this.code, this.error, this.errorDescription});
}
