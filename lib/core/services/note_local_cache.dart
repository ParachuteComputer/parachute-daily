import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../models/thing.dart';

/// SQLite cache for notes — offline fallback when server unreachable.
///
/// Stores Note objects directly, matching the v3 server schema.
/// Server is the source of truth. This cache is populated on every
/// successful server fetch and read when the server is unavailable.
///
/// [sync_state] column tracks offline mutations:
///   - `synced`         — matches server (default)
///   - `pending_create` — created offline, server POST queued
///   - `pending_edit`   — edited locally, server PATCH queued
///   - `pending_delete` — deleted locally, server DELETE queued
class NoteLocalCache {
  final Database _db;

  NoteLocalCache._(this._db);

  /// Open (or create) the cache database in the app documents directory.
  static Future<NoteLocalCache> open() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, 'parachute_notes_cache.db');
      final db = sqlite3.open(path);
      final cache = NoteLocalCache._(db);
      cache._ensureSchema();
      debugPrint('[NoteLocalCache] opened: $path');
      return cache;
    } catch (e) {
      debugPrint('[NoteLocalCache] failed to open, using in-memory fallback: $e');
      final db = sqlite3.openInMemory();
      final cache = NoteLocalCache._(db);
      cache._ensureSchema();
      return cache;
    }
  }

  void _ensureSchema() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id          TEXT PRIMARY KEY,
        content     TEXT NOT NULL DEFAULT '',
        path        TEXT,
        created_at  TEXT NOT NULL,
        updated_at  TEXT,
        tags_json   TEXT NOT NULL DEFAULT '[]',
        sync_state  TEXT DEFAULT 'synced'
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id        TEXT PRIMARY KEY,
        note_id   TEXT NOT NULL,
        path      TEXT NOT NULL,
        mime_type TEXT,
        FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_created ON notes(created_at)',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_note ON attachments(note_id)',
    );
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Return all visible notes for a date range, oldest first.
  ///
  /// Excludes pending_delete notes. Includes pending_create and pending_edit.
  /// When [tags] is provided, only returns notes matching at least one of those tags.
  List<Note> getNotesForDate(String dateFrom, String dateTo, {List<String>? tags}) {
    try {
      final conditions = <String>[
        "created_at >= ?",
        "created_at < ?",
        "COALESCE(sync_state, 'synced') != 'pending_delete'",
      ];
      // Convert local date boundaries to UTC so the query matches the user's
      // actual day (cache stores timestamps in UTC).
      final params = <Object>[
        DateTime.parse(dateFrom).toUtc().toIso8601String(),
        DateTime.parse(dateTo).toUtc().toIso8601String(),
      ];

      if (tags != null && tags.isNotEmpty) {
        final tagClauses = tags.map((_) => "tags_json LIKE ?").join(' OR ');
        conditions.add("($tagClauses)");
        for (final tag in tags) {
          params.add('%"$tag"%');
        }
      }

      final rows = _db.select(
        "SELECT * FROM notes WHERE ${conditions.join(' AND ')} ORDER BY created_at ASC",
        params,
      );
      return rows.map(_rowToNote).toList();
    } catch (e) {
      debugPrint('[NoteLocalCache] getNotesForDate error: $e');
      return [];
    }
  }

  /// Return all visible notes with a given tag (for Digest/Docs offline).
  ///
  /// Uses JSON pattern matching in SQL to avoid full table scan.
  /// Matches exact tag and sub-tags (e.g., "doc" matches "doc" and "doc/meeting").
  List<Note> getNotesWithTag(String tag, {String? excludeTag}) {
    try {
      // Match exact tag: "tag" appears in JSON array as "tag" or "tag/..."
      final conditions = <String>[
        "COALESCE(sync_state, 'synced') != 'pending_delete'",
        "(tags_json LIKE ? OR tags_json LIKE ?)",
      ];
      final params = <Object>[
        '%"$tag"%',
        '%"$tag/%',
      ];
      if (excludeTag != null) {
        conditions.add("tags_json NOT LIKE ?");
        params.add('%"$excludeTag"%');
      }
      final rows = _db.select(
        "SELECT * FROM notes WHERE ${conditions.join(' AND ')} ORDER BY created_at DESC",
        params,
      );
      return rows.map(_rowToNote).toList();
    } catch (e) {
      debugPrint('[NoteLocalCache] getNotesWithTag error: $e');
      return [];
    }
  }

  /// Get a single note by ID.
  Note? getNote(String id) {
    try {
      final rows = _db.select('SELECT * FROM notes WHERE id = ?', [id]);
      if (rows.isEmpty) return null;
      return _rowToNote(rows.first);
    } catch (e) {
      debugPrint('[NoteLocalCache] getNote error: $e');
      return null;
    }
  }

  /// Get the first audio attachment path for a note.
  String? getAudioPath(String noteId) {
    try {
      final rows = _db.select(
        "SELECT path FROM attachments WHERE note_id = ? AND mime_type LIKE 'audio/%' LIMIT 1",
        [noteId],
      );
      if (rows.isEmpty) return null;
      return rows.first['path'] as String;
    } catch (e) {
      debugPrint('[NoteLocalCache] getAudioPath error: $e');
      return null;
    }
  }

  /// Return IDs of notes with pending server deletes.
  List<String> getPendingDeletes() {
    try {
      final rows = _db.select(
        "SELECT id FROM notes WHERE sync_state = 'pending_delete'",
      );
      return rows.map((r) => r['id'] as String).toList();
    } catch (e) {
      debugPrint('[NoteLocalCache] getPendingDeletes error: $e');
      return [];
    }
  }

  /// Return notes with pending server edits.
  List<Note> getPendingEdits() {
    try {
      final rows = _db.select(
        "SELECT * FROM notes WHERE sync_state = 'pending_edit'",
      );
      return rows.map(_rowToNote).toList();
    } catch (e) {
      debugPrint('[NoteLocalCache] getPendingEdits error: $e');
      return [];
    }
  }

  /// Return notes created offline (pending server POST).
  List<Note> getPendingCreates() {
    try {
      final rows = _db.select(
        "SELECT * FROM notes WHERE sync_state = 'pending_create' ORDER BY created_at ASC",
      );
      return rows.map(_rowToNote).toList();
    } catch (e) {
      debugPrint('[NoteLocalCache] getPendingCreates error: $e');
      return [];
    }
  }

  /// Count of all pending operations (creates + edits + deletes).
  int getPendingCount() {
    try {
      final rows = _db.select(
        "SELECT COUNT(*) as c FROM notes WHERE sync_state IN ('pending_create', 'pending_edit', 'pending_delete')",
      );
      return rows.first['c'] as int;
    } catch (e) {
      return 0;
    }
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Batch-upsert notes from server into the cache.
  ///
  /// Preserves locally-pending mutations:
  /// - pending_delete rows keep their sync_state
  /// - pending_edit rows keep their content and sync_state
  /// - pending_create rows are not overwritten (shouldn't happen, but safe)
  void putNotes(List<Note> notes) {
    if (notes.isEmpty) return;
    PreparedStatement? stmt;
    try {
      stmt = _db.prepare(
        'INSERT INTO notes (id, content, path, created_at, updated_at, tags_json, sync_state) '
        "VALUES (?, ?, ?, ?, ?, ?, 'synced') "
        'ON CONFLICT(id) DO UPDATE SET '
        "  content    = CASE WHEN sync_state IN ('pending_edit', 'pending_create') THEN content    ELSE excluded.content    END, "
        "  path       = CASE WHEN sync_state IN ('pending_edit', 'pending_create') THEN path       ELSE excluded.path       END, "
        '  created_at = excluded.created_at, '
        '  updated_at = excluded.updated_at, '
        "  tags_json  = CASE WHEN sync_state IN ('pending_edit', 'pending_create') THEN tags_json  ELSE excluded.tags_json  END, "
        "  sync_state = CASE WHEN sync_state IN ('pending_delete', 'pending_edit', 'pending_create') THEN sync_state ELSE 'synced' END",
      );
      for (final note in notes) {
        stmt.execute([
          note.id,
          note.content,
          note.path,
          note.createdAt.toUtc().toIso8601String(),
          note.updatedAt?.toUtc().toIso8601String(),
          jsonEncode(note.tags),
        ]);
      }
    } catch (e) {
      debugPrint('[NoteLocalCache] putNotes error: $e');
    } finally {
      stmt?.dispose();
    }
  }

  /// Cache an attachment (e.g., audio file path).
  void putAttachment(String noteId, String path, String? mimeType) {
    try {
      final id = '${noteId}_${path.hashCode}';
      _db.execute(
        'INSERT OR REPLACE INTO attachments (id, note_id, path, mime_type) VALUES (?, ?, ?, ?)',
        [id, noteId, path, mimeType],
      );
    } catch (e) {
      debugPrint('[NoteLocalCache] putAttachment error: $e');
    }
  }

  /// Insert a note created offline (sync_state = pending_create).
  void insertPendingCreate(Note note, {String? audioPath}) {
    try {
      _db.execute(
        "INSERT OR REPLACE INTO notes (id, content, path, created_at, updated_at, tags_json, sync_state) "
        "VALUES (?, ?, ?, ?, ?, ?, 'pending_create')",
        [
          note.id,
          note.content,
          note.path,
          note.createdAt.toUtc().toIso8601String(),
          note.updatedAt?.toUtc().toIso8601String(),
          jsonEncode(note.tags),
        ],
      );
      if (audioPath != null) {
        putAttachment(note.id, audioPath, 'audio/wav');
      }
    } catch (e) {
      debugPrint('[NoteLocalCache] insertPendingCreate error: $e');
    }
  }

  // ── Sync-state mutations ───────────────────────────────────────────────────

  void markForDelete(String noteId) {
    try {
      _db.execute(
        "UPDATE notes SET sync_state = 'pending_delete' WHERE id = ?",
        [noteId],
      );
    } catch (e) {
      debugPrint('[NoteLocalCache] markForDelete error: $e');
    }
  }

  void markForEdit(String noteId, {required String content}) {
    try {
      _db.execute(
        "UPDATE notes SET content = ?, sync_state = 'pending_edit' WHERE id = ?",
        [content, noteId],
      );
    } catch (e) {
      debugPrint('[NoteLocalCache] markForEdit error: $e');
    }
  }

  void markSynced(String noteId, {String? content}) {
    try {
      _db.execute(
        "UPDATE notes SET content = COALESCE(?, content), sync_state = 'synced' WHERE id = ?",
        [content, noteId],
      );
    } catch (e) {
      debugPrint('[NoteLocalCache] markSynced error: $e');
    }
  }

  // ── Remove ─────────────────────────────────────────────────────────────────

  void removeNote(String noteId) {
    try {
      _db.execute('DELETE FROM attachments WHERE note_id = ?', [noteId]);
      _db.execute('DELETE FROM notes WHERE id = ?', [noteId]);
    } catch (e) {
      debugPrint('[NoteLocalCache] removeNote error: $e');
    }
  }

  /// Remove synced notes for a date range that aren't in the server's response.
  void removeStaleNotes(String dateFrom, String dateTo, Set<String> serverIds) {
    if (serverIds.isEmpty) return;
    try {
      final placeholders = List.filled(serverIds.length, '?').join(', ');
      _db.execute(
        "DELETE FROM notes "
        "WHERE created_at >= ? AND created_at < ? "
        "AND COALESCE(sync_state, 'synced') = 'synced' "
        "AND id NOT IN ($placeholders)",
        [DateTime.parse(dateFrom).toUtc().toIso8601String(),
         DateTime.parse(dateTo).toUtc().toIso8601String(), ...serverIds],
      );
    } catch (e) {
      debugPrint('[NoteLocalCache] removeStaleNotes error: $e');
    }
  }

  /// Clear all synced notes for a date range (server returned empty).
  void clearDateRange(String dateFrom, String dateTo) {
    try {
      _db.execute(
        "DELETE FROM notes WHERE created_at >= ? AND created_at < ? "
        "AND COALESCE(sync_state, 'synced') = 'synced'",
        [DateTime.parse(dateFrom).toUtc().toIso8601String(),
         DateTime.parse(dateTo).toUtc().toIso8601String()],
      );
    } catch (e) {
      debugPrint('[NoteLocalCache] clearDateRange error: $e');
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void dispose() {
    try {
      _db.dispose();
    } catch (_) {}
  }

  // ── Conversion ─────────────────────────────────────────────────────────────

  Note _rowToNote(Row row) {
    final tagsJson = (row['tags_json'] as String?) ?? '[]';
    List<String> tags;
    try {
      tags = (jsonDecode(tagsJson) as List<dynamic>)
          .map((t) => t as String)
          .toList();
    } catch (_) {
      tags = [];
    }

    final createdAtStr = row['created_at'] as String;
    final updatedAtStr = row['updated_at'] as String?;

    return Note(
      id: row['id'] as String,
      content: (row['content'] as String?) ?? '',
      path: row['path'] as String?,
      createdAt: DateTime.parse(createdAtStr),
      updatedAt: updatedAtStr != null ? DateTime.tryParse(updatedAtStr) : null,
      tags: tags,
    );
  }
}
