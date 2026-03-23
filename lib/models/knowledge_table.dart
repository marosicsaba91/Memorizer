import 'dart:convert';

class KnowledgeTable {
  final String name;

  /// Each inner list is one row; rows may have any number of string values.
  final List<List<String>> rows;

  const KnowledgeTable({required this.name, required this.rows});

  Map<String, dynamic> toJson() => {
        'name': name,
        'rows': rows,
      };

  factory KnowledgeTable.fromJson(Map<String, dynamic> json) => KnowledgeTable(
        name: json['name'] as String,
        rows: (json['rows'] as List)
            .map((row) =>
                (row as List).map((cell) => cell.toString()).toList())
            .toList(),
      );

  String serialize() => jsonEncode(toJson());

  static KnowledgeTable deserialize(String source) =>
      KnowledgeTable.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
