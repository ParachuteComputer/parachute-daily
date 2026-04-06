/// A Note is the universal record in Parachute.
/// Notes are differentiated by flat tags (#daily, #doc, #digest, etc.).
class Note {
  final String id;
  final String content;
  final String? path;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> tags;
  final List<NoteLink> links;

  const Note({
    required this.id,
    required this.content,
    this.path,
    required this.createdAt,
    this.updatedAt,
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

  factory Note.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final createdRaw = json['createdAt'] as String?;
    final updatedRaw = json['updatedAt'] as String?;
    return Note(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      path: json['path'] as String?,
      createdAt: (createdRaw != null ? DateTime.tryParse(createdRaw) : null) ?? now,
      updatedAt: updatedRaw != null ? DateTime.tryParse(updatedRaw) : null,
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
        'tags': tags,
        'links': links.map((l) => l.toJson()).toList(),
      };

  Note copyWith({
    String? id,
    String? content,
    String? path,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    List<NoteLink>? links,
  }) {
    return Note(
      id: id ?? this.id,
      content: content ?? this.content,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
