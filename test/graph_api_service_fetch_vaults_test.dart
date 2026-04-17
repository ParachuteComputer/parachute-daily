// Tests for GraphApiService.fetchVaults — specifically that we accept both
// shapes the vault server has returned for the unauth'd vault list:
//
//   - legacy/bare:  `[{ "name": "default" }, { "name": "work" }]`
//   - current:      `{ "vaults": [{ "name": "default" }, ...] }`
//
// Regression coverage for T-6 OAuth launch: a shape mismatch here silently
// blanks the vault picker and makes the "Connected to <vault>" snackbar lie
// because the client can't confirm which vault the token minted against.
//
// Run with: flutter test test/graph_api_service_fetch_vaults_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parachute/core/services/graph_api_service.dart';

void main() {
  group('GraphApiService.fetchVaults', () {
    test('accepts a bare JSON array of {name: ...}', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/vaults');
        return http.Response(
          jsonEncode([
            {'name': 'default'},
            {'name': 'work'},
          ]),
          200,
        );
      });

      final api = GraphApiService(baseUrl: 'http://example.test', client: client);
      final vaults = await api.fetchVaults();
      expect(vaults, ['default', 'work']);
    });

    test('accepts {vaults: [...]} wrapper (current server shape)', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'vaults': [
              {'name': 'default'},
              {'name': 'personal'},
            ],
          }),
          200,
        );
      });

      final api = GraphApiService(baseUrl: 'http://example.test', client: client);
      final vaults = await api.fetchVaults();
      expect(vaults, ['default', 'personal']);
    });

    test('accepts a bare list of strings', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode(['alpha', 'beta']),
            200,
          ));
      final api = GraphApiService(baseUrl: 'http://example.test', client: client);
      expect(await api.fetchVaults(), ['alpha', 'beta']);
    });

    test('returns null on unrecognized shape', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'not_vaults': 'oops'}),
            200,
          ));
      final api = GraphApiService(baseUrl: 'http://example.test', client: client);
      expect(await api.fetchVaults(), isNull);
    });

    test('returns null on non-200', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      final api = GraphApiService(baseUrl: 'http://example.test', client: client);
      expect(await api.fetchVaults(), isNull);
    });
  });

  group('GraphApiService vault path encoding', () {
    // Regression: previously the api prefix interpolated vaultName raw, so a
    // vault named "my vault" produced `/vaults/my vault/api/...` and every
    // note read/write got a malformed URL. Match the encoding done in
    // BackendHealthService and OAuthService.
    test('encodes vault names with spaces', () async {
      String? observedPath;
      final client = MockClient((req) async {
        observedPath = req.url.path;
        return http.Response(jsonEncode([]), 200);
      });
      final api = GraphApiService(
        baseUrl: 'http://example.test',
        vaultName: 'my vault',
        client: client,
      );
      await api.queryNotes(tag: 'captured');
      expect(observedPath, startsWith('/vaults/my%20vault/api/'));
    });

    test('encodes vault names with plus signs', () async {
      String? observedPath;
      final client = MockClient((req) async {
        observedPath = req.url.path;
        return http.Response(jsonEncode([]), 200);
      });
      final api = GraphApiService(
        baseUrl: 'http://example.test',
        vaultName: 'a+b',
        client: client,
      );
      await api.queryNotes(tag: 'captured');
      // Uri.encodeComponent turns `+` into `%2B`.
      expect(observedPath, startsWith('/vaults/a%2Bb/api/'));
    });

    test('encodes vault names with percent signs', () async {
      String? observedPath;
      final client = MockClient((req) async {
        observedPath = req.url.path;
        return http.Response(jsonEncode([]), 200);
      });
      final api = GraphApiService(
        baseUrl: 'http://example.test',
        vaultName: '50%off',
        client: client,
      );
      await api.queryNotes(tag: 'captured');
      expect(observedPath, startsWith('/vaults/50%25off/api/'));
    });

    test('leaves safe vault names untouched', () async {
      String? observedPath;
      final client = MockClient((req) async {
        observedPath = req.url.path;
        return http.Response(jsonEncode([]), 200);
      });
      final api = GraphApiService(
        baseUrl: 'http://example.test',
        vaultName: 'work',
        client: client,
      );
      await api.queryNotes(tag: 'captured');
      expect(observedPath, startsWith('/vaults/work/api/'));
    });
  });
}
