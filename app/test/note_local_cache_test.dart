/// Tests for NoteLocalCache sync_state logic.
///
/// These tests verify the SQL patterns used by NoteLocalCache directly
/// against an in-memory SQLite database, without needing path_provider
/// or the Flutter test environment's native library setup.
///
/// Run with: flutter test test/note_local_cache_test.dart
/// Note: Requires sqlite3 native libraries. On macOS, these are available
/// via sqlite3_flutter_libs. If tests hang on "loading", run via
/// integration_test/ instead.
@TestOn('mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('NoteLocalCache sync_state logic', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
      db.execute('''
        CREATE TABLE notes (
          id TEXT PRIMARY KEY, content TEXT NOT NULL DEFAULT '',
          path TEXT, created_at TEXT NOT NULL, updated_at TEXT,
          tags_json TEXT NOT NULL DEFAULT '[]', sync_state TEXT DEFAULT 'synced'
        )
      ''');
      db.execute('''
        CREATE TABLE attachments (
          id TEXT PRIMARY KEY, note_id TEXT NOT NULL,
          path TEXT NOT NULL, mime_type TEXT
        )
      ''');
    });

    tearDown(() => db.dispose());

    void insertNote(String id, {
      String syncState = 'synced',
      String content = 'hello',
      String tags = '["daily"]',
    }) {
      db.execute(
        "INSERT INTO notes (id, content, created_at, tags_json, sync_state) "
        "VALUES (?, ?, ?, ?, ?)",
        [id, content, '2026-04-01T12:00:00.000Z', tags, syncState],
      );
    }

    String? getSyncState(String id) {
      final rows = db.select('SELECT sync_state FROM notes WHERE id = ?', [id]);
      if (rows.isEmpty) return null;
      return rows.first['sync_state'] as String?;
    }

    String? getContent(String id) {
      final rows = db.select('SELECT content FROM notes WHERE id = ?', [id]);
      if (rows.isEmpty) return null;
      return rows.first['content'] as String?;
    }

    // The UPSERT SQL used by NoteLocalCache.putNotes
    void upsert(String id, String content, String tags) {
      final stmt = db.prepare(
        'INSERT INTO notes (id, content, created_at, tags_json, sync_state) '
        "VALUES (?, ?, ?, ?, 'synced') "
        'ON CONFLICT(id) DO UPDATE SET '
        "  content = CASE WHEN sync_state IN ('pending_edit', 'pending_create') "
        "    THEN content ELSE excluded.content END, "
        '  created_at = excluded.created_at, '
        "  sync_state = CASE WHEN sync_state IN "
        "    ('pending_delete', 'pending_edit', 'pending_create') "
        "    THEN sync_state ELSE 'synced' END",
      );
      stmt.execute([id, content, '2026-04-01T12:00:00.000Z', tags]);
      stmt.dispose();
    }

    test('upsert preserves pending_delete sync_state', () {
      insertNote('n1', syncState: 'pending_delete');
      upsert('n1', 'server content', '["daily"]');

      expect(getSyncState('n1'), 'pending_delete');
    });

    test('upsert preserves pending_edit content and sync_state', () {
      insertNote('n1', syncState: 'pending_edit', content: 'local edit');
      upsert('n1', 'server content', '["daily"]');

      expect(getSyncState('n1'), 'pending_edit');
      expect(getContent('n1'), 'local edit');
    });

    test('upsert preserves pending_create content and sync_state', () {
      insertNote('n1', syncState: 'pending_create', content: 'offline note');
      upsert('n1', 'server content', '["daily"]');

      expect(getSyncState('n1'), 'pending_create');
      expect(getContent('n1'), 'offline note');
    });

    test('upsert resets synced notes with new content', () {
      insertNote('n1', syncState: 'synced', content: 'old');
      upsert('n1', 'new server content', '["daily"]');

      expect(getSyncState('n1'), 'synced');
      expect(getContent('n1'), 'new server content');
    });

    test('pending_delete notes excluded from date queries', () {
      insertNote('n1', syncState: 'synced');
      insertNote('n2', syncState: 'pending_delete');
      insertNote('n3', syncState: 'pending_edit');
      insertNote('n4', syncState: 'pending_create');

      final rows = db.select(
        "SELECT id FROM notes "
        "WHERE COALESCE(sync_state, 'synced') != 'pending_delete' ORDER BY id",
      );
      final ids = rows.map((r) => r['id'] as String).toList();

      expect(ids, ['n1', 'n3', 'n4']);
    });

    test('markForEdit updates content and sets sync_state', () {
      insertNote('n1', content: 'original');

      db.execute(
        "UPDATE notes SET content = ?, sync_state = 'pending_edit' WHERE id = ?",
        ['edited', 'n1'],
      );

      expect(getSyncState('n1'), 'pending_edit');
      expect(getContent('n1'), 'edited');
    });

    test('markSynced clears pending state with server content', () {
      insertNote('n1', syncState: 'pending_edit', content: 'local');

      db.execute(
        "UPDATE notes SET content = COALESCE(?, content), sync_state = 'synced' WHERE id = ?",
        ['server authoritative', 'n1'],
      );

      expect(getSyncState('n1'), 'synced');
      expect(getContent('n1'), 'server authoritative');
    });

    test('markSynced with null content preserves existing', () {
      insertNote('n1', syncState: 'pending_edit', content: 'keep this');

      db.execute(
        "UPDATE notes SET content = COALESCE(?, content), sync_state = 'synced' WHERE id = ?",
        [null, 'n1'],
      );

      expect(getSyncState('n1'), 'synced');
      expect(getContent('n1'), 'keep this');
    });

    test('removeStaleNotes only removes synced notes not in server set', () {
      insertNote('n1', syncState: 'synced');
      insertNote('n2', syncState: 'synced');
      insertNote('n3', syncState: 'pending_edit');
      insertNote('n4', syncState: 'pending_delete');

      db.execute(
        "DELETE FROM notes WHERE created_at >= ? AND created_at < ? "
        "AND COALESCE(sync_state, 'synced') = 'synced' AND id NOT IN (?)",
        ['2026-04-01T00:00:00.000Z', '2026-04-02T00:00:00.000Z', 'n2'],
      );

      final ids = db.select('SELECT id FROM notes ORDER BY id')
          .map((r) => r['id'] as String).toList();
      expect(ids, ['n2', 'n3', 'n4']);
    });

    test('tag filter matches exact and sub-tags', () {
      db.execute(
        "INSERT INTO notes (id, content, created_at, tags_json, sync_state) "
        "VALUES ('n1', 'doc', '2026-04-01T12:00:00.000Z', '[\"doc\"]', 'synced')",
      );
      db.execute(
        "INSERT INTO notes (id, content, created_at, tags_json, sync_state) "
        "VALUES ('n2', 'meeting', '2026-04-01T12:00:00.000Z', '[\"doc/meeting\"]', 'synced')",
      );
      db.execute(
        "INSERT INTO notes (id, content, created_at, tags_json, sync_state) "
        "VALUES ('n3', 'daily', '2026-04-01T12:00:00.000Z', '[\"daily\"]', 'synced')",
      );

      final rows = db.select(
        "SELECT id FROM notes WHERE "
        "(tags_json LIKE ? OR tags_json LIKE ?) ORDER BY id",
        ['%"doc"%', '%"doc/%'],
      );
      final ids = rows.map((r) => r['id'] as String).toList();

      expect(ids, ['n1', 'n2']);
    });

    test('excludeTag filter works', () {
      db.execute(
        "INSERT INTO notes (id, content, created_at, tags_json, sync_state) "
        "VALUES ('n1', 'active', '2026-04-01T12:00:00.000Z', '[\"digest\"]', 'synced')",
      );
      db.execute(
        "INSERT INTO notes (id, content, created_at, tags_json, sync_state) "
        "VALUES ('n2', 'archived', '2026-04-01T12:00:00.000Z', '[\"digest\",\"archived\"]', 'synced')",
      );

      final rows = db.select(
        "SELECT id FROM notes WHERE "
        "(tags_json LIKE ? OR tags_json LIKE ?) AND tags_json NOT LIKE ? ORDER BY id",
        ['%"digest"%', '%"digest/%', '%"archived"%'],
      );
      final ids = rows.map((r) => r['id'] as String).toList();

      expect(ids, ['n1']);
    });

    test('getPendingCount counts all pending states', () {
      insertNote('n1', syncState: 'synced');
      insertNote('n2', syncState: 'pending_create');
      insertNote('n3', syncState: 'pending_edit');
      insertNote('n4', syncState: 'pending_delete');

      final rows = db.select(
        "SELECT COUNT(*) as c FROM notes "
        "WHERE sync_state IN ('pending_create', 'pending_edit', 'pending_delete')",
      );
      expect(rows.first['c'], 3);
    });

    test('attachment CRUD', () {
      insertNote('n1');
      db.execute(
        'INSERT INTO attachments (id, note_id, path, mime_type) '
        "VALUES ('att1', 'n1', 'audio/recording.wav', 'audio/wav')",
      );

      final rows = db.select(
        "SELECT path FROM attachments WHERE note_id = ? AND mime_type LIKE 'audio/%' LIMIT 1",
        ['n1'],
      );
      expect(rows.first['path'], 'audio/recording.wav');

      db.execute('DELETE FROM attachments WHERE note_id = ?', ['n1']);
      final after = db.select('SELECT * FROM attachments WHERE note_id = ?', ['n1']);
      expect(after.isEmpty, true);
    });
  });
}
