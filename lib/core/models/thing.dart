/// A Note is the universal record in Parachute.
/// Notes are differentiated by flat tags (#daily, #doc, #digest, etc.).
class Note {
  final String id;
  final String content;
  final String? path;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> metadata;
  final List<String> tags;
  final List<NoteLink> links;

  const Note({
    required this.id,
    required this.content,
    this.path,
    required this.createdAt,
    this.updatedAt,
    this.metadata = const {},
    this.tags = const [],
    this.links = const [],
  });

  // ---- Tag convenience ----

  bool hasTag(String tag) => tags.contains(tag);

  // ---- Type checks ----

  bool get isCaptured => hasTag('captured');
  bool get isReader => hasTag('reader');
  bool get isView => hasTag('view');
  bool get isPinned => hasTag('pinned');
  bool get isArchived => hasTag('archived');

  // ---- Serialization ----

  /// Parse a timestamp string, treating bare (no Z, no offset) strings as UTC.
  ///
  /// The vault server stores timestamps without a Z suffix. Dart's
  /// DateTime.tryParse treats those as local time, causing a timezone-offset
  /// shift when the client later calls .toUtc(). Force UTC interpretation so
  /// cached timestamps match the server's actual values.
  static DateTime? _parseUtc(String? raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    if (!raw.endsWith('Z') && !raw.contains('+') && !raw.contains('-', 10)) {
      return DateTime.utc(parsed.year, parsed.month, parsed.day,
          parsed.hour, parsed.minute, parsed.second,
          parsed.millisecond, parsed.microsecond);
    }
    return parsed;
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final createdRaw = json['createdAt'] as String?;
    final updatedRaw = json['updatedAt'] as String?;
    return Note(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      path: json['path'] as String?,
      createdAt: _parseUtc(createdRaw) ?? now,
      updatedAt: _parseUtc(updatedRaw),
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      tags: (json['tags'] as List<dynamic>?)
              ?.map((t) => t as String)
              .toList() ??
          [],
      links: (json['links'] as List<dynamic>?)
              ?.map((l) => NoteLink.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        if (path != null) 'path': path,
        'createdAt': createdAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (metadata.isNotEmpty) 'metadata': metadata,
        'tags': tags,
        'links': links.map((l) => l.toJson()).toList(),
      };

  Note copyWith({
    String? id,
    String? content,
    String? path,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
    List<String>? tags,
    List<NoteLink>? links,
  }) {
    return Note(
      id: id ?? this.id,
      content: content ?? this.content,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
      tags: tags ?? this.tags,
      links: links ?? this.links,
    );
  }

  @override
  String toString() => 'Note($id, ${content.length > 50 ? '${content.substring(0, 50)}...' : content})';
}

/// A directed link between two notes.
class NoteLink {
  final String sourceId;
  final String targetId;
  final String relationship;
  final String createdAt;

  const NoteLink({
    required this.sourceId,
    required this.targetId,
    required this.relationship,
    required this.createdAt,
  });

  factory NoteLink.fromJson(Map<String, dynamic> json) {
    return NoteLink(
      sourceId: json['sourceId'] as String,
      targetId: json['targetId'] as String,
      relationship: json['relationship'] as String,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'targetId': targetId,
        'relationship': relationship,
        'createdAt': createdAt,
      };
}
