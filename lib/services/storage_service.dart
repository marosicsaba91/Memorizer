import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/knowledge_table.dart';
import '../models/row_save_data.dart';

class StorageService {
  static const String _namesKey = 'knowledge_table_names';
  static const String _tablePrefix = 'knowledge_table/';
  static const String _sortSettingsPrefix = 'sort_settings/';
  static const String _studyStatePrefix = 'study_state/';
  static const String _rowDataPrefix = 'row_data/';

  /// Persists [tables] locally, replacing any previously saved data.
  Future<void> saveKnowledgeTables(List<KnowledgeTable> tables) async {
    final prefs = await SharedPreferences.getInstance();

    // Collect old names so we can remove stale entries.
    final oldNames = prefs.getStringList(_namesKey) ?? [];
    final newNames = tables.map((t) => t.name).toList();

    // Write each table.
    for (final table in tables) {
      await prefs.setString(
        '$_tablePrefix${table.name}',
        jsonEncode(table.toJson()),
      );
      await _reconcileRowDataForTable(prefs, table);
    }

    // Update the name index.
    await prefs.setStringList(_namesKey, newNames);

    // Remove tables that are no longer in the index.
    for (final name in oldNames) {
      if (!newNames.contains(name)) {
        await prefs.remove('$_tablePrefix$name');
        await prefs.remove('$_rowDataPrefix$name');
        await prefs.remove('$_sortSettingsPrefix$name');
        await prefs.remove('$_textSizePrefix$name');
        await prefs.remove('$_studyStatePrefix$name');
        await prefs.remove('$_difficultiesPrefix$name');
      }
    }
  }

  List<List<String>> _extractDataRows(List<List<String>> rows) {
    if (rows.isEmpty) return rows;

    var dataRows = rows;
    final firstRow = rows.first;
    final looksLikeHeader = firstRow.any(
      (cell) => cell.isNotEmpty && double.tryParse(cell) == null,
    );
    if (looksLikeHeader) {
      dataRows = rows.skip(1).toList();
    }
    return dataRows;
  }

  String _rowKeyFromRow(List<String> row) => row.isNotEmpty ? row.first : '';

  Future<void> _reconcileRowDataForTable(
    SharedPreferences prefs,
    KnowledgeTable table,
  ) async {
    final existing =
        await loadTableRowData(table.name) ??
        _loadLegacyRowDataForTable(prefs, table);
    final rows = _extractDataRows(table.rows);
    final updated = <String, RowSaveData>{};

    for (var i = 0; i < rows.length; i++) {
      final key = _rowKeyFromRow(rows[i]);
      final previous = existing[key];
      updated[key] = previous ?? RowSaveData(rowOrder: i, revealed: const [], difficulty: 5);
    }

    await prefs.setString(
      '$_rowDataPrefix${table.name}',
      jsonEncode(updated.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Map<String, RowSaveData> _loadLegacyRowDataForTable(
    SharedPreferences prefs,
    KnowledgeTable table,
  ) {
    final rows = _extractDataRows(table.rows);
    final rawStudyState = prefs.getString('$_studyStatePrefix${table.name}');
    final rawDifficulties = prefs.getString('$_difficultiesPrefix${table.name}');

    List<List<bool>> revealedByIndex = [];
    List<int> displayOrder = [];
    List<int> difficulties = [];

    if (rawStudyState != null) {
      try {
        final decoded = jsonDecode(rawStudyState) as Map<String, dynamic>;
        final revealedRaw = decoded['revealed'];
        final rowOrderRaw = decoded['rowOrder'];
        if (revealedRaw is List) {
          revealedByIndex = revealedRaw
              .map(
                (row) => (row as List)
                    .map((v) => v == true)
                    .toList(growable: false),
              )
              .toList(growable: false);
        }
        if (rowOrderRaw is List) {
          displayOrder = rowOrderRaw
              .whereType<int>()
              .toList(growable: false);
        }
      } catch (_) {}
    }

    if (rawDifficulties != null) {
      try {
        difficulties = (jsonDecode(rawDifficulties) as List)
            .whereType<int>()
            .toList(growable: false);
      } catch (_) {}
    }

    if (revealedByIndex.isEmpty && displayOrder.isEmpty && difficulties.isEmpty) {
      return <String, RowSaveData>{};
    }

    final rowPositionByIndex = <int, int>{};
    for (var pos = 0; pos < displayOrder.length; pos++) {
      rowPositionByIndex[displayOrder[pos]] = pos;
    }

    final migrated = <String, RowSaveData>{};
    for (var i = 0; i < rows.length; i++) {
      migrated[_rowKeyFromRow(rows[i])] = RowSaveData(
        rowOrder: rowPositionByIndex[i] ?? i,
        revealed: i < revealedByIndex.length ? revealedByIndex[i] : const [],
        difficulty: (i < difficulties.length ? difficulties[i] : 5).clamp(1, 10),
      );
    }
    return migrated;
  }

  static const String _textSizePrefix = 'table_textsize/';

  /// Persists the text size for [tableName].
  Future<void> saveTableTextSize(String tableName, double textSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_textSizePrefix$tableName', textSize);
  }

  /// Loads the text size for [tableName]. Returns null if not saved yet.
  Future<double?> loadTableTextSize(String tableName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('$_textSizePrefix$tableName');
  }

  /// Persists sort dialog settings for [tableName].
  Future<void> saveTableSortSettings(
    String tableName, {
    required bool randomise,
    required String seed,
    required int difficultyOrderIndex,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_sortSettingsPrefix$tableName', jsonEncode({
      'randomise': randomise,
      'seed': seed,
      'difficultyOrderIndex': difficultyOrderIndex,
    }));
  }

  /// Loads sort dialog settings for [tableName].
  /// Returns null if nothing has been saved yet.
  Future<Map<String, dynamic>?> loadTableSortSettings(String tableName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_sortSettingsPrefix$tableName');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Persists per-table study state: revealed cells and row order.
  Future<void> saveTableStudyState(
    String tableName, {
    required List<List<bool>> revealed,
    required List<int> rowOrder,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_studyStatePrefix$tableName', jsonEncode({
      'revealed': revealed,
      'rowOrder': rowOrder,
    }));
  }

  /// Loads per-table study state.
  /// Returns null if nothing has been saved yet.
  Future<Map<String, dynamic>?> loadTableStudyState(String tableName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_studyStatePrefix$tableName');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Persists per-row data for a table keyed by first-column text.
  Future<void> saveTableRowData(
    String tableName,
    Map<String, RowSaveData> rowData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_rowDataPrefix$tableName',
      jsonEncode(rowData.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Loads per-row data for a table keyed by first-column text.
  /// Returns null if nothing has been saved yet.
  Future<Map<String, RowSaveData>?> loadTableRowData(String tableName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_rowDataPrefix$tableName');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(
          key,
          RowSaveData.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static const String _difficultiesPrefix = 'difficulties/';

  /// Persists per-row difficulty values for [tableName].
  Future<void> saveDifficulties(
    String tableName,
    List<int> difficulties,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_difficultiesPrefix$tableName',
      jsonEncode(difficulties),
    );
  }

  /// Loads per-row difficulty values for [tableName].
  /// Returns null if nothing has been saved yet.
  Future<List<int>?> loadDifficulties(String tableName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_difficultiesPrefix$tableName');
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List).map((e) => e as int).toList();
    } catch (_) {
      return null;
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
        tables.add(
          KnowledgeTable.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // Skip corrupted entries silently.
      }
    }
    return tables;
  }
}
