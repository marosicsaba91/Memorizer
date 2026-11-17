import 'package:material_ui/material_ui.dart';
import 'package:memorizer/screens/knowledge_table_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memorizer/models/knowledge_entry.dart';
import 'package:memorizer/models/knowledge_table.dart';
import 'package:memorizer/models/row_save_data.dart';
import 'package:memorizer/services/sheets_service.dart';
import 'package:memorizer/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'only a trailing header marker places a column on a separate line',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const table = KnowledgeTable(
        name: 'Layout',
        rows: [
          ['Question', 'Answer', 'Notes*'],
          ['one', 'two\nlines', 'single-line note'],
        ],
      );
      await tester.pumpWidget(
        const MaterialApp(home: KnowledgeTableScreen(table: table)),
      );
      await tester.pumpAndSettle();
      final question = tester.getCenter(find.text('Question'));
      final answer = tester.getCenter(find.text('Answer'));
      final notes = tester.getCenter(find.text('Notes'));
      expect(answer.dy, closeTo(question.dy, 0.1));
      expect(notes.dy, greaterThan(question.dy));
      expect(find.text('Notes*'), findsNothing);
      await tester.tap(find.text('Answer'));
      await tester.pumpAndSettle();
      expect(find.text('two\nlines'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Notes')).dy,
        greaterThan(tester.getCenter(find.text('two\nlines')).dy),
      );
    },
  );

  test(
    'loads only hidden Importance beyond separator with defaults and bounds',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          'Word,Meaning,, Success ,Other,,IMPORTANCE\n'
          'one,first,,8,ignored,,2\n'
          'two,second,,,ignored,,\n'
          'three,third,,99,ignored,,-1\n'
          'four,fourth,,invalid,ignored,,invalid',
          200,
        ),
      );
      addTearDown(client.close);
      final table = await SheetsService(client: client).fetchKnowledgeTable(
        KnowledgeEntry(name: 'Test', sheetUrl: 'https://example.com/table.csv'),
      );
      expect(table.rows, [
        ['Word', 'Meaning'],
        ['one', 'first'],
        ['two', 'second'],
        ['three', 'third'],
        ['four', 'fourth'],
      ]);
      expect(table.importance, {'one': 2, 'three': 0});
      final cached = KnowledgeTable.deserialize(table.serialize());
      expect(table.toJson().containsKey('success'), isFalse);
      expect(cached.importance, table.importance);
    },
  );

  test(
    'stores every row and preserves local ratings through refresh',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      const table = KnowledgeTable(
        name: 'Test',
        rows: [
          ['Word'],
          ['one'],
          ['two'],
        ],
        importance: {'one': 9},
      );
      await storage.saveKnowledgeTables([table]);
      var saved = (await storage.loadTableRowData('Test'))!;
      expect(saved['one']!.importance, isNull);
      expect(saved['one']!.successCount, 0);
      expect(saved['two']!.importance, isNull);
      expect(saved['two']!.successCount, 0);
      saved['one'] = const RowSaveData(
        rowOrder: 0,
        revealed: [],
        importance: 3,
        successCount: 10,
      );
      await storage.saveTableRowData('Test', saved);
      await storage.saveKnowledgeTables([table]);
      saved = (await storage.loadTableRowData('Test'))!;
      expect(saved['one']!.importance, 3);
      expect(saved['one']!.successCount, 10);
    },
  );

  testWidgets(
    'entry popup edits Importance and displays stored outcome counts',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const table = KnowledgeTable(
        name: 'UI',
        rows: [
          ['Word'],
          ['one'],
        ],
        importance: {'one': 9},
      );
      await StorageService().saveTableRowData('UI', {
        'one': const RowSaveData(
          rowOrder: 0,
          revealed: [],
          failedCount: 2,
          almostCount: 3,
          successCount: 4,
        ),
      });
      await tester.pumpWidget(
        const MaterialApp(home: KnowledgeTableScreen(table: table)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1').first);
      await tester.pumpAndSettle();
      expect(find.text('Failed Count: 2'), findsOneWidget);
      expect(find.text('Almost Count: 3'), findsOneWidget);
      expect(find.text('Success Count: 4'), findsOneWidget);
      expect(find.text('Appeared Count: 9'), findsOneWidget);
      await tester.tap(find.byTooltip('Increase Importance'));
      await tester.pumpAndSettle();
      final saved = (await StorageService().loadTableRowData('UI'))!['one']!;
      expect(saved.importance, 10);
      expect(saved.appeared, 9);
    },
  );

  test('legacy scalar ratings do not fabricate outcome counts', () {
    final saved = RowSaveData.fromJson({'difficulty': 8, 'rowOrder': 2});
    expect(saved.successCount, 0);
    expect(saved.importance, isNull);
    expect(saved.toJson().containsKey('difficulty'), isFalse);
  });
}
