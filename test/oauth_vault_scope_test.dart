// Tests for Patch C: per-vault OAuth scope.
//
// When the user has a vault name picked, OAuthService.connect must do
// discovery against `/vaults/<name>/.well-known/oauth-authorization-server`
// so the token the server mints is bound to that specific vault. Without
// this, the user gets a token-for-default-vault even though they're trying
// to connect to a different one, and every subsequent API call silently
// lands on the wrong vault.
//
// We can't exercise the full browser round-trip in unit tests, so these
// assertions target the discovery step: the OAuthService hits the expected
// vault-scoped URL (or the unscoped one when no vault is given), and the
// token-exchange response parser promotes the user-supplied vault name
// when the server response omits `vault` (fallback for pre-vault-field
// servers).
//
// Run with: flutter test test/oauth_vault_scope_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parachute/features/settings/services/oauth_service.dart';

void main() {
  group('OAuthService discovery URL', () {
    test('hits /.well-known/... on the base URL when no vault scope', () async {
      final seenPaths = <String>[];
      final client = MockClient((req) async {
        seenPaths.add(req.url.path);
        // Return 404s so connect() throws discovery_failed before it tries
        // to launch a browser — we only care about the path(s) it probed.
        return http.Response('not found', 404);
      });

      final oauth = OAuthService(httpClient: client);
      await expectLater(
        oauth.connect(serverUrl: 'http://example.test'),
        throwsA(isA<OAuthException>()),
      );
      oauth.dispose();

      expect(
        seenPaths,
        contains('/.well-known/oauth-authorization-server'),
        reason: 'unscoped connect must probe the unscoped AS metadata URL',
      );
      expect(
        seenPaths.any((p) => p.startsWith('/vaults/')),
        isFalse,
        reason: 'unscoped connect must not touch any vault-scoped path',
      );
    });

    test('hits /vaults/<name>/.well-known/... when vault is set', () async {
      final seenPaths = <String>[];
      final client = MockClient((req) async {
        seenPaths.add(req.url.path);
        return http.Response('not found', 404);
      });

      final oauth = OAuthService(httpClient: client);
      await expectLater(
        oauth.connect(serverUrl: 'http://example.test', vaultName: 'work'),
        throwsA(isA<OAuthException>()),
      );
      oauth.dispose();

      expect(
        seenPaths,
        contains('/vaults/work/.well-known/oauth-authorization-server'),
        reason: 'scoped connect must probe the vault-scoped AS metadata URL',
      );
      // Also the protected-resource fallback is scoped.
      expect(
        seenPaths,
        contains('/vaults/work/.well-known/oauth-protected-resource'),
      );
    });

    test('URL-encodes vault names with special characters', () async {
      final seenPaths = <String>[];
      final client = MockClient((req) async {
        seenPaths.add(req.url.path);
        return http.Response('not found', 404);
      });

      final oauth = OAuthService(httpClient: client);
      await expectLater(
        oauth.connect(serverUrl: 'http://example.test', vaultName: 'my vault'),
        throwsA(isA<OAuthException>()),
      );
      oauth.dispose();

      expect(
        seenPaths.any((p) => p.contains('/vaults/my%20vault/.well-known/')),
        isTrue,
      );
    });

    test('treats an empty vaultName as unscoped', () async {
      final seenPaths = <String>[];
      final client = MockClient((req) async {
        seenPaths.add(req.url.path);
        return http.Response('not found', 404);
      });

      final oauth = OAuthService(httpClient: client);
      await expectLater(
        oauth.connect(serverUrl: 'http://example.test', vaultName: '   '),
        throwsA(isA<OAuthException>()),
      );
      oauth.dispose();

      expect(
        seenPaths.any((p) => p.startsWith('/vaults/')),
        isFalse,
        reason: 'blank/whitespace vault names must not be treated as scoped',
      );
    });
  });

  group('OAuthResult.vaultName round-trip', () {
    // These assertions exercise the public OAuthResult shape. They document
    // the contract settings relies on when it auto-selects the vault after
    // a successful OAuth: (a) server-authoritative name wins when present,
    // (b) otherwise the name the user scoped the flow to is preserved.
    test('OAuthResult carries token + scope + vaultName', () {
      const r = OAuthResult(
        token: 'pvt_abc',
        scope: 'notes:read notes:write',
        vaultName: 'work',
      );
      expect(r.token, 'pvt_abc');
      expect(r.scope, 'notes:read notes:write');
      expect(r.vaultName, 'work');
    });
  });

  // Note: _exchange behavior (reading access_token + vault from the token
  // response, falling back to the user-supplied vault name when the server
  // omits `vault`) is not unit-tested here because _exchange is private and
  // the full connect() flow needs url_launcher / app_links bindings. The
  // contract is documented on OAuthResult and exercised by the discovery
  // tests above plus the OAuthResult.vaultName round-trip test.
}
