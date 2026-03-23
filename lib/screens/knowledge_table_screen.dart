import 'dart:math';

import 'package:flutter/material.dart';

import '../models/knowledge_table.dart';

class KnowledgeTableScreen extends StatefulWidget {
  final KnowledgeTable table;

  const KnowledgeTableScreen({super.key, required this.table});

  @override
  State<KnowledgeTableScreen> createState() => _KnowledgeTableScreenState();
}

class _KnowledgeTableScreenState extends State<KnowledgeTableScreen> {
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

  int? _draggingColVisualIdx;
  int? _dragTargetVisualIdx;
  double _dragTravelDistance = 0;
  int? _lastOpenedRowIdx;
  int? _lastOpenedOrigColIdx;

  int get _numCols => _headers.length;

  // ── helpers ────────────────────────────────────────────────────

  bool _isRevealed(int origRowIdx, int visualColIdx) =>
      _revealed[origRowIdx][_columnOrder[visualColIdx]];

    bool _isLastOpened(int origRowIdx, int visualColIdx) =>
      _lastOpenedRowIdx == origRowIdx &&
      _lastOpenedOrigColIdx == _columnOrder[visualColIdx];


  void _setRevealed(int origRowIdx, int visualColIdx, bool value) =>
      setState(() {
        final origColIdx = _columnOrder[visualColIdx];
        _revealed[origRowIdx][origColIdx] = value;
        if (value) {
          _lastOpenedRowIdx = origRowIdx;
          _lastOpenedOrigColIdx = origColIdx;
        }
      });

  void _toggleRevealed(int origRowIdx, int visualColIdx) => setState(() {
        final origColIdx = _columnOrder[visualColIdx];
        _revealed[origRowIdx][origColIdx] =
            !_revealed[origRowIdx][origColIdx];
        if (_revealed[origRowIdx][origColIdx]) {
          _lastOpenedRowIdx = origRowIdx;
          _lastOpenedOrigColIdx = origColIdx;
        }
      });

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
    List<String> headers =
        List.generate(numCols, (i) => 'Column ${i + 1}');
    if (rows.isNotEmpty) {
      final firstRow = rows.first;
      final looksLikeHeader =
          firstRow.any((cell) => cell.isNotEmpty && double.tryParse(cell) == null);
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
    _colWidthFractions =
        List.filled(_numCols, 1.0 / _numCols, growable: true);
    _revealed = List.generate(
      _dataRows.length,
      (_) => List.filled(_numCols, false, growable: true),
      growable: true,
    );
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
        return;
      }
    }
  }

  void _randomise() {
    setState(() => _displayOrder.shuffle(Random()));
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
  }

  // ── build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hiddenColor = scheme.surfaceContainerHighest;
    final indexColor = scheme.outline;

    return Scaffold(
      body: _dataRows.isEmpty
          ? const Center(child: Text('Table is empty'))
          : Column(
              children: [
                // ── table ──────────────────────────────────────
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const indexWidth = 40.0;
                      final totalDataWidth =
                          constraints.maxWidth - indexWidth;
                      final colWidths = List.generate(
                        _numCols,
                        (i) => _colWidthFractions[i] * totalDataWidth,
                      );

                      const titleHeight = 56.0;
                      final dividerColor = Theme.of(context).dividerColor;
                      final dataTable = SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SafeArea(
                              bottom: false,
                              child: Container(
                                height: titleHeight,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                child: Text(
                                  widget.table.name,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge,
                                ),
                              ),
                            ),
                            Table(
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.intrinsicHeight,
                              columnWidths: {
                                0: const FixedColumnWidth(indexWidth),
                                for (var i = 0; i < _numCols; i++)
                                  i + 1: FixedColumnWidth(colWidths[i]),
                              },
                              border: TableBorder.all(
                                color: dividerColor,
                                width: 1,
                              ),
                              children: _displayOrder.map((origIdx) {
                                final row = _dataRows[origIdx];
                                return TableRow(children: [
                                  // Index
                                  Container(
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2, vertical: 6),
                                    child: Text(
                                      '${origIdx + 1}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: indexColor),
                                    ),
                                  ),
                                  // Data cells
                                  for (var v = 0; v < _numCols; v++)
                                    _draggableDataCell(
                                      isLastOpened:
                                          _isLastOpened(origIdx, v),
                                      visualColIdx: v,
                                      text: _columnOrder[v] < row.length
                                          ? row[_columnOrder[v]]
                                          : '',
                                      columnName: _headers[_columnOrder[v]],
                                      revealed: _isRevealed(origIdx, v),
                                      hiddenColor: hiddenColor,
                                      onTap: () => _toggleRevealed(origIdx, v),
                                    ),
                                ]);
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
                        handles.add(Positioned(
                          left: leftEdge - handleWidth / 2,
                          top: titleHeight,
                          bottom: 0,
                          width: handleWidth,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) {
                                setState(() {
                                  const minFraction = 0.05;
                                  final delta =
                                      details.delta.dx / totalDataWidth;
                                  var newLeft =
                                      _colWidthFractions[capturedV] + delta;
                                  var newRight =
                                      _colWidthFractions[capturedV + 1] -
                                          delta;
                                  if (newLeft < minFraction) {
                                    newRight -=
                                        (minFraction - newLeft);
                                    newLeft = minFraction;
                                  }
                                  if (newRight < minFraction) {
                                    newLeft -=
                                        (minFraction - newRight);
                                    newRight = minFraction;
                                  }
                                  _colWidthFractions[capturedV] = newLeft;
                                  _colWidthFractions[capturedV + 1] =
                                      newRight;
                                });
                              },
                            ),
                          ),
                        ));
                      }

                      return Stack(
                        children: [
                          Column(
                            children: [
                              Expanded(child: dataTable),
                            ],
                          ),
                          ...handles,
                        ],
                      );
                    },
                  ),
                ),

                // ── command buttons ────────────────────────────
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.menu, size: 18),
                        label: const Text('Menu'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _randomise,
                        icon: const Icon(Icons.shuffle, size: 18),
                        label: const Text('All'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _closeAll,
                        icon: const Icon(Icons.visibility_off, size: 18),
                        label: const Text('All'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _openAll,
                        icon: const Icon(Icons.visibility, size: 18),
                        label: const Text('All'),
                      ),
                      FilledButton.icon(
                        onPressed: _showNext,
                        icon: const Icon(Icons.visibility, size: 18),
                        label: const Text('Next'),
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
    final isDropTarget = _dragTargetVisualIdx == visualColIdx &&
        _draggingColVisualIdx != null &&
        _draggingColVisualIdx != visualColIdx;
    final highlightColor = const Color.fromARGB(255, 215, 223, 147).withAlpha(90);
    final cellColor = isLastOpened
      ? highlightColor
      : (revealed ? null : hiddenColor);

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
        return Draggable<int>(
          data: visualColIdx,
          onDragStarted: () => setState(() {
            _draggingColVisualIdx = visualColIdx;
            _dragTravelDistance = 0;
          }),
          onDragUpdate: (details) {
            _dragTravelDistance += details.delta.distance;
          },
          onDragEnd: (details) {
            final shouldToggle =
                !details.wasAccepted && _dragTravelDistance < 12;
            setState(() {
              _draggingColVisualIdx = null;
              _dragTargetVisualIdx = null;
              _dragTravelDistance = 0;
            });
            if (shouldToggle) {
              onTap();
            }
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: isDropTarget
                ? BoxDecoration(
                    color: cellColor,
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    ),
                  )
                : BoxDecoration(
                    color: cellColor,
                  ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                alignment:
                    revealed ? Alignment.centerLeft : Alignment.center,
                padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: revealed
                    ? Text(text)
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
        );
      },
    );
  }
}

