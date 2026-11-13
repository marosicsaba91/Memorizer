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
      expect(table.importance, {'one': 2, 'two': 5, 'three': 1, 'four': 5});
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
      expect(saved['one']!.success, isNull);
      expect(saved['two']!.importance, isNull);
      expect(saved['two']!.success, isNull);
      saved['one'] = const RowSaveData(
        rowOrder: 0,
        revealed: [],
        importance: 3,
        success: 10,
      );
      await storage.saveTableRowData('Test', saved);
      await storage.saveKnowledgeTables([table]);
      saved = (await storage.loadTableRowData('Test'))!;
      expect(saved['one']!.importance, 3);
      expect(saved['one']!.success, 10);
    },
  );

  testWidgets('index edits both ratings and persists after reopening', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const table = KnowledgeTable(
      name: 'UI',
      rows: [
        ['Word'],
        ['one'],
      ],
      importance: {'one': 9},
    );
    Widget screen() =>
        const MaterialApp(home: KnowledgeTableScreen(table: table));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    expect(find.text('Importance'), findsOneWidget);
    expect(find.text('Success'), findsOneWidget);
    await tester.tap(find.byTooltip('Increase Importance'));
    await tester.pumpAndSettle();
    final increase = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip('Increase Importance'),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(increase.onPressed, isNull);
    final decrease = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip('Decrease Success'),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(decrease.onPressed, isNotNull);
    await tester.tap(find.byTooltip('Increase Success'));
    await tester.pumpAndSettle();
    final saved = (await StorageService().loadTableRowData('UI'))!['one']!;
    expect(saved.importance, 10);
    expect(saved.success, 6);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  test('migrates saved difficulty to success', () {
    final saved = RowSaveData.fromJson({'difficulty': 8, 'rowOrder': 2});
    expect(saved.success, 8);
    expect(saved.importance, isNull);
    expect(saved.toJson().containsKey('difficulty'), isFalse);
  });
}
