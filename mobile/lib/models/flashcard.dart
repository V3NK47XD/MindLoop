class Flashcard {
  final String id;
  final String question;
  final String createdAt;
  final List<String> tags;
  final String sourcePdf;
  final int pdfRefLine;
  final List<String> attachments;
  final String folderPath; // Path where ZIP is extracted

  Flashcard({
    required this.id,
    required this.question,
    required this.createdAt,
    required this.tags,
    required this.sourcePdf,
    required this.pdfRefLine,
    required this.attachments,
    required this.folderPath,
  });

  factory Flashcard.fromJson(Map<String, dynamic> json, String folderPath) {
    final rawTags = List<dynamic>.from(json['tags'] ?? []);
    final rawAttachments = List<dynamic>.from(json['attachments'] ?? []);
    return Flashcard(
      id: json['id'] as String,
      question: json['question'] as String,
      createdAt: json['created_at'] as String,
      tags: rawTags.map((t) => t.toString().trim()).where((t) => t.isNotEmpty).toList(),
      sourcePdf: json['source_pdf'] as String? ?? '',
      pdfRefLine: json['pdf_ref_line'] as int? ?? 0,
      attachments: rawAttachments.map((a) => a.toString().trim()).where((a) => a.isNotEmpty).toList(),
      folderPath: folderPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'question': question,
      'created_at': createdAt,
      'tags': tags.join(','),
      'source_pdf': sourcePdf,
      'pdf_ref_line': pdfRefLine,
      'attachments': attachments.join(','),
      'folder_path': folderPath,
    };
  }

  factory Flashcard.fromMap(Map<String, dynamic> map) {
    // Trim each tag and attachment to remove whitespace artifacts from SQLite storage
    final tagsStr = map['tags'] as String? ?? '';
    final attachmentsStr = map['attachments'] as String? ?? '';
    return Flashcard(
      id: map['id'] as String,
      question: map['question'] as String,
      createdAt: map['created_at'] as String,
      tags: tagsStr.isEmpty
          ? []
          : tagsStr.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      sourcePdf: map['source_pdf'] as String? ?? '',
      pdfRefLine: map['pdf_ref_line'] as int? ?? 0,
      attachments: attachmentsStr.isEmpty
          ? []
          : attachmentsStr.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      folderPath: map['folder_path'] as String,
    );
  }
}
