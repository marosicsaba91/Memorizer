import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memorizer/models/knowledge_table.dart';
import 'package:memorizer/models/profile_settings.dart';
import 'package:memorizer/models/row_save_data.dart';
import 'package:memorizer/screens/home_screen.dart';
import 'package:memorizer/screens/profile_screen.dart';
import 'package:memorizer/services/ratings_sync_service.dart';
import 'package:memorizer/services/storage_service.dart';

const url = 'https://script.google.com/macros/s/test/exec';
const table = KnowledgeTable(
  name: 'Words',
  rows: [
    ['Word'],
    ['one'],
    ['two'],
  ],
);
http.Response response(Object value) => http.Response(jsonEncode(value), 200);
Map<String, dynamic> ratings() => {
  'ok': true,
  'version': 2,
  'entries': [
    {'table': 'Words', 'entry': 'one', 'importance': 8, 'success': 3},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.saveKnowledgeTables([table]);
  });

  test('download preserves study state and other rows', () async {
    final saved = (await storage.loadTableRowData('Words'))!;
    saved['one'] = const RowSaveData(rowOrder: 4, revealed: [true], success: 5);
    await storage.saveTableRowData('Words', saved);
    final client = MockClient((_) async => response(ratings()));
    addTearDown(client.close);
    expect(await RatingsSyncService(client: client).download(url), 1);
    final updated = (await storage.loadTableRowData('Words'))!;
    expect(updated['one']!.importance, 8);
    expect(updated['one']!.success, 3);
    expect(updated['one']!.rowOrder, 4);
    expect(updated['one']!.revealed, [true]);
    expect(updated['two']!.success, isNull);
  });

  test('invalid response leaves all local ratings intact', () async {
    final data = ratings();
    (data['entries'] as List).add({
      'table': 'Words',
      'entry': 'two',
      'success': 20,
    });
    final client = MockClient((_) async => response(data));
    addTearDown(client.close);
    await expectLater(
      RatingsSyncService(client: client).download(url),
      throwsFormatException,
    );
    expect(
      (await storage.loadTableRowData('Words'))!['one']!.importance,
      isNull,
    );
  });

  test('upload sends ratings only and follows Apps Script redirects', () async {
    final saved = (await storage.loadTableRowData('Words'))!;
    saved['one'] = const RowSaveData(rowOrder: 0, revealed: [], success: 6);
    await storage.saveTableRowData('Words', saved);
    var calls = 0;
    final client = MockClient((request) async {
      if (++calls == 1) {
        expect(request.method, 'POST');
        expect(request.headers['content-type'], startsWith('text/plain'));
        final body = jsonDecode(request.body) as Map;
        expect(body['version'], 2);
        expect(body['entries'], [
          {'table': 'Words', 'entry': 'one', 'importance': null, 'success': 6},
        ]);
        return http.Response(
          '',
          302,
          headers: {'location': 'https://script.googleusercontent.com/result'},
        );
      }
      expect(request.method, 'GET');
      expect(request.url.host, 'script.googleusercontent.com');
      return response({'ok': true, 'version': 2});
    });
    addTearDown(client.close);
    expect(await RatingsSyncService(client: client).upload(url), 1);
    expect(calls, 2);
  });

  test('failed sync permits retry', () async {
    var calls = 0;
    final client = MockClient(
      (_) async => ++calls == 1
          ? response({'ok': false, 'error': 'Unavailable'})
          : response(ratings()),
    );
    addTearDown(client.close);
    final sync = RatingsSyncService(client: client);
    await expectLater(sync.download(url), throwsException);
    expect(await sync.download(url), 1);
  });

  testWidgets(
    'Profile persists URL and autosync and supports manual transfers',
    (tester) async {
      final methods = <String>[];
      final client = MockClient((request) async {
        methods.add(request.method);
        return response(
          request.method == 'GET' ? ratings() : {'ok': true, 'version': 2},
        );
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(sync: RatingsSyncService(client: client)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), url);
      await tester.tap(find.text('Enable autosync'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      final settings = await storage.loadProfileSettings();
      expect(settings.syncUrl, url);
      expect(settings.autoSync, isTrue);
      expect(methods, isEmpty);
      await tester.ensureVisible(find.text('Refresh local data from web'));
      await tester.tap(find.text('Refresh local data from web'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Refresh web data from local'));
      await tester.tap(find.text('Refresh web data from local'));
      await tester.pumpAndSettle();
      expect(methods, ['GET', 'POST']);
    },
  );

  for (final enabled in [true, false]) {
    testWidgets(
      'autosync enabled=$enabled gates startup download and rating uploads',
      (tester) async {
        await storage.saveProfileSettings(
          ProfileSettings(syncUrl: url, autoSync: enabled),
        );
        final methods = <String>[];
        final client = MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'POST') {
            expect(jsonDecode(request.body)['entries'].first['importance'], 9);
            return response({'ok': true, 'version': 2});
          }
          return response(ratings());
        });
        addTearDown(client.close);
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(syncService: RatingsSyncService(client: client)),
          ),
        );
        await tester.pumpAndSettle();
        expect(methods, enabled ? ['GET'] : isEmpty);
        await tester.tap(find.text('Words'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Increase Importance'));
        await tester.pumpAndSettle();
        expect(methods, enabled ? ['GET', 'POST'] : isEmpty);
        expect(
          (await storage.loadTableRowData('Words'))!['one']!.importance,
          enabled ? 9 : 6,
        );
      },
    );
  }
}
