import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/knowledge_table.dart';

class StorageService {
  static const String _namesKey = 'knowledge_table_names';
  static const String _tablePrefix = 'knowledge_table/';

  /// Persists [tables] locally, replacing any previously saved data.
  Future<void> saveKnowledgeTables(List<KnowledgeTable> tables) async {
    final prefs = await SharedPreferences.getInstance();

    // Collect old names so we can remove stale entries.
    final oldNames = prefs.getStringList(_namesKey) ?? [];
    final newNames = tables.map((t) => t.name).toList();

    // Write each table.
    for (final table in tables) {
      await prefs.setString(
          '$_tablePrefix${table.name}', jsonEncode(table.toJson()));
    }

    // Update the name index.
    await prefs.setStringList(_namesKey, newNames);

    // Remove tables that are no longer in the index.
    for (final name in oldNames) {
      if (!newNames.contains(name)) {
        await prefs.remove('$_tablePrefix$name');
      }
    }
  }

  /// Loads and returns all locally saved [KnowledgeTable]s.
  Future<List<KnowledgeTable>> loadKnowledgeTables() async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_namesKey) ?? [];

    final tables = <KnowledgeTable>[];
    for (final name in names) {
      final raw = prefs.getString('$_tablePrefix$name');
      if (raw == null) continue;
      try {
        tables.add(KnowledgeTable.fromJson(
            jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Skip corrupted entries silently.
      }
    }
    return tables;
  }
}
