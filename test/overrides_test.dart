import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memorizer/models/knowledge_table.dart';
import 'package:memorizer/models/profile_settings.dart';
import 'package:memorizer/models/row_save_data.dart';
import 'package:memorizer/screens/knowledge_table_screen.dart';
import 'package:memorizer/screens/profile_screen.dart';
import 'package:memorizer/services/ratings_sync_service.dart';
import 'package:memorizer/services/storage_service.dart';

const table = KnowledgeTable(
  name: 'Defaults',
  rows: [
    ['Entry'],
    ['one'],
  ],
  importance: {'one': 3},
);
const url = 'https://script.google.com/macros/s/test/exec';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.saveKnowledgeTables([table]);
  });

  testWidgets(
    'personal Importance wins and Success 5 is neutral despite old table metadata',
    (tester) async {
      final cached = KnowledgeTable.fromJson({
        ...table.toJson(),
        'success': {'one': 10},
      });
      await storage.saveTableRowData('Defaults', {
        'one': const RowSaveData(rowOrder: 0, revealed: [], importance: 8),
      });
      await tester.pumpWidget(
        MaterialApp(home: KnowledgeTableScreen(table: cached)),
      );
      await tester.pumpAndSettle();
      Color? rowColor() =>
          (tester
                      .widgetList<Table>(find.byType(Table))
                      .expand((table) => table.children)
                      .firstWhere((row) => row.key == const ValueKey(0))
                      .decoration
                  as BoxDecoration)
              .color;
      expect(rowColor(), const Color(0xffffffff));
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      expect(find.text('8'), findsOneWidget);
      expect(find.text('Reset to: 3'), findsOneWidget);
      expect(find.text('Reset to: 5'), findsOneWidget);
      await tester.tap(find.byTooltip('Increase Success'));
      await tester.pumpAndSettle();
      expect(rowColor(), isNot(const Color(0xffffffff)));
      await tester.tap(find.text('Reset to: 5'));
      await tester.pumpAndSettle();
      expect(rowColor(), const Color(0xffffffff));
      final personal = (await storage
          .loadPersonalResults())['Defaults']!['one']!;
      expect(personal.importance, 8);
      expect(personal.success, isNull);
    },
  );

  testWidgets('reset removes each override and restores source defaults', (
    tester,
  ) async {
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KnowledgeTableScreen(
          table: table,
          onRatingsChanged: () async {
            changes++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await storage.loadPersonalResults(), isEmpty);
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('Reset to: 3'), findsOneWidget);
    expect(find.text('Reset to: 5'), findsOneWidget);
    await tester.tap(find.byTooltip('Increase Success'));
    await tester.pumpAndSettle();
    var personal = await storage.loadPersonalResults();
    expect(personal['Defaults']!['one']!.importance, isNull);
    expect(personal['Defaults']!['one']!.success, 6);
    await tester.tap(find.byTooltip('Increase Importance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to: 3'));
    await tester.pumpAndSettle();
    personal = await storage.loadPersonalResults();
    expect(personal['Defaults']!['one']!.importance, isNull);
    expect(personal['Defaults']!['one']!.success, 6);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Reset to: 5'));
    await tester.pumpAndSettle();
    expect(await storage.loadPersonalResults(), isEmpty);
    expect(changes, 4);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('personal_results/Defaults'), isFalse);
    expect(prefs.containsKey('row_data/Defaults'), isTrue);
  });

  test(
    'new source defaults apply without creating personal overrides',
    () async {
      await storage.saveTableRowData('Defaults', {
        'one': const RowSaveData(rowOrder: 0, revealed: [true], success: 8),
      });
      const updated = KnowledgeTable(
        name: 'Defaults',
        rows: [
          ['Entry'],
          ['one'],
        ],
        importance: {'one': 7},
      );
      await storage.saveKnowledgeTables([updated]);
      final row = (await storage.loadTableRowData('Defaults'))!['one']!;
      expect(row.importance, isNull);
      expect(row.success, 8);
      expect(row.revealed, [true]);
      expect((await storage.loadKnowledgeTables()).first.importance['one'], 7);
    },
  );

  test(
    'migrates old saved defaults without turning them into overrides',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'row_data/Defaults',
        jsonEncode({
          'one': {
            'rowOrder': 2,
            'revealed': [true],
            'importance': 3,
            'success': 9,
          },
        }),
      );
      final row = (await storage.loadTableRowData('Defaults'))!['one']!;
      expect(row.importance, isNull);
      expect(row.success, 9);
      expect(row.rowOrder, 2);
      expect(row.revealed, [true]);
      expect(jsonDecode(prefs.getString('personal_results/Defaults')!), {
        'one': {'success': 9},
      });
    },
  );

  test(
    'blank download clears overrides; empty snapshot removes old entries',
    () async {
      await storage.saveTableRowData('Defaults', {
        'one': const RowSaveData(
          rowOrder: 2,
          revealed: [true],
          importance: 8,
          success: 9,
        ),
      });
      var entries = <Map<String, dynamic>>[
        {'table': 'Defaults', 'entry': 'one', 'importance': '', 'success': 6},
      ];
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'ok': true, 'version': 2, 'entries': entries}),
          200,
        ),
      );
      addTearDown(client.close);
      final sync = RatingsSyncService(client: client);
      await sync.download(url);
      var row = (await storage.loadTableRowData('Defaults'))!['one']!;
      expect(row.importance, isNull);
      expect(row.success, 6);
      entries = [];
      await sync.download(url);
      expect(await storage.loadPersonalResults(), isEmpty);
      row = (await storage.loadTableRowData('Defaults'))!['one']!;
      expect(row.importance, isNull);
      expect(row.success, isNull);
      expect(row.rowOrder, 2);
      expect(row.revealed, [true]);
    },
  );

  test(
    'empty upload sends a replacement snapshot and rejects old endpoints',
    () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {
          'version': 2,
          'mode': 'replace',
          'entries': [],
        });
        return http.Response(jsonEncode({'ok': true, 'version': 2}), 200);
      });
      addTearDown(client.close);
      expect(await RatingsSyncService(client: client).upload(url), 0);
      final old = MockClient(
        (_) async => http.Response(
          jsonEncode({'ok': true, 'version': 1, 'entries': []}),
          200,
        ),
      );
      addTearDown(old.close);
      await expectLater(
        RatingsSyncService(client: old).download(url),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'clear local personal results keeps tables, settings and study state',
    (tester) async {
      await storage.saveProfileSettings(
        const ProfileSettings(syncUrl: url, autoSync: true),
      );
      await storage.saveTableRowData('Defaults', {
        'one': const RowSaveData(
          rowOrder: 2,
          revealed: [true],
          importance: 9,
          success: 8,
        ),
      });
      final client = MockClient(
        (_) async => throw StateError('Clear must stay local'),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(sync: RatingsSyncService(client: client)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Clear All Local Personal Results'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Clear All Local Personal Results'));
      await tester.pumpAndSettle();
      expect(await storage.loadPersonalResults(), isEmpty);
      expect((await storage.loadKnowledgeTables()).length, 1);
      expect((await storage.loadProfileSettings()).syncUrl, url);
      expect((await storage.loadProfileSettings()).autoSync, isTrue);
      final row = (await storage.loadTableRowData('Defaults'))!['one']!;
      expect(row.rowOrder, 2);
      expect(row.revealed, [true]);
      expect(row.importance, isNull);
      expect(row.success, isNull);
    },
  );
}
