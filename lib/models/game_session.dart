import 'dart:math';

import 'knowledge_table.dart';
import 'row_save_data.dart';

class GameSettings {
  /// Null means an infinite round.
  final int? questionCount;
  final Set<String>? selectedTables;
  final bool weighted;
  final int importanceWeight;
  final int lowSuccessWeight;

  const GameSettings({
    this.questionCount = 10,
    this.selectedTables,
    this.weighted = false,
    this.importanceWeight = 1,
    this.lowSuccessWeight = 2,
  }) : assert(importanceWeight >= 0 && importanceWeight <= 10),
       assert(lowSuccessWeight >= 0 && lowSuccessWeight <= 10);

  Map<String, dynamic> toJson() => {
    'questionCount': questionCount,
    'selectedTables': selectedTables?.toList(),
    'weighted': weighted,
    'importanceWeight': importanceWeight,
    'lowSuccessWeight': lowSuccessWeight,
  };

  factory GameSettings.fromJson(Map<String, dynamic> json) => GameSettings(
    questionCount:
        json.containsKey('questionCount') && json['questionCount'] == null
        ? null
        : (json['questionCount'] is int && json['questionCount'] > 0
              ? json['questionCount'] as int
              : 10),
    selectedTables: json['selectedTables'] is List
        ? (json['selectedTables'] as List).whereType<String>().toSet()
        : null,
    weighted: json['weighted'] == true,
    importanceWeight: json['importanceWeight'] is int
        ? (json['importanceWeight'] as int).clamp(0, 10)
        : 1,
    lowSuccessWeight: json['lowSuccessWeight'] is int
        ? (json['lowSuccessWeight'] as int).clamp(0, 10)
        : 2,
  );
}

enum GameAnswer { failed, almost, knew }

class GameEntry {
  final KnowledgeTable table;
  final List<String> cells;
  final List<String> headers;
  int? personalImportance;
  int? personalSuccess;

  GameEntry({
    required this.table,
    required this.cells,
    required this.headers,
    this.personalImportance,
    this.personalSuccess,
  });

  String get key => cells.first;
  int get importance => personalImportance ?? table.importance[key] ?? 5;
  int get success => personalSuccess ?? 5;
  int weight(GameSettings settings) =>
      importance * settings.importanceWeight +
      (11 - success) * settings.lowSuccessWeight;

  static List<GameEntry> fromTable(
    KnowledgeTable table,
    Map<String, RowSaveData> saved,
  ) {
    if (table.rows.isEmpty) return [];
    final hasHeader = table.rows.first.any(
      (cell) => cell.isNotEmpty && double.tryParse(cell) == null,
    );
    final width = table.rows.fold<int>(
      0,
      (width, row) => max(width, row.length),
    );
    if (width == 0) return [];
    final headers = List.generate(
      width,
      (i) =>
          hasHeader &&
              i < table.rows.first.length &&
              table.rows.first[i].isNotEmpty
          ? table.rows.first[i]
          : 'Column ${i + 1}',
    );
    return table.rows
        .skip(hasHeader ? 1 : 0)
        .where((row) => row.isNotEmpty && row.first.trim().isNotEmpty)
        .map(
          (row) => GameEntry(
            table: table,
            cells: List.generate(width, (i) => i < row.length ? row[i] : ''),
            headers: headers,
            personalImportance: saved[row.first]?.importance,
            personalSuccess: saved[row.first]?.success,
          ),
        )
        .toList();
  }
}

class GameSession {
  final List<GameEntry> entries;
  final GameSettings settings;
  final Random random;
  final List<GameEntry> _remaining = [];
  final Map<GameAnswer, int> results = {
    for (final answer in GameAnswer.values) answer: 0,
  };
  GameEntry? current;

  GameSession({required this.entries, required this.settings, Random? random})
    : random = random ?? Random() {
    if (settings.questionCount != null && settings.questionCount! < 1) {
      throw ArgumentError('Question count must be positive.');
    }
    if (entries.isNotEmpty) _next();
  }

  int get answered => results.values.fold(0, (total, count) => total + count);
  int? get total => settings.questionCount == null
      ? null
      : min(settings.questionCount!, entries.length);
  bool get finished => current == null;

  void answer(GameAnswer answer) {
    if (finished) return;
    results[answer] = results[answer]! + 1;
    if (total != null && answered >= total!) {
      current = null;
    } else {
      _next();
    }
  }

  void _next() {
    if (settings.questionCount == null) _remaining.clear();
    if (_remaining.isEmpty) _remaining.addAll(entries);
    var index = 0;
    if (settings.weighted &&
        (settings.importanceWeight > 0 || settings.lowSuccessWeight > 0)) {
      var ticket = random.nextInt(
        _remaining.fold<int>(0, (sum, entry) => sum + entry.weight(settings)),
      );
      for (; index < _remaining.length - 1; index++) {
        ticket -= _remaining[index].weight(settings);
        if (ticket < 0) break;
      }
    } else {
      index = random.nextInt(_remaining.length);
    }
    current = _remaining.removeAt(index);
  }
}
