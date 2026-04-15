// Tests for server-bound timestamp serialization. Regression coverage for a
// bug where voice entries landed in the vault with `createdAt` shifted by the
// user's timezone offset: the app sent a local `DateTime.toIso8601String()`
// (no `Z` or offset suffix) and the server treated the bare timestamp as UTC.
//
// Run with: flutter test test/daily_api_service_timestamp_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parachute/features/daily/journal/services/daily_api_service.dart';

void main() {
  group('formatCreatedAt', () {
    test('emits a Z-suffixed UTC ISO string for a UTC DateTime', () {
      final utc = DateTime.utc(2026, 4, 15, 16, 30, 0);
      expect(formatCreatedAt(utc), '2026-04-15T16:30:00.000Z');
    });

    test('converts a local DateTime to the same instant in UTC', () {
      // Build a local wall-clock time, then check the serialized value
      // represents the same instant (not the same wall-clock digits).
      final local = DateTime(2026, 4, 15, 10, 30, 0);
      final serialized = formatCreatedAt(local);

      expect(serialized.endsWith('Z'), isTrue,
          reason: 'server-bound timestamps must be Z-suffixed');

      final parsed = DateTime.parse(serialized);
      expect(parsed.isUtc, isTrue);
      expect(parsed.millisecondsSinceEpoch,
          local.millisecondsSinceEpoch,
          reason: 'conversion must preserve the instant');
    });

    test('is idempotent for already-UTC input', () {
      final utc = DateTime.utc(2026, 4, 15, 16, 30, 0);
      expect(formatCreatedAt(utc), formatCreatedAt(utc.toUtc()));
    });

    test('regression: bare local toIso8601String would NOT be Z-suffixed', () {
      // Documents the bug this helper guards against: the raw
      // `toIso8601String()` on a local DateTime produces a bare timestamp
      // (no `Z`, no offset), which the vault server misinterprets as UTC.
      final local = DateTime(2026, 4, 15, 10, 30, 0);
      expect(local.toIso8601String().endsWith('Z'), isFalse);
      // The helper always produces a Z-suffixed value.
      expect(formatCreatedAt(local).endsWith('Z'), isTrue);
    });
  });
}
