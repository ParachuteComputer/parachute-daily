-- Link orphaned audio files to their matching notes.
--
-- 33 audio files in ~/.parachute/daily/assets/ couldn't be matched during
-- the v3 data migration. This script links 31 of them to notes by timestamp
-- proximity and adds the #voice tag where missing.
--
-- 2 files on 2026-03-04 have no corresponding notes and are skipped.
--
-- Backup: ~/.parachute/daily.db.bak-before-audio-link
-- Run with: sqlite3 ~/.parachute/daily.db < scripts/link-orphan-audio.sql

-- ============================================================================
-- Step 1: Create attachments for unlinked audio files
-- ============================================================================

-- 2025-12-22: 4 files → 3 notes (timestamp-named files)
-- 153928 = 15:39:28, closest note is 43soktzucw78
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-2025-12-22-153928', '43soktzucw78', '2025-12-22/153928_audio.wav', 'audio/wav', '2025-12-22T15:39:28.000Z');

INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-2025-12-22-154138', '43soktzucw78', '2025-12-22/154138_audio.wav', 'audio/wav', '2025-12-22T15:41:38.000Z');

INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-2025-12-22-154420', '43soktzucw78', '2025-12-22/154420_audio.wav', 'audio/wav', '2025-12-22T15:44:20.000Z');

INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-2025-12-22-172002', '43soktzucw78', '2025-12-22/172002_audio.wav', 'audio/wav', '2025-12-22T17:20:02.000Z');

-- 2026-03-15: 7 files → 4 notes
-- 18600bf4 (mtime 08:02) → 2026-03-15-14-02-22-073090 (0s diff, empty content)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-18600bf4', '2026-03-15-14-02-22-073090', '2026-03-15/18600bf4.wav', 'audio/wav', '2026-03-15T08:02:22.000Z');

-- 6517ad28 (mtime 16:39) → 2026-03-15-22-39-05-306067 (0s diff, empty content)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-6517ad28', '2026-03-15-22-39-05-306067', '2026-03-15/6517ad28.wav', 'audio/wav', '2026-03-15T16:39:05.000Z');

-- 34ca9e2a (mtime 16:42) → 2026-03-15-22-42-27-826274 (0s diff, has content)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-34ca9e2a', '2026-03-15-22-42-27-826274', '2026-03-15/34ca9e2a.wav', 'audio/wav', '2026-03-15T16:42:27.000Z');

-- 3b81aac7, 881e051e, ebc2c239, feddb943 — all map to same notes but with large diffs.
-- These are likely additional recording segments. Attach to closest:
-- 3b81aac7 (mtime 22:10) → 2026-03-15-22-39-05-306067
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-3b81aac7', '2026-03-15-22-39-05-306067', '2026-03-15/3b81aac7.wav', 'audio/wav', '2026-03-15T22:10:30.000Z');

-- 881e051e (mtime 22:34) → 2026-03-15-22-42-27-826274
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-881e051e', '2026-03-15-22-42-27-826274', '2026-03-15/881e051e.wav', 'audio/wav', '2026-03-15T22:34:17.000Z');

-- ebc2c239 (mtime 22:40) → 2026-03-15-22-42-27-826274
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-ebc2c239', '2026-03-15-22-42-27-826274', '2026-03-15/ebc2c239.wav', 'audio/wav', '2026-03-15T22:40:54.000Z');

-- feddb943 (mtime 22:57) → 2026-03-15-22-42-27-826274
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-feddb943', '2026-03-15-22-42-27-826274', '2026-03-15/feddb943.wav', 'audio/wav', '2026-03-15T22:57:01.000Z');

-- 2026-03-16: 5 files → 5 notes
-- abdee7fd (mtime 11:10) → 2026-03-16-14-51-46-410944
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-abdee7fd', '2026-03-16-14-51-46-410944', '2026-03-16/abdee7fd.wav', 'audio/wav', '2026-03-16T11:10:48.000Z');

-- fb4ffe31 (mtime 11:13) → 2026-03-16-14-51-46-410944
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-fb4ffe31', '2026-03-16-14-51-46-410944', '2026-03-16/fb4ffe31.wav', 'audio/wav', '2026-03-16T11:13:25.000Z');

-- a8887397 (mtime 12:36) → 2026-03-16-13-03-30-057148
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-a8887397', '2026-03-16-13-03-30-057148', '2026-03-16/a8887397.wav', 'audio/wav', '2026-03-16T12:36:28.000Z');

-- 56595fc5 (mtime 12:36) → 2026-03-16-13-03-30-057148
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-56595fc5', '2026-03-16-13-03-30-057148', '2026-03-16/56595fc5.wav', 'audio/wav', '2026-03-16T12:36:31.000Z');

-- c29c0503 (mtime 15:06) → 2026-03-16-21-06-48-841719 (0s diff)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-c29c0503', '2026-03-16-21-06-48-841719', '2026-03-16/c29c0503.wav', 'audio/wav', '2026-03-16T15:06:48.000Z');

-- 2026-03-19: 1 file → 1 note
-- e821dcf0 (mtime 07:29) → 2026-03-19-13-29-58-009829 (0s diff)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-e821dcf0', '2026-03-19-13-29-58-009829', '2026-03-19/e821dcf0.wav', 'audio/wav', '2026-03-19T07:29:58.000Z');

-- 2026-03-20: 1 file → 1 note
-- 10520cbf (mtime 07:19) → 2026-03-20-13-19-50-701821 (0s diff)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-10520cbf', '2026-03-20-13-19-50-701821', '2026-03-20/10520cbf.wav', 'audio/wav', '2026-03-20T07:19:50.000Z');

-- 2026-03-26: 2 files → 1 note
-- a47c7b3c (mtime 15:05) → 2026-03-26-21-05-57-345658 (0s diff)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-a47c7b3c', '2026-03-26-21-05-57-345658', '2026-03-26/a47c7b3c.wav', 'audio/wav', '2026-03-26T15:05:57.000Z');

-- 95d0fd4f (mtime 16:03) → 2026-03-26-21-05-57-345658
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-95d0fd4f', '2026-03-26-21-05-57-345658', '2026-03-26/95d0fd4f.wav', 'audio/wav', '2026-03-26T16:03:27.000Z');

-- 2026-03-28: 2 files → 1 note
-- 108ede1e_recording (mtime 10:28) → 2026-03-28-14-12-06-699578
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-108ede1e', '2026-03-28-14-12-06-699578', '2026-03-28/108ede1e_recording_1774706342874.wav', 'audio/wav', '2026-03-28T10:28:19.000Z');

-- ad047f55 (mtime 10:29) → 2026-03-28-14-12-06-699578
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-ad047f55', '2026-03-28-14-12-06-699578', '2026-03-28/ad047f55.wav', 'audio/wav', '2026-03-28T10:29:09.000Z');

-- 2026-03-29: 9 files → 4 notes
-- 4217d18d (mtime 10:44) → 2026-03-29-16-53-45-797660 (569s diff)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-4217d18d', '2026-03-29-16-53-45-797660', '2026-03-29/4217d18d.wav', 'audio/wav', '2026-03-29T10:44:16.000Z');

-- 0a9025ff (mtime 10:53) → 2026-03-29-16-53-45-797660 (0s diff)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-0a9025ff', '2026-03-29-16-53-45-797660', '2026-03-29/0a9025ff.wav', 'audio/wav', '2026-03-29T10:53:45.000Z');

-- 1b215f14 (mtime 10:55) → 2026-03-29-16-53-45-797660 (127s diff)
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-1b215f14', '2026-03-29-16-53-45-797660', '2026-03-29/1b215f14.wav', 'audio/wav', '2026-03-29T10:55:52.000Z');

-- 708efe85_recording (mtime 17:02) → 2026-03-29-16-53-45-797660
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-708efe85', '2026-03-29-16-53-45-797660', '2026-03-29/708efe85_recording_1774823284178.wav', 'audio/wav', '2026-03-29T17:02:22.000Z');

-- e52983ab (mtime 19:05) → 2026-03-29-23-50-16-905738
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-e52983ab', '2026-03-29-23-50-16-905738', '2026-03-29/e52983ab.wav', 'audio/wav', '2026-03-29T19:05:31.000Z');

-- 27eeb612 (mtime 19:05) → 2026-03-29-23-50-16-905738
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-27eeb612', '2026-03-29-23-50-16-905738', '2026-03-29/27eeb612.wav', 'audio/wav', '2026-03-29T19:05:55.000Z');

-- 2046ff42 (mtime 19:13) → 2026-03-29-01-48-11-532958
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-2046ff42', '2026-03-29-01-48-11-532958', '2026-03-29/2046ff42.wav', 'audio/wav', '2026-03-29T19:13:48.000Z');

-- ae980231 (mtime 19:16) → 2026-03-29-23-50-16-905738
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-ae980231', '2026-03-29-23-50-16-905738', '2026-03-29/ae980231.wav', 'audio/wav', '2026-03-29T19:16:09.000Z');

-- c144c76f (mtime 19:34) → 2026-03-29-23-50-16-905738
INSERT OR IGNORE INTO attachments (id, note_id, path, mime_type, created_at)
VALUES ('orphan-c144c76f', '2026-03-29-23-50-16-905738', '2026-03-29/c144c76f.wav', 'audio/wav', '2026-03-29T19:34:36.000Z');

-- ============================================================================
-- Step 2: Add #voice tag to notes that now have audio but lack the tag
-- ============================================================================

INSERT OR IGNORE INTO note_tags (note_id, tag_name)
SELECT DISTINCT a.note_id, 'voice'
FROM attachments a
WHERE a.id LIKE 'orphan-%'
  AND a.mime_type = 'audio/wav'
  AND NOT EXISTS (
    SELECT 1 FROM note_tags nt
    WHERE nt.note_id = a.note_id AND nt.tag_name = 'voice'
  );

-- ============================================================================
-- Summary
-- ============================================================================
-- Linked: 31 audio files → 15 notes
-- Skipped: 2 files on 2026-03-04 (no notes exist for that date)
-- Tags added: #voice tag to all newly-linked notes that didn't have it
