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
  late StorageService storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.saveKnowledgeTables([words]);
  });

  test(
    'weighted selection uses personal ratings and the requested formula',
    () {
      final entries = GameEntry.fromTable(words, {
        'alpha': const RowSaveData(
          rowOrder: 0,
          revealed: [],
          importance: 9,
          success: 2,
        ),
      });
      expect(entries.first.importance, 9);
      expect(entries.first.weight(const GameSettings()), 9 + (11 - 2) * 2);
      expect(entries[1].importance, 3);
      expect(entries[1].success, 5);
      expect(entries[1].weight(const GameSettings()), 15);
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
        find.byKey(const ValueKey('question-count')),
        '37',
      );
      await tester.pump();
      await tester.tap(find.text('Infinite'));
      await tester.pump();
      await tester.tap(find.text('Selected tables'));
      await tester.pump();
      await tester.tap(find.text('Words'));
      await tester.pump();
      await tester.tap(find.text('Aggregated Chance'));
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
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('question-count')), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .map((slider) => slider.value),
        [4.0, 7.0],
      );
      await tester.ensureVisible(find.text('Finite'));
      await tester.tap(find.text('Finite'));
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

  test(
    'component weights can be disabled and both zero fall back to equal chance',
    () {
      final entries = GameEntry.fromTable(words, {});
      entries.first.personalImportance = 9;
      entries.first.personalSuccess = 2;
      expect(
        entries.first.weight(
          const GameSettings(importanceWeight: 10, lowSuccessWeight: 0),
        ),
        90,
      );
      expect(
        entries.first.weight(
          const GameSettings(importanceWeight: 0, lowSuccessWeight: 10),
        ),
        90,
      );
      final zero = GameSession(
        entries: entries,
        settings: const GameSettings(
          questionCount: null,
          weighted: true,
          importanceWeight: 0,
          lowSuccessWeight: 0,
        ),
        random: Random(1),
      );
      final seen = <String>{};
      for (var i = 0; i < 100; i++) {
        seen.add(zero.current!.key);
        zero.answer(GameAnswer.almost);
      }
      expect(seen.length, 3);
    },
  );

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
      await tester.tap(find.text('Aggregated Chance'));
      await tester.pumpAndSettle();
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.map((slider) => slider.value), [1.0, 2.0]);
      expect(
        sliders.every(
          (slider) =>
              slider.min == 0 && slider.max == 10 && slider.divisions == 10,
        ),
        isTrue,
      );
      sliders[0].onChanged!(0);
      sliders[1].onChanged!(10);
      await tester.pump();
      await tester.tap(find.text('Start Game'));
      await tester.pumpAndSettle();
      expect(result!.importanceWeight, 0);
      expect(result!.lowSuccessWeight, 10);
    },
  );

  test('infinite weighted selection favors high weight and never ends', () {
    final entries = GameEntry.fromTable(words, {}).take(2).toList();
    entries[0].personalImportance = 10;
    entries[0].personalSuccess = 1;
    entries[1].personalImportance = 1;
    entries[1].personalSuccess = 10;
    final game = GameSession(
      entries: entries,
      settings: const GameSettings(questionCount: null, weighted: true),
      random: Random(42),
    );
    var first = 0;
    for (var i = 0; i < 5000; i++) {
      if (game.current == entries[0]) first++;
      game.answer(GameAnswer.knew);
    }
    expect(first, inInclusiveRange(4450, 4650));
    expect(game.total, isNull);
    expect(game.finished, isFalse);
  });

  test('empty and numeric tables are handled without inventing a header', () {
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
      await tester.tap(find.text('Infinite'));
      await tester.tap(find.text('Selected tables'));
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
      await tester.tap(find.text('Words'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Aggregated Chance'));
      await tester.tap(find.text('Aggregated Chance'));
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
      await tester.tap(find.text('Failed'));
      await tester.pumpAndSettle();
      final second = current();
      expect(second, isNot(first));
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
      expect(updated[first]!.success, 4);
      expect(updated[first]!.importance, 4);
      expect(updated[second]!.success, isNull);
      expect(updated[third]!.success, 6);
      expect(updated[first]!.revealed, [true, true, true]);
      expect(changes, 3);
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

  testWidgets('Almost on a one-column entry leaves Success unset', (
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
    expect(await storage.loadPersonalResults(), isEmpty);
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

  for (final limit in [1, 10]) {
    testWidgets('Success remains within 1–10 when grading at $limit', (
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
      await storage.saveTableRowData('Single', {
        'only': RowSaveData(
          rowOrder: 0,
          revealed: [],
          success: limit,
          importance: limit,
        ),
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: GameScreen(
            tables: [single],
            settings: GameSettings(questionCount: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byTooltip(
        limit == 1 ? 'Decrease Importance' : 'Increase Importance',
      );
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(of: button, matching: find.byType(IconButton))
                  .first,
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text(limit == 1 ? 'Failed' : 'I knew'));
      await tester.pumpAndSettle();
      expect(
        (await storage.loadTableRowData('Single'))!['only']!.success,
        limit,
      );
    });
  }
}
