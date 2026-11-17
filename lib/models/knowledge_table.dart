import 'dart:convert';

class KnowledgeTable {
  static bool isSeparateLineColumn(String title) =>
      title.trimRight().endsWith('*');

  static String columnLabel(String title) {
    final trimmed = title.trimRight();
    return isSeparateLineColumn(title)
        ? trimmed.substring(0, trimmed.length - 1).trimRight()
        : title;
  }

  final Map<String, int> importance;
  final String name;
  final String? sourceUrl;
  final double? textSize;

  /// Each inner list is one row; rows may have any number of string values.
  final List<List<String>> rows;

  const KnowledgeTable({
    required this.name,
    this.importance = const {},
    required this.rows,
    this.sourceUrl,
    this.textSize,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'importance': importance,
    'rows': rows,
    'sourceUrl': sourceUrl,
    if (textSize != null) 'textSize': textSize,
  };

  factory KnowledgeTable.fromJson(Map<String, dynamic> json) => KnowledgeTable(
    name: json['name'] as String,
    importance: Map<String, int>.from(json['importance'] as Map? ?? {}),
    sourceUrl: json['sourceUrl'] as String?,
    textSize: (json['textSize'] as num?)?.toDouble(),
    rows: (json['rows'] as List)
        .map((row) => (row as List).map((cell) => cell.toString()).toList())
        .toList(),
  );

  String serialize() => jsonEncode(toJson());

  static KnowledgeTable deserialize(String source) =>
      KnowledgeTable.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
