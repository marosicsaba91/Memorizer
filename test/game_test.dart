import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memorizer/models/game_session.dart';
import 'package:memorizer/models/knowledge_table.dart';
import 'package:memorizer/models/row_save_data.dart';
import 'package:memorizer/screens/game_screen.dart';
import 'package:memorizer/screens/game_setup_dialog.dart';
import 'package:memorizer/screens/home_screen.dart';
import 'package:memorizer/services/storage_service.dart';

const words = KnowledgeTable(
  name: 'Words',
  rows: [
    ['Question', 'Answer', 'Example'],
    ['alpha', 'answer alpha', 'example alpha'],
    ['beta', 'answer beta', 'example beta'],
    ['gamma', 'answer gamma', 'example gamma'],
  ],
  importance: {'alpha': 3, 'beta': 3, 'gamma': 3},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'appearances count only graded outcomes and regrading changes the outcome',
    () {
      final entries = GameEntry.fromTable(words, {});
      final game = GameSession(
        entries: entries,
        settings: const GameSettings(),
      );
      final first = game.current!;
      expect(first.appeared, 0);
      game.answer(GameAnswer.failed);
      expect(first.appeared, 1);
      expect(first.failedCount, 1);
      expect(game.current!.appeared, 0);
      game.goBack();
      game.answer(GameAnswer.knew);
      expect(first.failedCount, 0);
      expect(first.successCount, 1);
      expect(first.appeared, 1);
      game.answer(GameAnswer.knew);
      expect(first.appeared, 1);
    },
  );

  test('weights use fixed round-start maxima and the requested components', () {
    final entries = GameEntry.fromTable(words, {
      'alpha': const RowSaveData(
        rowOrder: 0,
        revealed: [],
        importance: 9,
        failedCount: 3,
        successCount: 10,
      ),
      'beta': const RowSaveData(
        rowOrder: 1,
        revealed: [],
        failedCount: 7,
        successCount: 1,
      ),
    });
    final game = GameSession(
      entries: entries,
      settings: const GameSettings(
        weighted: true,
        importanceWeight: 2,
        lowSuccessWeight: 3,
        lowAppearanceWeight: 4,
      ),
    );
    final detail = game.weightDetails(entries.first);
    expect(detail.successDelta, 7);
    expect(detail.maxSuccessDelta, 7);
    expect(detail.adjustedSuccess, 0);
    expect(detail.maxAppeared, 13);
    expect(detail.adjustedAppearance, 0);
    expect(detail.total, 9 * 2);
    expect(game.selectionWeight(entries[1]), 3 * 2 + 13 * 3 + 5 * 4);
    entries.first.results = entries.first.results.withImportance(1);
    expect(game.weightDetails(entries.first).total, detail.total);
  });

  testWidgets(
    'question info exposes counts and fixed weights and reviewing does not add appearances',
    (tester) async {
      const single = KnowledgeTable(
        name: 'Single',
        rows: [
          ['Question'],
          ['only'],
        ],
        importance: {'only': 3},
      );
      final storage = StorageService();
      await storage.saveKnowledgeTables([single]);
      var syncs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            tables: const [single],
            settings: const GameSettings(questionCount: null, weighted: true),
            onRatingsChanged: () async {
              syncs++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Question 1 / 1'), findsOneWidget);
      expect(find.text('RW=1.00'), findsOneWidget);
      expect(await storage.loadPersonalResults(), isEmpty);
      expect(syncs, 0);
      await tester.tap(find.byTooltip('Question info'));
      await tester.pumpAndSettle();
      expect(find.text('In-table Importance'), findsOneWidget);
      expect(find.text('Overridden Importance'), findsOneWidget);
      final info = find.byType(AlertDialog);
      expect(
        find.descendant(of: info, matching: find.text('Failed')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: info, matching: find.text('Almost')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: info, matching: find.text('Success')),
        findsOneWidget,
      );
      expect(find.text('Appeared'), findsOneWidget);
      expect(find.text('Weight = 3 × 1 + 0 × 2 + 0 × 0'), findsOneWidget);
      expect(find.text('Weight = ui × iw + as × sw + aa × aw'), findsOneWidget);
      final total = tester.widget<Text>(find.text('Weight = 3'));
      expect(total.style!.fontWeight, FontWeight.bold);
      expect(total.style!.fontSize, 24);
      expect(find.text('Mean Weight = 3.00'), findsOneWidget);
      expect(find.text('Relative Weight = 3 / 3.00 = 1.00'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Almost'));
      await tester.pumpAndSettle();
      expect(syncs, 1);
      var saved = (await storage.loadPersonalResults())['Single']!['only']!;
      expect(saved.appeared, 1);
      expect(saved.almostCount, 1);
      await tester.tap(find.text('Review Questions'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 / 1'), findsOneWidget);
      saved = (await storage.loadPersonalResults())['Single']!['only']!;
      expect(saved.appeared, 1);
      expect(syncs, 1);
      await tester.tap(find.text('Failed'));
      await tester.pumpAndSettle();
      saved = (await storage.loadPersonalResults())['Single']!['only']!;
      expect(saved.failedCount, 1);
      expect(saved.almostCount, 0);
      expect(saved.appeared, 1);
      expect(syncs, 2);
      await tester.tap(find.text('Back to Summary'));
      await tester.pumpAndSettle();
      expect(find.text('Failed: 1'), findsOneWidget);
    },
  );

  late StorageService storage;
  test(
    'relative weight uses the selection pool mean and preserves it for history',
    () {
      final entries = GameEntry.fromTable(words, {}).take(2).toList();
      entries.first.results = entries.first.results.withImportance(10);
      entries.last.results = entries.last.results.withImportance(2);
      final game = GameSession(
        entries: entries,
        random: Random(3),
        settings: const GameSettings(weighted: true, lowSuccessWeight: 0),
      );
      final first = game.current!;
      expect(game.meanWeight(first), 6);
      expect(game.relativeWeight(first), game.selectionWeight(first) / 6);
      game.answer(GameAnswer.almost);
      final second = game.current!;
      expect(game.meanWeight(second), game.selectionWeight(second));
      expect(game.relativeWeight(second), 1);
      game.goBack();
      expect(game.meanWeight(game.current!), 6);
      expect(
        game.relativeWeight(game.current!),
        game.selectionWeight(first) / 6,
      );
    },
  );

  test('all-zero pool has neutral relative weight', () {
    final game = GameSession(
      entries: GameEntry.fromTable(words, {}),
      settings: const GameSettings(
        weighted: true,
        importanceWeight: 0,
        lowSuccessWeight: 0,
      ),
    );
    expect(game.meanWeight(game.current!), 0);
    expect(game.relativeWeight(game.current!), 1);
  });
  testWidgets(
    'game settings headings are bold and the dialog fits collapsed content',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await StorageService().saveGameSettings(
        const GameSettings(questionCount: null),
        10,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const GameSetupDialog(tables: [words]),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      for (final heading in [
        'Question count',
        'Included tables',
        'Question selection',
        'Automatically opened column',
      ]) {
        expect(
          tester.widget<Text>(find.text(heading)).style!.fontWeight,
          FontWeight.bold,
        );
      }
      final panel = find
          .ancestor(
            of: find.text('Set up game'),
            matching: find.byType(Material),
          )
          .first;
      final collapsedHeight = tester.getSize(panel).height;
      expect(collapsedHeight, lessThan(650));
      await tester.tap(find.text('Aggregated'));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, greaterThan(collapsedHeight));
      expect(tester.takeException(), isNull);
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.saveKnowledgeTables([words]);
  });

  test(
    'missing Importance falls back to zero and personal overrides take precedence',
    () {
      const source = KnowledgeTable(
        name: 'No default',
        rows: [
          ['Q'],
          ['first'],
          ['second'],
        ],
      );
      final entries = GameEntry.fromTable(source, {
        'first': const RowSaveData(rowOrder: 0, revealed: [], importance: 8),
      });
      expect(entries.first.importance, 8);
      expect(entries.last.importance, 0);
    },
  );

  test('finite rounds do not repeat entries and cap at the available pool', () {
    final entries = GameEntry.fromTable(words, {});
    for (final weighted in [false, true]) {
      final game = GameSession(
        entries: entries,
        settings: GameSettings(questionCount: 10, weighted: weighted),
        random: Random(7),
      );
      final seen = <String>{};
      while (!game.finished) {
        expect(seen.add(game.current!.key), isTrue);
        game.answer(GameAnswer.almost);
      }
      expect(game.answered, 3);
      expect(game.total, 3);
      expect(game.results[GameAnswer.almost], 3);
    }
    final shorter = GameSession(
      entries: entries,
      settings: const GameSettings(questionCount: 1),
    );
    shorter.answer(GameAnswer.knew);
    expect(shorter.finished, isTrue);
    expect(shorter.answered, 1);
  });

  test(
    'history navigation preserves the next question and scores each visit once',
    () {
      for (final count in <int?>[3, null]) {
        final game = GameSession(
          entries: GameEntry.fromTable(words, {}),
          settings: GameSettings(questionCount: count),
          random: Random(7),
        );
        final first = game.current;
        expect(game.canGoBack, isFalse);
        expect(game.canGoForward, isFalse);
        game.answer(GameAnswer.knew);
        final second = game.current;
        game.goBack();
        expect(game.current, same(first));
        expect(game.questionNumber, 1);
        expect(game.isReviewing, isTrue);
        game.answer(GameAnswer.failed);
        expect(game.answered, 1);
        expect(game.results[GameAnswer.failed], 1);
        expect(game.results[GameAnswer.knew], 0);
        expect(game.current, same(first));
        game.goForward();
        expect(game.current, same(second));
        expect(game.questionNumber, 2);
        expect(game.isReviewing, isFalse);
        expect(game.canGoForward, isFalse);
        game.goForward();
        expect(game.current, same(second));
      }
    },
  );

  test(
    'All exhausts the pool without duplicates and history remains reviewable',
    () {
      final game = GameSession(
        entries: GameEntry.fromTable(words, {}),
        settings: const GameSettings(questionCount: null),
      );
      final seen = <String>{};
      while (!game.finished) {
        expect(seen.add(game.current!.key), isTrue);
        game.answer(GameAnswer.almost);
      }
      expect(game.total, 3);
      expect(game.history.length, 3);
      game.reviewHistory();
      expect(game.questionNumber, 1);
      expect(game.currentAnswer, GameAnswer.almost);
      game.goForward();
      expect(game.questionNumber, 2);
      game.showSummary();
      expect(game.finished, isTrue);
    },
  );

  testWidgets(
    'game setup automatically remembers choices across dialog openings',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<GameSettings>(
                  context: context,
                  builder: (_) => const GameSetupDialog(tables: [words]),
                ),
                child: const Text('Setup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auto-open-column')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('question-count')),
        '37',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('All').first);
      await tester.tap(find.text('All').first);
      await tester.pump();
      await tester.tap(find.text('Selected'));
      await tester.pump();
      await tester.ensureVisible(find.text('Words'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Words'));
      await tester.pump();
      await tester.ensureVisible(find.text('Aggregated'));
      await tester.tap(find.text('Aggregated'));
      await tester.pumpAndSettle();
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      sliders[0].onChanged!(4);
      sliders[1].onChanged!(7);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final saved = (await storage.loadGameSettings())!;
      expect(saved['questionCount'], isNull);
      expect(saved['finiteQuestionCount'], 37);
      expect(saved['selectedTables'], ['Words']);
      expect(saved['importanceWeight'], 4);
      expect(saved['lowSuccessWeight'], 7);
      expect(saved['autoOpenColumn'], 2);
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('question-count')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('auto-open-column')))
            .controller!
            .text,
        '2',
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .map((slider) => slider.value),
        [4.0, 7.0, 0.0],
      );
      await tester.ensureVisible(find.text('Fixed'));
      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('question-count')))
            .controller!
            .text,
        '37',
      );
    },
  );

  for (final column in [0, 1, 2, 3]) {
    testWidgets('auto open column $column and toggle revealed fields', (
      tester,
    ) async {
      const table = KnowledgeTable(
        name: 'Toggle',
        rows: [
          ['Front', 'Back'],
          ['front value', 'back value'],
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            tables: const [table],
            settings: GameSettings(autoOpenColumn: column),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('front value'),
        column == 1 ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('back value'),
        column == 2 ? findsOneWidget : findsNothing,
      );
      expect(find.text('Front'), column == 1 ? findsNothing : findsOneWidget);
      expect(find.text('Back'), column == 2 ? findsNothing : findsOneWidget);
      await tester.tap(find.text('Show Answer'));
      await tester.pumpAndSettle();
      expect(find.text('Front'), findsNothing);
      expect(find.text('Back'), findsNothing);
      await tester.tap(find.text('front value'));
      await tester.pumpAndSettle();
      expect(find.text('front value'), findsNothing);
      expect(find.text('Front'), findsOneWidget);
      expect(find.text('Show Answer'), findsOneWidget);
      await tester.tap(find.text('Front'));
      await tester.pumpAndSettle();
      expect(find.text('front value'), findsOneWidget);
      expect(find.text('Almost'), findsOneWidget);
    });
  }

  testWidgets(
    'revealed text is centered and shrinks with length; reveal prompts are translucent',
    (tester) async {
      final longText = List.filled(30, 'A longer answer').join(' ');
      final table = KnowledgeTable(
        name: 'Sizing',
        rows: [
          ['Question', 'Answer'],
          ['Short', longText],
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            tables: [table],
            settings: const GameSettings(questionCount: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final short = tester.widget<Text>(find.text('Short'));
      final prompt = tester.widget<Text>(find.text('Tap to reveal'));
      expect(short.textAlign, TextAlign.center);
      expect(prompt.style!.color!.a, closeTo(0.5, 0.01));
      await tester.tap(find.text('Show Answer'));
      await tester.pumpAndSettle();
      final long = tester.widget<Text>(find.text(longText));
      expect(long.textAlign, TextAlign.center);
      expect(long.style!.fontSize!, lessThan(short.style!.fontSize!));
      expect(long.style!.fontSize!, greaterThanOrEqualTo(14));
    },
  );

  test('zero weights still exhaust the pool using equal chance', () {
    final entries = GameEntry.fromTable(words, {});
    final game = GameSession(
      entries: entries,
      settings: const GameSettings(
        weighted: true,
        importanceWeight: 0,
        lowSuccessWeight: 0,
        lowAppearanceWeight: 0,
      ),
    );
    expect(entries.map(game.selectionWeight), everyElement(0));
    final seen = <String>{};
    while (!game.finished) {
      expect(seen.add(game.current!.key), isTrue);
      game.answer(GameAnswer.almost);
    }
    expect(seen.length, 3);
  });

  testWidgets(
    'question count accepts typing and steps by rounded ten percent',
    (tester) async {
      GameSettings? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<GameSettings>(
                    context: context,
                    builder: (_) => const GameSetupDialog(tables: [words]),
                  );
                },
                child: const Text('Setup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      final count = find.byKey(const ValueKey('question-count'));
      String value() => tester.widget<TextField>(count).controller!.text;
      await tester.enterText(count, '25');
      await tester.pump();
      await tester.tap(find.byTooltip('More questions'));
      await tester.pump();
      expect(value(), '28');
      await tester.tap(find.byTooltip('Fewer questions'));
      await tester.pump();
      expect(value(), '25');
      await tester.enterText(count, '100');
      await tester.pump();
      await tester.tap(find.byTooltip('More questions'));
      await tester.pump();
      expect(value(), '110');
      await tester.tap(find.byTooltip('Fewer questions'));
      await tester.pump();
      expect(value(), '99');
      await tester.enterText(count, '0');
      await tester.pump();
      final start = find
          .ancestor(
            of: find.text('Start Game'),
            matching: find.byType(FilledButton),
          )
          .first;
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      await tester.enterText(count, '2');
      await tester.pump();
      await tester.tap(find.byTooltip('Fewer questions'));
      await tester.pump();
      expect(value(), '1');
      await tester.tap(find.text('Start Game'));
      await tester.pumpAndSettle();
      expect(result!.questionCount, 1);
    },
  );

  testWidgets(
    'aggregated setup passes adjustable component weights to the game',
    (tester) async {
      GameSettings? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<GameSettings>(
                    context: context,
                    builder: (_) => const GameSetupDialog(tables: [words]),
                  );
                },
                child: const Text('Setup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Aggregated'));
      await tester.tap(find.text('Aggregated'));
      await tester.pumpAndSettle();
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.map((slider) => slider.value), [1.0, 2.0, 0.0]);
      expect(
        sliders.every(
          (slider) =>
              slider.min == 0 && slider.max == 20 && slider.divisions == null,
        ),
        isTrue,
      );
      sliders[0].onChanged!(0);
      sliders[1].onChanged!(20);
      sliders[2].onChanged!(10);
      await tester.pump();
      await tester.tap(find.text('Start Game'));
      await tester.pumpAndSettle();
      expect(result!.importanceWeight, 0);
      expect(result!.lowSuccessWeight, 100);
      expect(result!.lowAppearanceWeight, 10);
      final restored = GameSettings.fromJson(result!.toJson());
      expect(restored.lowSuccessWeight, 100);
      expect(restored.lowAppearanceWeight, 10);
    },
  );

  test('a weight of 10 has five times the first-draw probability of 2', () {
    final entries = GameEntry.fromTable(words, {}).take(2).toList();
    entries[0].results = entries[0].results.withImportance(10);
    entries[1].results = entries[1].results.withImportance(2);
    final random = Random(42);
    var first = 0;
    for (var index = 0; index < 6000; index++) {
      final game = GameSession(
        entries: entries,
        random: random,
        settings: const GameSettings(weighted: true, lowSuccessWeight: 0),
      );
      if (game.current == entries.first) first++;
    }
    expect(first, inInclusiveRange(4900, 5100));
  });

  test('empty and numeric tables are handled without inventing a header', () {
    const marked = KnowledgeTable(
      name: 'Marked',
      rows: [
        ['Question', 'Notes*'],
        ['one', 'note'],
      ],
    );
    expect(GameEntry.fromTable(marked, {}).first.headers, [
      'Question',
      'Notes',
    ]);
    expect(
      GameEntry.fromTable(const KnowledgeTable(name: 'Empty', rows: []), {}),
      isEmpty,
    );
    const numeric = KnowledgeTable(
      name: 'Numbers',
      rows: [
        ['1', '2'],
        ['3'],
      ],
    );
    final entries = GameEntry.fromTable(numeric, {});
    expect(entries.length, 2);
    expect(entries.first.headers, ['Column 1', 'Column 2']);
    expect(entries[1].cells, ['3', '']);
  });

  testWidgets(
    'main Play button opens setup with finite, 10, all and equal defaults',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Play')).dy,
        lessThan(tester.getTopLeft(find.text('Words')).dy),
      );
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.text('Set up game'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      final segments = tester
          .widgetList<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .toList();
      expect(segments.map((segment) => segment.selected.single), [
        false,
        true,
        false,
      ]);
      await tester.tap(find.text('Start Game'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 / 3'), findsOneWidget);
      expect(find.text('Show Answer'), findsOneWidget);
    },
  );

  testWidgets(
    'setup supports selected tables, infinite and weighted on a phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      GameSettings? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<GameSettings>(
                    context: context,
                    builder: (_) => const GameSetupDialog(tables: [words]),
                  );
                },
                child: const Text('Setup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('All').first);
      await tester.tap(find.text('All').first);
      await tester.tap(find.text('Selected'));
      await tester.pumpAndSettle();
      final disabled = tester.widget<FilledButton>(
        find
            .ancestor(
              of: find.text('Start Game'),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(disabled.onPressed, isNull);
      await tester.ensureVisible(find.text('Words'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Words'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Aggregated'));
      await tester.tap(find.text('Aggregated'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Game'));
      await tester.pumpAndSettle();
      expect(result!.questionCount, isNull);
      expect(result!.selectedTables, {'Words'});
      expect(result!.weighted, isTrue);
      expect(result!.importanceWeight, 1);
      expect(result!.lowSuccessWeight, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reveal, scoring, summary, new round and confirmed exit persist only ratings',
    (tester) async {
      final saved = (await storage.loadTableRowData('Words'))!;
      for (final key in saved.keys.toList()) {
        saved[key] = const RowSaveData(
          rowOrder: 0,
          revealed: [true, true, true],
        );
      }
      await storage.saveTableRowData('Words', saved);
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameScreen(
                      tables: const [words],
                      settings: const GameSettings(),
                      random: Random(7),
                      onRatingsChanged: () async {
                        changes++;
                      },
                    ),
                  ),
                ),
                child: const Text('Launch'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      String current() => [
        'alpha',
        'beta',
        'gamma',
      ].firstWhere((key) => find.text(key).evaluate().isNotEmpty);
      final first = current();
      final ratingCheckmark = find.byIcon(Icons.check);
      Finder markedRating(String label) => find.descendant(
        of: find.ancestor(of: ratingCheckmark, matching: find.byType(Wrap)),
        matching: find.text(label),
      );
      final exitPosition = tester.getCenter(find.byTooltip('Exit game'));
      final titlePosition = tester.getCenter(find.text('Question 1 / 3'));
      expect(exitPosition.dx, lessThan(titlePosition.dx));
      expect((exitPosition.dy - titlePosition.dy).abs(), lessThan(24));
      Color? cardColor(Finder content) => tester
          .widget<Card>(
            find.ancestor(of: content, matching: find.byType(Card)).first,
          )
          .color;
      final revealedColor = cardColor(find.text(first));
      expect(cardColor(find.text('Tap to reveal').first), isNot(revealedColor));

      expect(find.text('answer $first'), findsNothing);
      expect(find.text('Failed'), findsNothing);
      await tester.tap(find.byTooltip('Increase Importance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap to reveal').first);
      await tester.pumpAndSettle();
      expect(find.text('answer $first'), findsOneWidget);
      expect(cardColor(find.text('answer $first')), revealedColor);
      expect(find.text('Show Answer'), findsOneWidget);
      await tester.tap(find.text('Show Answer'));
      await tester.pumpAndSettle();
      expect(find.text('example $first'), findsOneWidget);
      expect(ratingCheckmark, findsNothing);
      await tester.tap(find.text('Failed'));
      await tester.pumpAndSettle();
      final second = current();
      expect(second, isNot(first));
      expect(find.text('answer $second'), findsNothing);
      await tester.tap(find.text(second));
      await tester.pumpAndSettle();
      expect(find.text(second), findsNothing);
      await tester.tap(find.text('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 / 3'), findsOneWidget);
      expect(find.text('answer $first'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(markedRating('Failed'), findsOneWidget);
      await tester.tap(find.text('I knew'));
      await tester.pumpAndSettle();
      expect(ratingCheckmark, findsOneWidget);
      expect(markedRating('I knew'), findsOneWidget);
      expect(find.text('Question 1 / 3'), findsOneWidget);
      expect(
        (await storage.loadTableRowData('Words'))![first]!.successCount,
        1,
      );
      await tester.tap(find.text('Failed'));
      await tester.pumpAndSettle();
      expect((await storage.loadTableRowData('Words'))![first]!.failedCount, 1);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Question 2 / 3'), findsOneWidget);
      expect(find.text(second), findsNothing);
      expect(find.text('answer $second'), findsNothing);
      await tester.tap(find.text('Show Answer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Almost'));
      await tester.pumpAndSettle();
      final third = current();
      await tester.tap(find.text('Show Answer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I knew'));
      await tester.pumpAndSettle();
      expect(find.text('Round complete'), findsOneWidget);
      expect(find.text('I knew: 1'), findsOneWidget);
      expect(find.text('Almost: 1'), findsOneWidget);
      expect(find.text('Failed: 1'), findsOneWidget);
      final updated = (await storage.loadTableRowData('Words'))!;
      expect(updated[first]!.failedCount, 1);
      expect(updated[first]!.importance, 4);
      expect(updated[second]!.successCount, 0);
      expect(updated[third]!.successCount, 1);
      expect(updated[first]!.revealed, [true, true, true]);
      expect(changes, 6);
      expect(updated.values.map((row) => row.appeared), everyElement(1));
      await tester.tap(find.text('New Round'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Exit game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep playing'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Exit game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exit game').last);
      await tester.pumpAndSettle();
      expect(find.text('Launch'), findsOneWidget);
    },
  );

  testWidgets('Almost records one appearance and one Almost outcome', (
    tester,
  ) async {
    const single = KnowledgeTable(
      name: 'Single',
      rows: [
        ['Question'],
        ['only'],
      ],
    );
    await storage.saveKnowledgeTables([single]);
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          tables: [single],
          settings: GameSettings(questionCount: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Show Answer'), findsNothing);
    await tester.tap(find.text('Almost'));
    await tester.pumpAndSettle();
    expect(find.text('Round complete'), findsOneWidget);
    final result = (await storage.loadPersonalResults())['Single']!['only']!;
    expect(result.successCount, 0);
    expect(result.appeared, 1);
  });

  testWidgets(
    'selected tables exclude other entries and an empty selection is safe',
    (tester) async {
      const selected = KnowledgeTable(
        name: 'Selected',
        rows: [
          ['Question'],
          ['selected entry'],
        ],
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: GameScreen(
            tables: [words, selected],
            settings: GameSettings(selectedTables: {'Selected'}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('selected entry'), findsOneWidget);
      expect(find.text('Question 1 / 1'), findsOneWidget);
      await tester.tap(find.text('Almost'));
      await tester.pumpAndSettle();
      expect(find.text('Round complete'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        const MaterialApp(
          home: GameScreen(
            tables: [words],
            settings: GameSettings(selectedTables: {'Missing'}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No entries in the selected tables.'), findsOneWidget);
      expect(find.byTooltip('Exit game'), findsOneWidget);
    },
  );

  testWidgets('comments save before rating and survive answering', (
    tester,
  ) async {
    const single = KnowledgeTable(
      name: 'Single',
      rows: [
        ['Question'],
        ['only'],
      ],
    );
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          tables: const [single],
          settings: const GameSettings(),
          onRatingsChanged: () async {
            changes++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('No comment yet'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Comment'), findsNothing);
    await tester.tap(find.byTooltip('No comment yet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Remember this');
    await tester.pump();
    await tester.tap(find.byTooltip('Close comment'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Comment saved'), findsOneWidget);
    expect(changes, 1);
    final saved = (await storage.loadPersonalResults())['Single']!['only']!;
    expect(saved.comment, 'Remember this');
    expect(saved.appeared, 0);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Comment saved'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Updated while answering');
    await tester.tap(find.text('I knew'));
    await tester.pumpAndSettle();
    final rated = (await storage.loadPersonalResults())['Single']!['only']!;
    expect(rated.comment, 'Updated while answering');
    expect(rated.successCount, 1);
  });

  testWidgets('outcome counts continue above ten', (tester) async {
    const single = KnowledgeTable(
      name: 'Single',
      rows: [
        ['Question'],
        ['only'],
      ],
    );
    await storage.saveKnowledgeTables([single]);
    await storage.saveTableRowData('Single', {
      'only': const RowSaveData(
        rowOrder: 0,
        revealed: [],
        failedCount: 12,
        almostCount: 7,
        successCount: 15,
      ),
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(tables: [single], settings: GameSettings()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('I knew'));
    await tester.pumpAndSettle();
    final result = (await storage.loadTableRowData('Single'))!['only']!;
    expect(result.successCount, 16);
    expect(result.appeared, 35);
  });
}
