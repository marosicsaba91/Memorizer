import 'dart:math';

import 'knowledge_table.dart';
import 'row_save_data.dart';

class GameSettings {
  /// Null selects all included questions.
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
  RowSaveData results;

  GameEntry({
    required this.table,
    required this.cells,
    required this.headers,
    RowSaveData? results,
  }) : results = results ?? const RowSaveData(rowOrder: 0, revealed: []);

  String get key => cells.first;
  int get importance => results.importance ?? table.importance[key] ?? 0;
  int? get personalImportance => results.importance;
  int get appeared => results.appeared;
  int get failedCount => results.failedCount;
  int get almostCount => results.almostCount;
  int get successCount => results.successCount;

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
      (index) =>
          hasHeader &&
              index < table.rows.first.length &&
              table.rows.first[index].isNotEmpty
          ? KnowledgeTable.columnLabel(table.rows.first[index])
          : 'Column ${index + 1}',
    );
    return table.rows
        .skip(hasHeader ? 1 : 0)
        .where((row) => row.isNotEmpty && row.first.trim().isNotEmpty)
        .map(
          (row) => GameEntry(
            table: table,
            headers: headers,
            cells: List.generate(
              width,
              (index) => index < row.length ? row[index] : '',
            ),
            results: saved[row.first],
          ),
        )
        .toList();
  }
}

class QuestionWeight {
  final int usedImportance;
  final int successDelta;
  final int maxSuccessDelta;
  final int appeared;
  final int maxAppeared;
  final int importanceWeight;
  final int successWeight;
  final int appearanceWeight;

  const QuestionWeight({
    required this.usedImportance,
    required this.successDelta,
    required this.maxSuccessDelta,
    required this.appeared,
    required this.maxAppeared,
    required this.importanceWeight,
    required this.successWeight,
    required this.appearanceWeight,
  });

  int get adjustedSuccess => maxSuccessDelta - successDelta;
  int get adjustedAppearance => maxAppeared - appeared;
  int get importanceSubtotal => usedImportance * importanceWeight;
  int get successSubtotal => adjustedSuccess * successWeight;
  int get appearanceSubtotal => adjustedAppearance * appearanceWeight;
  int get total => importanceSubtotal + successSubtotal + appearanceSubtotal;
}

class GameSession {
  final List<GameEntry> entries;
  final GameSettings settings;
  final Random random;
  final List<GameEntry> _remaining = [];
  final Map<GameEntry, QuestionWeight> _weights = {};
  final Map<GameEntry, double> _selectionMeans = {};
  final Map<GameAnswer, int> results = {
    for (final answer in GameAnswer.values) answer: 0,
  };
  final List<GameEntry> _history = [];
  final List<GameAnswer?> _answers = [];
  int _position = 0;
  bool _completed = false;

  GameSession({
    required List<GameEntry> entries,
    required this.settings,
    Random? random,
  }) : entries = _uniqueEntries(entries),
       random = random ?? Random() {
    if (settings.questionCount != null && settings.questionCount! < 1) {
      throw ArgumentError('Question count must be positive.');
    }
    if (this.entries.isEmpty) return;
    final maxSuccessDelta = this.entries
        .map((entry) => entry.successCount - entry.failedCount)
        .reduce(max);
    final maxAppeared = this.entries.map((entry) => entry.appeared).reduce(max);
    for (final entry in this.entries) {
      _weights[entry] = QuestionWeight(
        usedImportance: entry.importance,
        successDelta: entry.successCount - entry.failedCount,
        maxSuccessDelta: maxSuccessDelta,
        appeared: entry.appeared,
        maxAppeared: maxAppeared,
        importanceWeight: settings.importanceWeight,
        successWeight: settings.lowSuccessWeight,
        appearanceWeight: settings.lowAppearanceWeight,
      );
    }
    _remaining.addAll(this.entries);
    _next();
  }

  static List<GameEntry> _uniqueEntries(List<GameEntry> entries) {
    final seen = <(String, String)>{};
    return entries
        .where((entry) => seen.add((entry.table.name, entry.key)))
        .toList();
  }

  GameEntry? get current =>
      _completed || _history.isEmpty ? null : _history[_position];
  List<GameEntry> get history => List.unmodifiable(_history);
  int get questionNumber => _position + 1;
  int get answered => results.values.fold(0, (total, count) => total + count);
  int get total =>
      min(settings.questionCount ?? entries.length, entries.length);
  bool get finished => current == null;
  bool get roundComplete => answered >= total;
  bool get isReviewing => !finished && currentAnswer != null;
  bool get canGoBack => !finished && _position > 0;
  bool get canGoForward => !finished && _position < _history.length - 1;
  GameAnswer? get currentAnswer => finished ? null : _answers[_position];
  QuestionWeight weightDetails(GameEntry entry) => _weights[entry]!;
  int selectionWeight(GameEntry entry) => weightDetails(entry).total;
  double meanWeight(GameEntry entry) => _selectionMeans[entry]!;
  double relativeWeight(GameEntry entry) {
    final mean = meanWeight(entry);
    return mean == 0 ? 1 : selectionWeight(entry) / mean;
  }

  RowSaveData resultForAnswer(GameAnswer answer) {
    final previous = currentAnswer;
    final saved = current!.results;
    int adjust(GameAnswer category, int count) =>
        count - (previous == category ? 1 : 0) + (answer == category ? 1 : 0);
    return RowSaveData(
      rowOrder: saved.rowOrder,
      revealed: saved.revealed,
      importance: saved.importance,
      comment: saved.comment,
      failedCount: adjust(GameAnswer.failed, saved.failedCount),
      almostCount: adjust(GameAnswer.almost, saved.almostCount),
      successCount: adjust(GameAnswer.knew, saved.successCount),
    );
  }

  void goBack() {
    if (canGoBack) _position--;
  }

  void goForward() {
    if (canGoForward) _position++;
  }

  void reviewHistory() {
    if (_history.isEmpty) return;
    _completed = false;
    _position = 0;
  }

  void showSummary() {
    if (roundComplete) _completed = true;
  }

  void answer(GameAnswer answer) {
    if (finished) return;
    final previous = currentAnswer;
    current!.results = resultForAnswer(answer);
    _answers[_position] = answer;
    if (previous != null) results[previous] = results[previous]! - 1;
    results[answer] = results[answer]! + 1;
    if (previous != null) return;
    if (answered >= total || _remaining.isEmpty) {
      _completed = true;
    } else {
      _next();
    }
  }

  void _next() {
    if (_remaining.isEmpty) {
      _completed = true;
      return;
    }
    final poolWeight = _remaining.fold<int>(
      0,
      (sum, entry) => sum + selectionWeight(entry),
    );
    final mean = poolWeight / _remaining.length;
    final sum = settings.weighted ? poolWeight : 0;
    var index = 0;
    if (sum > 0) {
      var ticket = random.nextDouble() * sum;
      for (; index < _remaining.length - 1; index++) {
        ticket -= selectionWeight(_remaining[index]);
        if (ticket < 0) break;
      }
    } else {
      index = random.nextInt(_remaining.length);
    }
    final selected = _remaining.removeAt(index);
    _selectionMeans[selected] = mean;
    _history.add(selected);
    _answers.add(null);
    _position = _history.length - 1;
  }
}
