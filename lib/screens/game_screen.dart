import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../models/game_session.dart';
import '../models/knowledge_table.dart';
import '../models/row_save_data.dart';
import '../services/storage_service.dart';

class GameScreen extends StatefulWidget {
  final List<KnowledgeTable> tables;
  final GameSettings settings;
  final Future<void> Function()? onRatingsChanged;
  final Random? random;

  const GameScreen({
    super.key,
    required this.tables,
    required this.settings,
    this.onRatingsChanged,
    this.random,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _storage = StorageService();
  final _scroll = ScrollController();
  GameSession? _session;
  List<bool> _revealed = [];
  final Map<int, List<bool>> _questionReveals = {};
  bool _loading = true;
  bool _saving = false;
  bool _allowPop = false;
  bool _exitDialogOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  Future<void> _newRound() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = <GameEntry>[];
      for (final table in widget.tables) {
        if (widget.settings.selectedTables != null &&
            !widget.settings.selectedTables!.contains(table.name))
          continue;
        entries.addAll(
          GameEntry.fromTable(table, await _storage.ensureTableRowData(table)),
        );
      }
      if (!mounted) return;
      setState(() {
        _questionReveals.clear();
        _session = GameSession(
          entries: entries,
          settings: widget.settings,
          random: widget.random,
        );
        _prepareQuestion();
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not start game: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prepareQuestion() {
    final entry = _session?.current;
    _revealed = _questionReveals.putIfAbsent(
      _session!.questionNumber,
      () => List.generate(
        entry?.cells.length ?? 0,
        (index) => index + 1 == widget.settings.autoOpenColumn,
      ),
    );
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _navigateQuestion({required bool forward}) {
    if (_saving) return;
    setState(() {
      if (forward) {
        _session!.goForward();
      } else {
        _session!.goBack();
      }
      _prepareQuestion();
    });
  }

  Future<void> _persist(GameEntry entry, {RowSaveData? result}) async {
    final saved = await _storage.ensureTableRowData(entry.table);
    final previous = saved[entry.key];
    final updated = result ?? entry.results;
    saved[entry.key] = RowSaveData(
      rowOrder: previous?.rowOrder ?? saved.length,
      revealed: previous?.revealed ?? const [],
      importance: updated.importance,
      failedCount: updated.failedCount,
      almostCount: updated.almostCount,
      successCount: updated.successCount,
    );
    await _storage.saveTableRowData(entry.table.name, saved);
  }

  Future<void> _notifyChanged() async {
    try {
      await widget.onRatingsChanged?.call();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved locally. Autosync failed: $error')),
        );
    }
  }

  Future<void> _changeImportance(int delta) async {
    if (_saving) return;
    final entry = _session!.current!;
    final previous = entry.results;
    setState(() {
      _saving = true;
      entry.results = entry.results.withImportance(
        (entry.importance + delta).clamp(0, 10),
      );
    });
    try {
      await _persist(entry);
      unawaited(_notifyChanged());
    } catch (error) {
      entry.results = previous;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save Importance: $error')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _answer(GameAnswer answer) async {
    if (_saving || !_revealed.every((value) => value)) {
      return;
    }
    final entry = _session!.current!;
    setState(() => _saving = true);
    try {
      final result = _session!.resultForAnswer(answer);
      await _persist(entry, result: result);
      unawaited(_notifyChanged());
      if (!mounted) return;
      setState(() {
        _session!.answer(answer);
        _prepareQuestion();
      });
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save result: $error')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestExit() async {
    if (_saving || _exitDialogOpen) return;
    _exitDialogOpen = true;
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit game?'),
        content: const Text(
          'Your rating changes are saved. Round progress will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exit game'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (exit == true && mounted) _backToMain();
  }

  void _showQuestionInfo() {
    final session = _session!;
    final entry = session.current!;
    final weight = session.weightDetails(entry);
    final mean = session.meanWeight(entry);
    final meanLabel = mean > 0 && mean < 0.01
        ? mean.toStringAsPrecision(3)
        : mean.toStringAsFixed(2);
    final relativeWeight = session.relativeWeight(entry);
    const formulas = {
      'sd: Success Delta': 'sd = Success − Failed',
      'as: Adjusted Success': 'as = max sd − sd',
      'aa: Adjusted Appearance': 'aa = max a − Appeared',
    };
    Widget values(List<(String, String)> rows) => Table(
      columnWidths: const {0: FlexColumnWidth(), 1: IntrinsicColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows
          .expand(
            (row) => [
              if (formulas[row.$1] case final formula?)
                TableRow(
                  children: [
                    Text(formula, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox.shrink(),
                  ],
                ),
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 1, 12, 1),
                    child: Text(row.$1),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.end,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
            ],
          )
          .toList(),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Question info'),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                values([
                  (
                    'In-table Importance',
                    '${entry.table.importance[entry.key] ?? 0}',
                  ),
                  (
                    'Overridden Importance',
                    entry.personalImportance?.toString() ?? 'Unset',
                  ),
                  ('Failed', '${entry.failedCount}'),
                  ('Almost', '${entry.almostCount}'),
                  ('Success', '${entry.successCount}'),
                  ('Appeared', '${entry.appeared}'),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Weight at round start',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                values([
                  ('ui: Used Importance', '${weight.usedImportance}'),
                  ('sd: Success Delta', '${weight.successDelta}'),
                  ('max sd: Max Success Delta', '${weight.maxSuccessDelta}'),
                  ('as: Adjusted Success', '${weight.adjustedSuccess}'),
                  ('max a: Max Appearance', '${weight.maxAppeared}'),
                  ('aa: Adjusted Appearance', '${weight.adjustedAppearance}'),
                  ('iw: Importance Weight', '${weight.importanceWeight}'),
                  ('sw: Success Weight', '${weight.successWeight}'),
                  ('aw: Appearance Weight', '${weight.appearanceWeight}'),
                ]),
                const SizedBox(height: 4),
                const Text('Weight = ui × iw + as × sw + aa × aw'),
                const SizedBox(height: 2),
                Text(
                  'Weight = ${weight.usedImportance} × ${weight.importanceWeight} + ${weight.adjustedSuccess} × ${weight.successWeight} + ${weight.adjustedAppearance} × ${weight.appearanceWeight}',
                ),
                const SizedBox(height: 4),
                Text(
                  'Weight = ${weight.total}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text('Mean Weight = $meanLabel'),
                const SizedBox(height: 2),
                Text(
                  mean == 0
                      ? 'Relative Weight = 1.00'
                      : 'Relative Weight = ${weight.total} / $meanLabel = ${relativeWeight.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 3),
                Text(
                  mean == 0
                      ? 'All remaining weights are zero, so each question has equal chance.'
                      : 'Relative Weight shows how likely this question was to be selected compared with the average question in the pool at that draw.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!widget.settings.weighted)
                  const Text('Equal Chance is selected.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _backToMain() {
    setState(() => _allowPop = true);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _summary(GameSession session) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_outlined, size: 56),
          const SizedBox(height: 16),
          const Text(
            'Round complete',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text('${session.answered} questions answered'),
          const SizedBox(height: 20),
          Text('I knew: ${session.results[GameAnswer.knew]}'),
          Text('Almost: ${session.results[GameAnswer.almost]}'),
          Text('Failed: ${session.results[GameAnswer.failed]}'),
          const SizedBox(height: 12),
          Text(
            'Result: ${session.answered == 0 ? 0 : (session.results[GameAnswer.knew]! * 100 / session.answered).round()}% knew',
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => setState(() {
              session.reviewHistory();
              _prepareQuestion();
            }),
            child: const Text('Review Questions'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _newRound, child: const Text('New Round')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _backToMain,
            child: const Text('Back to Main Menu'),
          ),
        ],
      ),
    ),
  );

  Widget _question(GameSession session) {
    final entry = session.current!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  entry.table.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Text('Importance:', style: TextStyle(fontSize: 12)),
              IconButton(
                iconSize: 18,
                tooltip: 'Decrease Importance',
                onPressed: !_saving && entry.importance > 0
                    ? () => _changeImportance(-1)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Text('${entry.importance}', style: const TextStyle(fontSize: 12)),
              IconButton(
                iconSize: 18,
                tooltip: 'Increase Importance',
                onPressed: !_saving && entry.importance < 10
                    ? () => _changeImportance(1)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            itemCount: entry.cells.length,
            itemBuilder: (context, index) => Card(
              color: _revealed[index]
                  ? Theme.of(context).colorScheme.surface
                  : Theme.of(context).colorScheme.secondaryContainer,
              child: InkWell(
                onTap: _saving
                    ? null
                    : () =>
                          setState(() => _revealed[index] = !_revealed[index]),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_revealed[index]) ...[
                        Text(
                          entry.headers[index],
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        _revealed[index]
                            ? (entry.cells[index].isEmpty
                                  ? '—'
                                  : entry.cells[index])
                            : 'Tap to reveal',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: _revealed[index]
                              ? _infoFontSize(
                                  entry.cells[index],
                                  entry.table.textSize ?? 20,
                                )
                              : 18,
                          color: _revealed[index]
                              ? null
                              : Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer
                                    .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _infoFontSize(String text, double baseSize) {
    final length = text.runes.length;
    // Account for deliberate line breaks as well as the amount of text.
    final amount = max(length, text.split('\n').length * 30);
    final scale = amount <= 60 ? 1.0 : sqrt(60 / amount);
    return (baseSize * scale).clamp(min(14.0, baseSize), baseSize);
  }

  Widget _ratingLabel(String label, bool selected) => Semantics(
    selected: selected,
    child: selected
        ? Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [const Icon(Icons.check, size: 16), Text(label)],
          )
        : Text(label),
  );

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final playing = !_loading && _error == null && session?.current != null;
    final currentAnswer = session?.currentAnswer;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Exit game',
            onPressed: _saving ? null : _requestExit,
            icon: const Icon(Icons.exit_to_app),
          ),
          title: Text(
            playing
                ? 'Question ${session!.questionNumber} / ${session.total}'
                : 'Play',
          ),
          actions: [
            if (playing && widget.settings.weighted)
              Text(
                'RW=${session!.relativeWeight(session.current!).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (playing)
              IconButton(
                iconSize: 18,
                tooltip: 'Question info',
                onPressed: _showQuestionInfo,
                icon: const Icon(Icons.info_outline),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _newRound,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : session!.entries.isEmpty
            ? const Center(child: Text('No entries in the selected tables.'))
            : session.finished
            ? _summary(session)
            : _question(session),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (playing)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: !_saving && session!.canGoBack
                            ? () => _navigateQuestion(forward: false)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      TextButton.icon(
                        onPressed: !_saving && session!.canGoForward
                            ? () => _navigateQuestion(forward: true)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next'),
                      ),
                    ],
                  ),
                if (playing && session!.roundComplete)
                  TextButton(
                    onPressed: () => setState(() => session.showSummary()),
                    child: const Text('Back to Summary'),
                  ),
                if (playing)
                  if (!_revealed.every((value) => value))
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _revealed.fillRange(
                                  0,
                                  _revealed.length,
                                  true,
                                ),
                              ),
                        child: const Text('Show Answer'),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving
                                ? null
                                : () => _answer(GameAnswer.failed),
                            child: _ratingLabel(
                              'Failed',
                              currentAnswer == GameAnswer.failed,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => _answer(GameAnswer.almost),
                            child: _ratingLabel(
                              'Almost',
                              currentAnswer == GameAnswer.almost,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving
                                ? null
                                : () => _answer(GameAnswer.knew),
                            child: _ratingLabel(
                              'I knew',
                              currentAnswer == GameAnswer.knew,
                            ),
                          ),
                        ),
                      ],
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
