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
    return Flashcard(
      id: json['id'] as String,
      question: json['question'] as String,
      createdAt: json['created_at'] as String,
      tags: List<String>.from(json['tags'] ?? []),
      sourcePdf: json['source_pdf'] as String? ?? '',
      pdfRefLine: json['pdf_ref_line'] as int? ?? 0,
      attachments: List<String>.from(json['attachments'] ?? []),
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
    return Flashcard(
      id: map['id'] as String,
      question: map['question'] as String,
      createdAt: map['created_at'] as String,
      tags: (map['tags'] as String).isEmpty ? [] : (map['tags'] as String).split(','),
      sourcePdf: map['source_pdf'] as String? ?? '',
      pdfRefLine: map['pdf_ref_line'] as int? ?? 0,
      attachments: (map['attachments'] as String).isEmpty ? [] : (map['attachments'] as String).split(','),
      folderPath: map['folder_path'] as String,
    );
  }
}
