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
    'resetting Importance retains graded results and restores table default',
    (tester) async {
      await storage.saveTableRowData('Defaults', {
        'one': const RowSaveData(
          rowOrder: 2,
          revealed: [true],
          importance: 8,
          failedCount: 1,
          almostCount: 2,
          successCount: 3,
        ),
      });
      await tester.pumpWidget(
        const MaterialApp(home: KnowledgeTableScreen(table: table)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      expect(find.text('8'), findsOneWidget);
      await tester.tap(find.text('Reset to: 3'));
      await tester.pumpAndSettle();
      final saved = (await storage.loadPersonalResults())['Defaults']!['one']!;
      expect(saved.importance, isNull);
      expect(saved.failedCount, 1);
      expect(saved.almostCount, 2);
      expect(saved.successCount, 3);
      expect(saved.appeared, 6);
      expect(find.text('3'), findsOneWidget);
    },
  );

  test(
    'an entry with only an Importance override is deleted when reset',
    () async {
      await storage.saveTableRowData('Defaults', {
        'one': const RowSaveData(rowOrder: 0, revealed: [], importance: 8),
      });
      await storage.saveTableRowData('Defaults', {
        'one': const RowSaveData(rowOrder: 0, revealed: []),
      });
      expect(await storage.loadPersonalResults(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('personal_results/Defaults'), isFalse);
      expect(prefs.containsKey('row_data/Defaults'), isTrue);
    },
  );

  test(
    'source refresh retains counts and applies updated global Importance',
    () async {
      await storage.saveTableRowData('Defaults', {
        'one': const RowSaveData(
          rowOrder: 2,
          revealed: [true],
          successCount: 8,
        ),
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
      expect(row.successCount, 8);
      expect(row.revealed, [true]);
      expect((await storage.loadKnowledgeTables()).first.importance['one'], 7);
    },
  );

  test(
    'legacy results preserve Importance without inferring historical outcomes',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'personal_results/Defaults',
        jsonEncode({
          'one': {'importance': 8, 'success': 9, 'appeared': 12},
        }),
      );
      final row = (await storage.loadTableRowData('Defaults'))!['one']!;
      expect(row.importance, 8);
      expect(row.appeared, 0);
      final actual =
          jsonDecode(prefs.getString('personal_results/Defaults')!)['one']
              as Map;
      expect(actual.containsKey('success'), isFalse);
      expect(actual.containsKey('appeared'), isFalse);
      expect(actual['appearedCount'], 0);
    },
  );

  test('download replaces counters while retaining study state', () async {
    await storage.saveTableRowData('Defaults', {
      'one': const RowSaveData(
        rowOrder: 2,
        revealed: [true],
        importance: 8,
        successCount: 9,
      ),
    });
    var entries = <Map<String, dynamic>>[
      {
        'table': 'Defaults',
        'entry': 'one',
        'importance': '',
        'failedCount': 1,
        'almostCount': 2,
        'successCount': 3,
        'appearedCount': 6,
      },
    ];
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'ok': true, 'version': 3, 'entries': entries}),
        200,
      ),
    );
    addTearDown(client.close);
    final sync = RatingsSyncService(client: client);
    await sync.download(url);
    var row = (await storage.loadTableRowData('Defaults'))!['one']!;
    expect(row.importance, isNull);
    expect(row.appeared, 6);
    entries = [];
    await sync.download(url);
    expect(await storage.loadPersonalResults(), isEmpty);
    row = (await storage.loadTableRowData('Defaults'))!['one']!;
    expect(row.appeared, 0);
    expect(row.rowOrder, 2);
    expect(row.revealed, [true]);
  });

  test(
    'empty upload replaces the remote snapshot and old endpoints are rejected',
    () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {
          'version': 3,
          'mode': 'replace',
          'entries': [],
        });
        return http.Response(jsonEncode({'ok': true, 'version': 3}), 200);
      });
      addTearDown(client.close);
      expect(await RatingsSyncService(client: client).upload(url), 0);
      final old = MockClient(
        (_) async => http.Response(
          jsonEncode({'ok': true, 'version': 2, 'entries': []}),
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
    'clearing local results clears all counters and preserves settings and study state',
    (tester) async {
      await storage.saveProfileSettings(
        const ProfileSettings(syncUrl: url, autoSync: true),
      );
      await storage.saveTableRowData('Defaults', {
        'one': const RowSaveData(
          rowOrder: 2,
          revealed: [true],
          importance: 9,
          failedCount: 2,
          almostCount: 1,
          successCount: 8,
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
      expect(row.appeared, 0);
    },
  );
}
