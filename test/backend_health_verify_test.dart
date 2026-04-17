// Tests for BackendHealthService.verifyConnection — the typed end-to-end
// probe that Settings' "Test Connection" button calls.
//
// The bug we're guarding against: the old "Test Connection" hit `/api/health`
// on the unscoped base URL without auth and reported success even when the
// stored token was invalid for the configured vault. Users then tried to
// capture a note and hit silent failures. verifyConnection must:
//
//   - route through the vault-scoped prefix when a vault is set,
//   - try BOTH /health and /notes with the stored auth,
//   - and return a typed result so the UI can say "your token isn't
//     authorized for vault X" instead of a generic failure.
//
// Run with: flutter test test/backend_health_verify_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parachute/core/services/backend_health_service.dart';

void main() {
  group('verifyConnection', () {
    test('returns ok when both health and notes return 200', () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add(req.url.path);
        return http.Response('{}', 200);
      });
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        apiKey: 'para_test',
        client: client,
      );
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.ok);
      expect(calls, containsAll(['/api/health', '/api/notes']));
    });

    test('routes through /vaults/<name>/api when vault is set', () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add(req.url.path);
        return http.Response('{}', 200);
      });
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        apiKey: 'para_test',
        vaultName: 'work',
        client: client,
      );
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.ok);
      expect(calls, ['/vaults/work/api/health', '/vaults/work/api/notes']);
    });

    test('sends Authorization header when apiKey is set', () async {
      String? observedAuth;
      final client = MockClient((req) async {
        observedAuth = req.headers['Authorization'];
        return http.Response('{}', 200);
      });
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        apiKey: 'para_abc',
        client: client,
      );
      await svc.verifyConnection();
      expect(observedAuth, 'Bearer para_abc');
    });

    test('maps 401 on health to unauthorized', () async {
      final client = MockClient((_) async => http.Response('nope', 401));
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        apiKey: 'bad',
        client: client,
      );
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.unauthorized);
      expect(result.statusCode, 401);
    });

    test('maps 404 on vault-scoped health to wrongVault', () async {
      final client = MockClient((_) async => http.Response('no such vault', 404));
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        apiKey: 'para_x',
        vaultName: 'ghost',
        client: client,
      );
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.wrongVault);
      expect(result.vaultName, 'ghost');
    });

    test('maps 403 on vault-scoped health to wrongVault', () async {
      // A token that authenticates cleanly against the server but is not
      // authorized for this specific vault is a wrong-vault problem, not a
      // wrong-token problem. The user should re-run Connect to Vault with
      // the right vault selected, not swap out their credential.
      final client = MockClient((_) async => http.Response('forbidden', 403));
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        apiKey: 'para_default_vault_token',
        vaultName: 'work',
        client: client,
      );
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.wrongVault);
      expect(result.statusCode, 403);
      expect(result.vaultName, 'work');
    });

    test('403 without a vault set still maps to unauthorized', () async {
      // With no vault scope, 403 means the token itself is rejected — there
      // is no "wrong vault" to suggest.
      final client = MockClient((_) async => http.Response('forbidden', 403));
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        apiKey: 'para_bad',
        client: client,
      );
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.unauthorized);
      expect(result.statusCode, 403);
    });

    test('maps 401 on notes (after healthy /health) to unauthorized', () async {
      // Regression: server where /health is public but data routes require
      // auth. verifyConnection must probe both; otherwise Test Connection
      // lies about the stored token being valid.
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/health')) return http.Response('{}', 200);
        return http.Response('bad token', 401);
      });
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        apiKey: 'stale_token',
        client: client,
      );
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.unauthorized);
    });

    test('maps 500 to serverError', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        client: client,
      );
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.serverError);
      expect(result.statusCode, 500);
    });

    test('maps network failure to unreachable', () async {
      final client = MockClient((_) async {
        throw http.ClientException('connection refused');
      });
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        client: client,
      );
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.unreachable);
    });

    test('returns unreachable when baseUrl is empty', () async {
      final svc = BackendHealthService(baseUrl: '');
      final result = await svc.verifyConnection();
      expect(result.kind, VerifyResultKind.unreachable);
    });
  });

  group('checkHealth (vault routing)', () {
    test('hits /vaults/<name>/api/health when vault is set', () async {
      String? observedPath;
      final client = MockClient((req) async {
        observedPath = req.url.path;
        return http.Response('{"version": "1.2.3"}', 200);
      });
      final svc = BackendHealthService(
        baseUrl: 'http://example.test',
        vaultName: 'personal',
        client: client,
      );
      final status = await svc.checkHealth();
      expect(observedPath, '/vaults/personal/api/health');
      expect(status.isHealthy, isTrue);
      expect(status.serverVersion, '1.2.3');
    });
  });
}
