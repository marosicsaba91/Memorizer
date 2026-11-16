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
  final int lowAppearanceWeight;
  final int autoOpenColumn;

  const GameSettings({
    this.questionCount = 10,
    this.selectedTables,
    this.weighted = false,
    this.importanceWeight = 1,
    this.lowSuccessWeight = 2,
    this.autoOpenColumn = 1,
    this.lowAppearanceWeight = 0,
  }) : assert(importanceWeight >= 0 && importanceWeight <= 100),
       assert(lowAppearanceWeight >= 0 && lowAppearanceWeight <= 100),
       assert(lowSuccessWeight >= 0 && lowSuccessWeight <= 100);

  Map<String, dynamic> toJson() => {
    'questionCount': questionCount,
    'selectedTables': selectedTables?.toList(),
    'weighted': weighted,
    'importanceWeight': importanceWeight,
    'lowSuccessWeight': lowSuccessWeight,
    'autoOpenColumn': autoOpenColumn,
    'lowAppearanceWeight': lowAppearanceWeight,
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
    lowAppearanceWeight: json['lowAppearanceWeight'] is int
        ? (json['lowAppearanceWeight'] as int).clamp(0, 100)
        : 0,
    autoOpenColumn: json['autoOpenColumn'] is int
        ? json['autoOpenColumn'] as int
        : 1,
    importanceWeight: json['importanceWeight'] is int
        ? (json['importanceWeight'] as int).clamp(0, 100)
        : 1,
    lowSuccessWeight: json['lowSuccessWeight'] is int
        ? (json['lowSuccessWeight'] as int).clamp(0, 100)
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
  int appeared;

  GameEntry({
    required this.table,
    required this.cells,
    required this.headers,
    this.personalImportance,
    this.personalSuccess,
    this.appeared = 0,
  });

  String get key => cells.first;
  int get importance => personalImportance ?? table.importance[key] ?? 5;
  int get success => personalSuccess ?? 5;

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
            appeared: saved[row.first]?.appeared ?? 0,
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
  final Set<(String, String)> _shown = {};

  double selectionWeight(GameEntry entry) {
    final minimum = entries.map((e) => e.appeared).reduce(min);
    final maximum = entries.map((e) => e.appeared).reduce(max);
    final normalized = maximum == minimum
        ? 0.0
        : (entry.appeared - minimum) / (maximum - minimum);
    return max(
      1.0,
          entry.importance * settings.importanceWeight +
          (11 - entry.success) * settings.lowSuccessWeight +
          (1 - normalized) * 10 * settings.lowAppearanceWeight,
    );
  }

  final Map<GameAnswer, int> results = {
    for (final answer in GameAnswer.values) answer: 0,
  };
  final List<GameEntry> _history = [];
  final List<GameAnswer?> _answers = [];
  final Map<GameEntry, int?> _initialSuccess = {};
  int _position = 0;
  bool _completed = false;

  GameEntry? get current =>
      _completed || _history.isEmpty ? null : _history[_position];
  int get questionNumber => _position + 1;
  bool get isReviewing => _position < answered;
  bool get canGoBack => !finished && _position > 0;
  bool get canGoForward => !finished && _position < _history.length - 1;
  GameAnswer? get currentAnswer => finished ? null : _answers[_position];

  int? successForAnswer(GameAnswer answer) {
    final entry = current!;
    var success = _initialSuccess[entry];
    for (var i = 0; i < _history.length; i++) {
      if (!identical(_history[i], entry)) continue;
      final grade = i == _position ? answer : _answers[i];
      if (grade == null || grade == GameAnswer.almost) continue;
      success = ((success ?? 5) + (grade == GameAnswer.knew ? 1 : -1)).clamp(
        1,
        10,
      );
    }
    return success;
  }

  void goBack() {
    if (canGoBack) _position--;
  }

  void goForward() {
    if (canGoForward) _position++;
  }

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
    final previous = currentAnswer;
    _answers[_position] = answer;
    if (previous != null) {
      results[previous] = results[previous]! - 1;
      results[answer] = results[answer]! + 1;
      return;
    }
    results[answer] = results[answer]! + 1;
    if (total != null && answered >= total!) {
      _completed = true;
    } else {
      _next();
    }
  }

  void _next() {
    if (settings.questionCount == null) _remaining.clear();
    if (_remaining.isEmpty) _remaining.addAll(entries);
    var index = 0;
    final weights = settings.weighted
        ? _remaining.map(selectionWeight).toList()
        : <double>[];
    final sum = weights.fold<double>(0, (sum, weight) => sum + weight);
    if (sum > 0) {
      var ticket = random.nextDouble() * sum;
      for (; index < _remaining.length - 1; index++) {
        ticket -= weights[index];
        if (ticket < 0) break;
      }
    } else {
      index = random.nextInt(_remaining.length);
    }
    _history.add(_remaining.removeAt(index));
    _answers.add(null);
    final entry = _history.last;
    if (_shown.add((entry.table.name, entry.key))) entry.appeared++;
    _initialSuccess.putIfAbsent(entry, () => entry.personalSuccess);
    _position = _history.length - 1;
  }
}
