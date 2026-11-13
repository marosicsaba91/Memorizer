import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/game_session.dart';
import '../models/knowledge_table.dart';
import '../services/storage_service.dart';

class GameSetupDialog extends StatefulWidget {
  final List<KnowledgeTable> tables;
  const GameSetupDialog({super.key, required this.tables});

  @override
  State<GameSetupDialog> createState() => _GameSetupDialogState();
}

class _GameSetupDialogState extends State<GameSetupDialog> {
  bool _infinite = false;
  final _countController = TextEditingController(text: '10');
  int? get _count => int.tryParse(_countController.text);
  bool get _validCount => _count != null && _count! >= 1;
  int _importanceWeight = 1;
  int _lowSuccessWeight = 2;
  bool _allTables = true;
  bool _weighted = false;
  final Set<String> _selected = {};

  final _storage = StorageService();
  bool _loading = true;
  Future<void> _pendingSave = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final json = await _storage.loadGameSettings();
    if (!mounted) return;
    if (json != null) {
      final settings = GameSettings.fromJson(json);
      _infinite = settings.questionCount == null;
      final finiteCount = json['finiteQuestionCount'];
      _countController.text =
          (finiteCount is int && finiteCount > 0
                  ? finiteCount
                  : settings.questionCount ?? 10)
              .toString();
      _allTables = settings.selectedTables == null;
      _selected.addAll(settings.selectedTables ?? {});
      _weighted = settings.weighted;
      _importanceWeight = settings.importanceWeight;
      _lowSuccessWeight = settings.lowSuccessWeight;
    }
    setState(() => _loading = false);
  }

  GameSettings get _settings => GameSettings(
    questionCount: _infinite ? null : _count,
    selectedTables: _allTables ? null : Set.of(_selected),
    weighted: _weighted,
    importanceWeight: _importanceWeight,
    lowSuccessWeight: _lowSuccessWeight,
  );

  void _change(VoidCallback update) {
    setState(update);
    if (!_validCount) return;
    final settings = _settings;
    final count = _count!;
    _pendingSave = _pendingSave
        .then((_) => _storage.saveGameSettings(settings, count))
        .catchError((Object error) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not save game settings: $error',
                ),
              ),
            );
        });
  }

  Future<void> _start() async {
    await _pendingSave;
    if (mounted) Navigator.pop(context, _settings);
  }

  void _changeCount(int direction) {
    final current = _count;
    if (current == null || current < 1) return;
    final step = max(1, (0.1 * current).round());
    _change(
      () => _countController.text = '${max(1, current + direction * step)}',
    );
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  Widget _weightControl(String label, int value, ValueChanged<int> onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '$value',
                  onChanged: (value) => onChanged(value.round()),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text('$value', textAlign: TextAlign.center),
              ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set up game'),
    content: SizedBox(
      width: 420,
      child: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Question count'),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Finite')),
                      ButtonSegment(value: true, label: Text('Infinite')),
                    ],
                    selected: {_infinite},
                    onSelectionChanged: (value) =>
                        _change(() => _infinite = value.first),
                  ),
                  if (!_infinite) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Fewer questions',
                          onPressed: _validCount && _count! > 1
                              ? () => _changeCount(-1)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            key: const ValueKey('question-count'),
                            controller: _countController,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) => _change(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Questions',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'More questions',
                          onPressed: _validCount ? () => _changeCount(1) : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    if (!_validCount)
                      const Text('Enter a whole number of at least 1.'),
                  ],
                  const SizedBox(height: 20),
                  const Text('Included'),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('All tables')),
                      ButtonSegment(
                        value: false,
                        label: Text('Selected tables'),
                      ),
                    ],
                    selected: {_allTables},
                    onSelectionChanged: (value) =>
                        _change(() => _allTables = value.first),
                  ),
                  if (!_allTables)
                    ...widget.tables.map(
                      (table) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(table.name),
                        value: _selected.contains(table.name),
                        onChanged: (value) => _change(() {
                          if (value == true) {
                            _selected.add(table.name);
                          } else {
                            _selected.remove(table.name);
                          }
                        }),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text('Question selection'),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Equal Chance')),
                      ButtonSegment(
                        value: true,
                        label: Text('Aggregated Chance'),
                      ),
                    ],
                    selected: {_weighted},
                    onSelectionChanged: (value) =>
                        _change(() => _weighted = value.first),
                  ),
                  if (_weighted) ...[
                    const SizedBox(height: 12),
                    _weightControl(
                      'More important items',
                      _importanceWeight,
                      (value) => _change(() => _importanceWeight = value),
                    ),
                    _weightControl(
                      'Items with low success rate',
                      _lowSuccessWeight,
                      (value) => _change(() => _lowSuccessWeight = value),
                    ),
                    if (_importanceWeight == 0 && _lowSuccessWeight == 0)
                      const Text(
                        'Both weights are zero, so entries have equal chance.',
                      ),
                  ],
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            _loading ||
                widget.tables.isEmpty ||
                (!_allTables && _selected.isEmpty) ||
                (!_infinite && !_validCount)
            ? null
            : _start,
        child: const Text('Start Game'),
      ),
    ],
  );
}
