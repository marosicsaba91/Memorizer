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
    _revealed = List.generate(entry?.cells.length ?? 0, (index) => index == 0);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _persist(GameEntry entry) async {
    final saved = await _storage.ensureTableRowData(entry.table);
    final previous = saved[entry.key];
    saved[entry.key] = RowSaveData(
      rowOrder: previous?.rowOrder ?? saved.length,
      revealed: previous?.revealed ?? const [],
      importance: entry.personalImportance,
      success: entry.personalSuccess,
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
    final previous = entry.personalImportance;
    setState(() {
      _saving = true;
      entry.personalImportance = (entry.importance + delta).clamp(1, 10);
    });
    try {
      await _persist(entry);
      unawaited(_notifyChanged());
    } catch (error) {
      entry.personalImportance = previous;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save Importance: $error')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _answer(GameAnswer answer) async {
    if (_saving || !_revealed.every((value) => value)) return;
    final entry = _session!.current!;
    final previous = entry.personalSuccess;
    setState(() => _saving = true);
    try {
      if (answer != GameAnswer.almost) {
        entry.personalSuccess =
            (entry.success + (answer == GameAnswer.knew ? 1 : -1)).clamp(1, 10);
        await _persist(entry);
        unawaited(_notifyChanged());
      }
      if (!mounted) return;
      setState(() {
        _session!.answer(answer);
        _prepareQuestion();
      });
    } catch (error) {
      entry.personalSuccess = previous;
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
                onPressed: !_saving && entry.importance > 1
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
                onTap: _revealed[index]
                    ? null
                    : () => setState(() => _revealed[index] = true),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        entry.headers[index],
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 12),
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

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final playing = !_loading && _error == null && session?.current != null;
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
                ? 'Question ${session!.answered + 1}${session.total == null ? '' : ' / ${session.total}'}'
                : 'Play',
          ),
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
                  if (!_revealed.every((value) => value))
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _revealed = List.filled(
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
                            child: const Text('Failed'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => _answer(GameAnswer.almost),
                            child: const Text('Almost'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving
                                ? null
                                : () => _answer(GameAnswer.knew),
                            child: const Text('I knew'),
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
