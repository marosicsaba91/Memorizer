import 'dart:math';

import 'package:flutter/material.dart';

import '../models/knowledge_table.dart';
import '../models/row_save_data.dart';
import '../services/storage_service.dart';

class KnowledgeTableScreen extends StatefulWidget {
  final KnowledgeTable table;

  const KnowledgeTableScreen({super.key, required this.table});

  @override
  State<KnowledgeTableScreen> createState() => _KnowledgeTableScreenState();
}

class _KnowledgeTableScreenState extends State<KnowledgeTableScreen> {
  final GlobalKey<PopupMenuButtonState<_FooterMenuAction>>
  _footerMenuButtonKey = GlobalKey<PopupMenuButtonState<_FooterMenuAction>>();
  final ScrollController _tableScrollController = ScrollController();

  late List<String> _headers;
  late List<List<String>> _dataRows;

  /// Revealed state: _revealed[origRowIdx][origColIdx].
  late List<List<bool>> _revealed;

  /// Current display order as a list of original row indices.
  late List<int> _displayOrder;

  /// Maps visual column position → original column index.
  late List<int> _columnOrder;

  /// Fractional widths for each visual data column (values sum to 1.0).
  late List<double> _colWidthFractions;

  /// Row anchor keys used for auto-scrolling to newly revealed rows.
  late List<GlobalKey> _rowKeys;

  int? _draggingColVisualIdx;
  int? _dragTargetVisualIdx;
  int? _lastOpenedRowIdx;
  int? _lastOpenedOrigColIdx;

  /// Per-row difficulty: 1–10, default 5.
  late List<int> _difficulties;

  late double _textSize;
  bool _lastSortRandomise = false;
  String _lastSortSeed = '';
  _DifficultyOrder _lastSortDifficultyOrder = _DifficultyOrder.ignore;

  final _storageService = StorageService();

  int get _numCols => _headers.length;

  // ── helpers ────────────────────────────────────────────────────

  bool _isRevealed(int origRowIdx, int visualColIdx) =>
      _revealed[origRowIdx][_columnOrder[visualColIdx]];

  bool _isLastOpened(int origRowIdx, int visualColIdx) =>
      _lastOpenedRowIdx == origRowIdx &&
      _lastOpenedOrigColIdx == _columnOrder[visualColIdx];

  void _setRevealed(int origRowIdx, int visualColIdx, bool value) {
    setState(() {
      final origColIdx = _columnOrder[visualColIdx];
      _revealed[origRowIdx][origColIdx] = value;
      if (value) {
        _lastOpenedRowIdx = origRowIdx;
        _lastOpenedOrigColIdx = origColIdx;
      }
    });
    _saveStudyState();
  }

  String _rowKeyForIndex(int origRowIdx) {
    final row = _dataRows[origRowIdx];
    return row.isNotEmpty ? row.first : '';
  }

  void _toggleRevealed(int origRowIdx, int visualColIdx) {
    setState(() {
      final origColIdx = _columnOrder[visualColIdx];
      _revealed[origRowIdx][origColIdx] = !_revealed[origRowIdx][origColIdx];
      if (_revealed[origRowIdx][origColIdx]) {
        _lastOpenedRowIdx = origRowIdx;
        _lastOpenedOrigColIdx = origColIdx;
      } else {
        _lastOpenedRowIdx = null;
        _lastOpenedOrigColIdx = null;
      }
    });
    _saveStudyState();
  }

  Future<void> _saveStudyState() async {
    final rowOrderByIndex = <int, int>{
      for (var pos = 0; pos < _displayOrder.length; pos++) _displayOrder[pos]: pos,
    };

    final rowData = <String, RowSaveData>{};
    for (var origIdx = 0; origIdx < _dataRows.length; origIdx++) {
      rowData[_rowKeyForIndex(origIdx)] = RowSaveData(
        rowOrder: rowOrderByIndex[origIdx] ?? origIdx,
        revealed: List<bool>.from(_revealed[origIdx], growable: false),
        difficulty: _difficulties[origIdx].clamp(1, 10),
      );
    }

    await _storageService.saveTableRowData(widget.table.name, rowData);
  }

  // ── init ───────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final rows = widget.table.rows;
    List<List<String>> dataRows = rows;

    // Determine the column count from the widest row.
    int numCols = rows.fold(0, (m, r) => r.length > m ? r.length : m);
    if (numCols < 1) numCols = 1;

    // Detect and extract an optional header row.
    List<String> headers = List.generate(numCols, (i) => 'Column ${i + 1}');
    if (rows.isNotEmpty) {
      final firstRow = rows.first;
      final looksLikeHeader = firstRow.any(
        (cell) => cell.isNotEmpty && double.tryParse(cell) == null,
      );
      if (looksLikeHeader) {
        headers = List.generate(
          numCols,
          (i) => i < firstRow.length && firstRow[i].isNotEmpty
              ? firstRow[i]
              : 'Column ${i + 1}',
        );
        dataRows = rows.skip(1).toList();
      }
    }

    _headers = headers;
    _dataRows = dataRows;
    _displayOrder = List.generate(_dataRows.length, (i) => i, growable: true);
    _columnOrder = List.generate(_numCols, (i) => i, growable: true);
    _colWidthFractions = List.filled(_numCols, 1.0 / _numCols, growable: true);
    _revealed = List.generate(
      _dataRows.length,
      (_) => List.filled(_numCols, false, growable: true),
      growable: true,
    );
    _rowKeys = List.generate(
      _dataRows.length,
      (_) => GlobalKey(),
      growable: true,
    );

    _difficulties = List.filled(_dataRows.length, 5, growable: true);
    _textSize = widget.table.textSize ?? 14.0;
    _loadTextSize();
    _loadInitialOrderingPreferences();
  }

  Future<void> _loadInitialOrderingPreferences() async {
    await _loadSortSettings();
    await _loadRowSaveData();
  }

  Future<void> _loadTextSize() async {
    final saved = await _storageService.loadTableTextSize(widget.table.name);
    if (!mounted) return;
    if (saved != null) setState(() => _textSize = saved);
  }

  Future<void> _loadSortSettings() async {
    final saved = await _storageService.loadTableSortSettings(widget.table.name);
    if (!mounted || saved == null) return;

    final randomise = saved['randomise'];
    final seed = saved['seed'];
    final diffOrderIndex = saved['difficultyOrderIndex'];

    if (randomise is bool && seed is String && diffOrderIndex is int) {
      if (diffOrderIndex >= 0 && diffOrderIndex < _DifficultyOrder.values.length) {
        setState(() {
          _lastSortRandomise = randomise;
          _lastSortSeed = seed;
          _lastSortDifficultyOrder = _DifficultyOrder.values[diffOrderIndex];
        });
      }
    }
  }

  Future<void> _loadRowSaveData() async {
    final saved = await _storageService.loadTableRowData(widget.table.name);
    if (!mounted || saved == null) return;

    final rowOrders = List<int>.generate(_dataRows.length, (i) => i);
    final revealed = List<List<bool>>.generate(
      _dataRows.length,
      (_) => List<bool>.filled(_numCols, false, growable: false),
      growable: false,
    );
    final difficulties = List<int>.filled(_dataRows.length, 5, growable: false);

    for (var origIdx = 0; origIdx < _dataRows.length; origIdx++) {
      final key = _rowKeyForIndex(origIdx);
      final rowSaveData = saved[key];
      if (rowSaveData == null) continue;

      rowOrders[origIdx] = rowSaveData.rowOrder;
      difficulties[origIdx] = rowSaveData.difficulty.clamp(1, 10);

      final rowRevealed = rowSaveData.revealed;
      for (var c = 0; c < _numCols; c++) {
        revealed[origIdx][c] = c < rowRevealed.length ? rowRevealed[c] : false;
      }
    }

    final order = List<int>.generate(_dataRows.length, (i) => i, growable: false)
      ..sort((a, b) {
        final cmp = rowOrders[a].compareTo(rowOrders[b]);
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    int? lastRow;
    int? lastCol;
    for (var r = 0; r < revealed.length; r++) {
      for (var c = 0; c < revealed[r].length; c++) {
        if (revealed[r][c]) {
          lastRow = r;
          lastCol = c;
        }
      }
    }

    setState(() {
      _difficulties = difficulties;
      _revealed = revealed;
      _displayOrder = List<int>.from(order, growable: true);
      _lastOpenedRowIdx = lastRow;
      _lastOpenedOrigColIdx = lastCol;
    });
  }

  Future<void> _saveSortSettings({
    required bool randomise,
    required String seed,
    required _DifficultyOrder diffOrder,
  }) async {
    await _storageService.saveTableSortSettings(
      widget.table.name,
      randomise: randomise,
      seed: seed,
      difficultyOrderIndex: diffOrder.index,
    );
  }

  Future<void> _saveDifficulty(int origRowIdx, int value) async {
    setState(() => _difficulties[origRowIdx] = value.clamp(1, 10));
    await _saveStudyState();
  }

  // ── heatmap ────────────────────────────────────────────────────

  /// Returns a row background color based on difficulty (1–10).
  /// 5 → white, <5 → cold (blue), >5 → warm (red).
  Color _difficultyColor(int difficulty) => switch (difficulty) {
    1 || _ when difficulty <= 1 => const Color.fromARGB(255, 72, 172, 122),
    2 => const Color.fromARGB(255, 117, 201, 128),
    3 => const Color.fromARGB(255, 185, 240, 159),
    4 => const Color.fromARGB(255, 235, 255, 204),
    5 => const Color.fromARGB(255, 255, 255, 255),
    6 => const Color.fromARGB(255, 255, 247, 204),
    7 => const Color.fromARGB(255, 255, 222, 180),
    8 => const Color.fromARGB(255, 255, 177, 146),
    9 => const Color.fromARGB(255, 250, 147, 129),
    _ => const Color.fromARGB(255, 248, 108, 108),
  };

  void _showDifficultyDialog(int origRowIdx) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final d = _difficulties[origRowIdx];
          return AlertDialog(
            title: const Text('Difficulty', textAlign: TextAlign.center),
            content: Text(
              d.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  if (d > 1) {
                    _saveDifficulty(origRowIdx, d - 1);
                    setDialogState(() {});
                  }
                },
                child: const Text('-1'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () {
                  if (d < 10) {
                    _saveDifficulty(origRowIdx, d + 1);
                    setDialogState(() {});
                  }
                },
                child: const Text('+1'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _tableScrollController.dispose();
    super.dispose();
  }

  void _scrollRowIntoView(int origRowIdx) {
    if (origRowIdx < 0 || origRowIdx >= _rowKeys.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _rowKeys[origRowIdx].currentContext;
      if (targetContext == null) return;

      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.7,
      );
    });
  }

  // ── button actions ─────────────────────────────────────────────

  void _showNext() {
    final totalCells = _displayOrder.length * _numCols;
    if (totalCells == 0) return;

    var startOffset = 0;
    if (_lastOpenedRowIdx != null && _lastOpenedOrigColIdx != null) {
      final rowPos = _displayOrder.indexOf(_lastOpenedRowIdx!);
      final colPos = _columnOrder.indexOf(_lastOpenedOrigColIdx!);
      if (rowPos != -1 && colPos != -1) {
        startOffset = rowPos * _numCols + colPos + 1;
      }
    }

    for (var step = 0; step < totalCells; step++) {
      final flatIndex = (startOffset + step) % totalCells;
      final rowPos = flatIndex ~/ _numCols;
      final visualColIdx = flatIndex % _numCols;
      final origRowIdx = _displayOrder[rowPos];
      if (!_isRevealed(origRowIdx, visualColIdx)) {
        _setRevealed(origRowIdx, visualColIdx, true);
        _scrollRowIntoView(origRowIdx);
        return;
      }
    }
  }

  int _deterministicHash(String seed) {
    int hash = 0;
    for (final codeUnit in seed.codeUnits) {
      hash = ((hash << 5) - hash) + codeUnit;
      hash &= 0x7fffffff; // Keep a stable positive 31-bit seed
    }
    return hash;
  }

  void _randomise({String? seed, _DifficultyOrder diffOrder = _DifficultyOrder.ignore}) {
    final normalizedSeed = seed?.trim() ?? '';
    final random = normalizedSeed.isEmpty
        ? Random()
        : Random(_deterministicHash(normalizedSeed));

    setState(() {
      // Start from canonical order so the same seed always yields the same result.
      _displayOrder = List.generate(_dataRows.length, (i) => i, growable: true);
      _displayOrder.shuffle(random);
      if (diffOrder != _DifficultyOrder.ignore) {
        _displayOrder.sort((a, b) => diffOrder == _DifficultyOrder.easierFirst
            ? _difficulties[a].compareTo(_difficulties[b])
            : _difficulties[b].compareTo(_difficulties[a]));
      }
    });
    _saveStudyState();
  }

  void _showReorderDialog() {
    final seedController = TextEditingController(text: _lastSortSeed);
    var doRandomise = _lastSortRandomise;
    var diffOrder = _lastSortDifficultyOrder;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isLandscape =
              MediaQuery.orientationOf(context) == Orientation.landscape;

          final randomiseControls = isLandscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: doRandomise,
                      onChanged: (value) =>
                          setDialogState(() => doRandomise = value ?? false),
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text('Randomise'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: seedController,
                        enabled: doRandomise,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Seed (optional)',
                          hintText: 'Leave empty for completely random',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: doRandomise,
                          onChanged: (value) => setDialogState(
                            () => doRandomise = value ?? false,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        const Text('Randomise'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: seedController,
                      enabled: doRandomise,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Seed (optional)',
                        hintText: 'Leave empty for completely random',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                );

          final difficultyControls = SegmentedButton<_DifficultyOrder>(
            segments: const [
              ButtonSegment(
                value: _DifficultyOrder.ignore,
                label: Text('Ignore'),
              ),
              ButtonSegment(
                value: _DifficultyOrder.easierFirst,
                label: Text('Easy First'),
              ),
              ButtonSegment(
                value: _DifficultyOrder.harderFirst,
                label: Text('Hard First'),
              ),
            ],
            selected: {diffOrder},
            onSelectionChanged: (sel) =>
                setDialogState(() => diffOrder = sel.first),
          );

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
            title: const Text('Reorder', textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                randomiseControls,
                const SizedBox(height: 12),
                if (isLandscape)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('Difficulty'),
                      const SizedBox(width: 12),
                      Expanded(child: difficultyControls),
                    ],
                  )
                else ...[
                  const Text('Difficulty'),
                  const SizedBox(height: 4),
                  difficultyControls,
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final seed = seedController.text;
                  setState(() {
                    _lastSortRandomise = doRandomise;
                    _lastSortSeed = seed;
                    _lastSortDifficultyOrder = diffOrder;
                  });
                  Navigator.pop(context);
                  await _saveSortSettings(
                    randomise: doRandomise,
                    seed: seed,
                    diffOrder: diffOrder,
                  );
                  if (doRandomise) {
                    _randomise(seed: seed, diffOrder: diffOrder);
                  } else {
                    _reorder(diffOrder: diffOrder);
                  }
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _reorder({_DifficultyOrder diffOrder = _DifficultyOrder.ignore}) {
    setState(() {
      _displayOrder = List.generate(_dataRows.length, (i) => i, growable: true);
      if (diffOrder != _DifficultyOrder.ignore) {
        _displayOrder.sort((a, b) => diffOrder == _DifficultyOrder.easierFirst
            ? _difficulties[a].compareTo(_difficulties[b])
            : _difficulties[b].compareTo(_difficulties[a]));
      }
    });
    _saveStudyState();
  }

  void _closeAll() {
    setState(() {
      for (var rowIdx = 0; rowIdx < _revealed.length; rowIdx++) {
        for (var colIdx = 0; colIdx < _revealed[rowIdx].length; colIdx++) {
          _revealed[rowIdx][colIdx] = false;
        }
      }
      _lastOpenedRowIdx = null;
      _lastOpenedOrigColIdx = null;
    });
    _saveStudyState();
  }

  void _openAll() {
    setState(() {
      for (var rowIdx = 0; rowIdx < _revealed.length; rowIdx++) {
        for (var colIdx = 0; colIdx < _revealed[rowIdx].length; colIdx++) {
          _revealed[rowIdx][colIdx] = true;
        }
      }
      if (_displayOrder.isNotEmpty && _columnOrder.isNotEmpty) {
        _lastOpenedRowIdx = _displayOrder.last;
        _lastOpenedOrigColIdx = _columnOrder.last;
      }
    });
    _saveStudyState();
  }

  void _handleFooterMenuAction(_FooterMenuAction action) {
    switch (action) {
      case _FooterMenuAction.settings:
        _showSettingsDialog();
        return;
      case _FooterMenuAction.reorder:
        _showReorderDialog();
        return;
      case _FooterMenuAction.hideAll:
        _closeAll();
        return;
      case _FooterMenuAction.showAll:
        _openAll();
        return;
    }
  }

  void _showSettingsDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Text Size', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 10)),
                  Expanded(
                    child: Slider(
                      value: _textSize,
                      min: 6,
                      max: 28,
                      divisions: 22,
                      label: _textSize.toStringAsFixed(0),
                      onChanged: (v) {
                        setDialogState(() => _textSize = v);
                        setState(() {});
                        _storageService.saveTableTextSize(
                            widget.table.name, v);
                      },
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 22)),
                ],
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hiddenColor = scheme.surfaceContainerHighest;

    return Scaffold(
      body: Column(
        children: [
          // ── table ──────────────────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const indexWidth = 40.0;
                final totalDataWidth = constraints.maxWidth - indexWidth;
                final colWidths = List.generate(
                  _numCols,
                  (i) => _colWidthFractions[i] * totalDataWidth,
                );

                final dragHandleTop = MediaQuery.paddingOf(context).top;
                final dataTable = SingleChildScrollView(
                  controller: _tableScrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SafeArea(bottom: false, child: SizedBox.shrink()),
                      if (_dataRows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('Table is empty')),
                        )
                      else
                        Table(
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.intrinsicHeight,
                          columnWidths: {
                            0: const FixedColumnWidth(indexWidth),
                            for (var i = 0; i < _numCols; i++)
                              i + 1: FixedColumnWidth(colWidths[i]),
                          },
                          border: TableBorder.all(
                            color: Colors.black,
                            width: 1,
                          ),
                          children: _displayOrder.map((origIdx) {
                            final row = _dataRows[origIdx];
                            final rowColor = _difficultyColor(
                              _difficulties[origIdx],
                            );
                            return TableRow(
                              key: ValueKey(origIdx),
                              decoration: BoxDecoration(color: rowColor),
                              children: [
                                // Index — tap to open difficulty dialog
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _showDifficultyDialog(origIdx),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Container(
                                      key: _rowKeys[origIdx],
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        '${origIdx + 1}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Data cells
                                for (var v = 0; v < _numCols; v++)
                                  _draggableDataCell(
                                    isLastOpened: _isLastOpened(origIdx, v),
                                    visualColIdx: v,
                                    text: _columnOrder[v] < row.length
                                        ? row[_columnOrder[v]]
                                        : '',
                                    columnName: _headers[_columnOrder[v]],
                                    revealed: _isRevealed(origIdx, v),
                                    hiddenColor: hiddenColor,
                                    onTap: () => _toggleRevealed(origIdx, v),
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                );

                // Drag handles for column dividers.
                var leftEdge = indexWidth;
                final handles = <Widget>[];
                for (var v = 0; v < _numCols - 1; v++) {
                  leftEdge += colWidths[v];
                  final capturedV = v;
                  const handleWidth = 16.0;
                  handles.add(
                    Positioned(
                      left: leftEdge - handleWidth / 2,
                      top: dragHandleTop,
                      bottom: 0,
                      width: handleWidth,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              const minFraction = 0.05;
                              final delta = details.delta.dx / totalDataWidth;
                              var newLeft =
                                  _colWidthFractions[capturedV] + delta;
                              var newRight =
                                  _colWidthFractions[capturedV + 1] - delta;
                              if (newLeft < minFraction) {
                                newRight -= (minFraction - newLeft);
                                newLeft = minFraction;
                              }
                              if (newRight < minFraction) {
                                newLeft -= (minFraction - newRight);
                                newRight = minFraction;
                              }
                              _colWidthFractions[capturedV] = newLeft;
                              _colWidthFractions[capturedV + 1] = newRight;
                            });
                          },
                        ),
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    Column(children: [Expanded(child: dataTable)]),
                    ...handles,
                  ],
                );
              },
            ),
          ),

          // ── command buttons ────────────────────────────
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Row(
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(Icons.exit_to_app, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PopupMenuButton<_FooterMenuAction>(
                    key: _footerMenuButtonKey,
                    onSelected: _handleFooterMenuAction,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _FooterMenuAction.settings,
                        child: ListTile(
                          leading: Icon(Icons.text_fields),
                          title: Text('Text Size'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _FooterMenuAction.reorder,
                        child: ListTile(
                          leading: Icon(Icons.reorder),
                          title: Text('Reorder'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _FooterMenuAction.hideAll,
                        child: ListTile(
                          leading: Icon(Icons.visibility_off),
                          title: Text('Hide All'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _FooterMenuAction.showAll,
                        child: ListTile(
                          leading: Icon(Icons.visibility),
                          title: Text('Show All'),
                        ),
                      ),
                    ],
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () =>
                            _footerMenuButtonKey.currentState?.showButtonMenu(),
                        child: Text(
                          widget.table.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _showNext,
                  child: const Icon(Icons.skip_next, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── widget helpers ─────────────────────────────────────────────

  Widget _draggableDataCell({
    required bool isLastOpened,
    required int visualColIdx,
    required String text,
    required String columnName,
    required bool revealed,
    required Color hiddenColor,
    required VoidCallback onTap,
  }) {
    final isDropTarget =
        _dragTargetVisualIdx == visualColIdx &&
        _draggingColVisualIdx != null &&
        _draggingColVisualIdx != visualColIdx;
    final cellColor = revealed ? null : hiddenColor;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        if (details.data != visualColIdx) {
          setState(() => _dragTargetVisualIdx = visualColIdx);
          return true;
        }
        return false;
      },
      onLeave: (_) {
        if (_dragTargetVisualIdx == visualColIdx) {
          setState(() => _dragTargetVisualIdx = null);
        }
      },
      onAcceptWithDetails: (details) {
        final from = details.data;
        final to = visualColIdx;
        setState(() {
          _dragTargetVisualIdx = null;
          _draggingColVisualIdx = null;
          if (from != to) {
            final colVal = _columnOrder.removeAt(from);
            _columnOrder.insert(to, colVal);
            final widthVal = _colWidthFractions.removeAt(from);
            _colWidthFractions.insert(to, widthVal);
          }
        });
      },
      builder: (context, candidateData, _) {
        return LongPressDraggable<int>(
          data: visualColIdx,
          onDragStarted: () => setState(() {
            _draggingColVisualIdx = visualColIdx;
          }),
          onDragEnd: (details) {
            setState(() {
              _draggingColVisualIdx = null;
              _dragTargetVisualIdx = null;
            });
          },
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(revealed ? text : columnName),
            ),
          ),
          childWhenDragging: Container(
            constraints: const BoxConstraints(minHeight: 44),
            color: Colors.grey.withAlpha(50),
          ),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(color: cellColor),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Container(
                    alignment: revealed
                        ? Alignment.centerLeft
                        : Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: revealed
                        ? Text(
                            text,
                            style: TextStyle(color: Colors.black, fontSize: _textSize),
                          )
                        : Center(
                            child: Text(
                              columnName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              if (isLastOpened || isDropTarget)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: isLastOpened || isDropTarget
                              ? const BorderSide(color: Colors.black, width: 3)
                              : BorderSide.none,
                          top: isLastOpened
                              ? const BorderSide(color: Colors.black, width: 3)
                              : BorderSide.none,
                          bottom: isLastOpened
                              ? const BorderSide(color: Colors.black, width: 3)
                              : BorderSide.none,
                          right: isLastOpened
                              ? const BorderSide(color: Colors.black, width: 3)
                              : BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _FooterMenuAction { settings, reorder, hideAll, showAll }

enum _DifficultyOrder { ignore, easierFirst, harderFirst }
