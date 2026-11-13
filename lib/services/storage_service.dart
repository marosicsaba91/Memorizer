import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/knowledge_table.dart';
import '../models/row_save_data.dart';
import '../models/profile_settings.dart';
import '../models/game_session.dart';

class StorageService {
  Future<Map<String, dynamic>?> loadGameSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('game/settings');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveGameSettings(GameSettings settings, int finiteCount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'game/settings',
      jsonEncode({...settings.toJson(), 'finiteQuestionCount': finiteCount}),
    );
  }

  Future<ProfileSettings> loadProfileSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return ProfileSettings(
      syncUrl: prefs.getString('profile/sync_url') ?? '',
      autoSync: prefs.getBool('profile/auto_sync') ?? false,
    );
  }

  Future<void> saveProfileSettings(ProfileSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile/sync_url', settings.syncUrl.trim());
    await prefs.setBool('profile/auto_sync', settings.autoSync);
  }

  Future<Map<String, RowSaveData>> ensureTableRowData(
    KnowledgeTable table,
  ) async {
    final existing = await loadTableRowData(table.name);
    if (existing != null) return existing;
    final prefs = await SharedPreferences.getInstance();
    await _reconcileRowDataForTable(prefs, table);
    return (await loadTableRowData(table.name))!;
  }

  static const String _namesKey = 'knowledge_table_names';
  static const String _tablePrefix = 'knowledge_table/';
  static const String _sortSettingsPrefix = 'sort_settings/';
  static const String _studyStatePrefix = 'study_state/';
  static const String _rowDataPrefix = 'row_data/';

  /// Persists [tables] locally, replacing any previously saved data.
  Future<void> saveKnowledgeTables(List<KnowledgeTable> tables) async {
    final prefs = await SharedPreferences.getInstance();

    await _migratePersonalResults(prefs);

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
      updated[key] = previous ?? RowSaveData(rowOrder: i, revealed: const []);
    }

    await saveTableRowData(table.name, updated);
  }

  Map<String, RowSaveData> _loadLegacyRowDataForTable(
    SharedPreferences prefs,
    KnowledgeTable table,
  ) {
    final rows = _extractDataRows(table.rows);
    final rawStudyState = prefs.getString('$_studyStatePrefix${table.name}');
    final rawDifficulties = prefs.getString(
      '$_difficultiesPrefix${table.name}',
    );

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
                (row) =>
                    (row as List).map((v) => v == true).toList(growable: false),
              )
              .toList(growable: false);
        }
        if (rowOrderRaw is List) {
          displayOrder = rowOrderRaw.whereType<int>().toList(growable: false);
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

    if (revealedByIndex.isEmpty &&
        displayOrder.isEmpty &&
        difficulties.isEmpty) {
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
        success: i < difficulties.length ? difficulties[i].clamp(1, 10) : null,
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
    required int successOrderIndex,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_sortSettingsPrefix$tableName',
      jsonEncode({
        'randomise': randomise,
        'seed': seed,
        'successOrderIndex': successOrderIndex,
      }),
    );
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
    await prefs.setString(
      '$_studyStatePrefix$tableName',
      jsonEncode({'revealed': revealed, 'rowOrder': rowOrder}),
    );
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

  static const String _personalPrefix = 'personal_results/';

  // Earlier versions stored defaults with study state. Migrate values that
  // differ from the cached table defaults into the sparse override database.
  Future<void> _migratePersonalResults(SharedPreferences prefs) async {
    for (final key
        in prefs
            .getKeys()
            .where((key) => key.startsWith(_rowDataPrefix))
            .toList()) {
      final rows = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      final name = key.substring(_rowDataPrefix.length);
      final personalKey = '$_personalPrefix$name';
      final personal = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(personalKey) ?? '{}') as Map,
      );
      final rawTable = prefs.getString('$_tablePrefix$name');
      final table = rawTable == null
          ? null
          : KnowledgeTable.deserialize(rawTable);
      var changed = false;
      for (final row in rows.entries) {
        final value = row.value as Map<String, dynamic>;
        if (!value.containsKey('importance') &&
            !value.containsKey('success') &&
            !value.containsKey('difficulty'))
          continue;
        changed = true;
        final importance = value.remove('importance');
        final success = value.remove('success') ?? value.remove('difficulty');
        value.remove('difficulty');
        if (!personal.containsKey(row.key)) {
          final overrides = <String, dynamic>{
            if (importance is int &&
                importance != (table?.importance[row.key] ?? 5))
              'importance': importance.clamp(1, 10),
            if (success is int && success != 5) 'success': success.clamp(1, 10),
          };
          if (overrides.isNotEmpty) personal[row.key] = overrides;
        }
      }
      if (changed) {
        if (personal.isEmpty) {
          await prefs.remove(personalKey);
        } else {
          await prefs.setString(personalKey, jsonEncode(personal));
        }
        await prefs.setString(key, jsonEncode(rows));
      }
    }
  }

  Future<Map<String, Map<String, RowSaveData>>> loadPersonalResults() async {
    final prefs = await SharedPreferences.getInstance();
    await _migratePersonalResults(prefs);
    final result = <String, Map<String, RowSaveData>>{};
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith(_personalPrefix),
    )) {
      final rows = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      result[key.substring(_personalPrefix.length)] = rows.map(
        (name, value) =>
            MapEntry(name, RowSaveData.fromJson(value as Map<String, dynamic>)),
      );
    }
    return result;
  }

  Future<void> _savePersonalTable(
    String name,
    Map<String, RowSaveData> rows,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final personal = <String, dynamic>{
      for (final row in rows.entries)
        if (row.value.importance != null || row.value.success != null)
          row.key: {
            if (row.value.importance != null)
              'importance': row.value.importance,
            if (row.value.success != null) 'success': row.value.success,
          },
    };
    if (personal.isEmpty) {
      await prefs.remove('$_personalPrefix$name');
    } else {
      await prefs.setString('$_personalPrefix$name', jsonEncode(personal));
    }
  }

  Future<void> replacePersonalResults(
    Map<String, Map<String, RowSaveData>> results,
  ) async {
    await clearPersonalResults();
    for (final table in results.entries) {
      await _savePersonalTable(table.key, table.value);
    }
  }

  Future<void> clearPersonalResults() async {
    final prefs = await SharedPreferences.getInstance();
    await _migratePersonalResults(prefs);
    for (final key
        in prefs
            .getKeys()
            .where(
              (key) =>
                  key.startsWith(_personalPrefix) ||
                  key.startsWith(_difficultiesPrefix),
            )
            .toList()) {
      await prefs.remove(key);
    }
  }

  /// Keep study state separate from optional personal results overrides.
  Future<void> saveTableRowData(
    String tableName,
    Map<String, RowSaveData> rowData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await _migratePersonalResults(prefs);
    await prefs.setString(
      '$_rowDataPrefix$tableName',
      jsonEncode({
        for (final row in rowData.entries)
          row.key: {
            'rowOrder': row.value.rowOrder,
            'revealed': row.value.revealed,
          },
      }),
    );
    await _savePersonalTable(tableName, rowData);
  }

  Future<Map<String, RowSaveData>?> loadTableRowData(String tableName) async {
    final personal = (await loadPersonalResults())[tableName] ?? {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_rowDataPrefix$tableName');
    if (raw == null && personal.isEmpty) return null;
    final decoded = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
    final result = decoded.map(
      (key, value) =>
          MapEntry(key, RowSaveData.fromJson(value as Map<String, dynamic>)),
    );
    for (final row in personal.entries) {
      final study = result[row.key];
      result[row.key] = RowSaveData(
        rowOrder: study?.rowOrder ?? result.length,
        revealed: study?.revealed ?? const [],
        importance: row.value.importance,
        success: row.value.success,
      );
    }
    return result;
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
