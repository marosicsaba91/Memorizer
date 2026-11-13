import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/row_save_data.dart';
import 'storage_service.dart';

class RatingsSyncService {
  final StorageService storage;
  final http.Client? client;
  Future<void> _pending = Future<void>.value();

  RatingsSyncService({StorageService? storage, this.client})
    : storage = storage ?? StorageService();

  static Uri endpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Enter a valid HTTPS sync URL.');
    }
    return uri;
  }

  // Serialize transfers so startup downloads and uploads cannot overtake each other.
  Future<int> _enqueue(Future<int> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, dynamic>> _request(String url, {Object? body}) async {
    final uri = endpoint(url);
    final connection = client ?? http.Client();
    try {
      var response =
          await (body == null
                  ? connection.get(uri)
                  : connection.post(
                      uri,
                      headers: {'Content-Type': 'text/plain; charset=utf-8'},
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 30));
      // Apps Script redirects POST responses to a GET-only content URL.
      for (
        var i = 0;
        i < 5 && (response.statusCode == 302 || response.statusCode == 303);
        i++
      ) {
        final location = response.headers['location'];
        if (location == null) throw Exception('Sync redirect has no location.');
        response = await connection
            .get(endpoint(uri.resolve(location).toString()))
            .timeout(const Duration(seconds: 30));
      }
      if (response.statusCode != 200) {
        throw Exception('Sync server returned HTTP ${response.statusCode}.');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'The sync URL did not return a JSON object.',
        );
      }
      if (decoded['ok'] != true) {
        throw Exception(
          decoded['error'] ?? 'The sync server rejected the request.',
        );
      }
      if (decoded['version'] != 2) {
        throw const FormatException(
          'Update and redeploy personal-sync.gs to use personal results overrides.',
        );
      }
      return decoded;
    } finally {
      if (client == null) connection.close();
    }
  }

  Future<int> download(String url) => _enqueue(() async {
    final data = await _request(url);
    if (data['version'] != 2 || data['entries'] is! List) {
      throw const FormatException('Unsupported sync data format.');
    }
    final updates = <String, Map<String, RowSaveData>>{};
    // Validate the entire response before changing local storage.
    for (final item in data['entries'] as List) {
      if (item is! Map ||
          item['table'] is! String ||
          (item['table'] as String).trim().isEmpty ||
          item['entry'] is! String ||
          (item['entry'] as String).trim().isEmpty) {
        throw const FormatException(
          'A downloaded entry is missing its table or entry name.',
        );
      }
      int? rating(String field) {
        final value = item[field];
        if (value == null || value == '') return null;
        if (value is! int || value < 1 || value > 10) {
          throw FormatException('$field must be an integer from 1 to 10.');
        }
        return value;
      }

      (updates[item['table'] as String] ??= {})[item['entry']
          as String] = RowSaveData(
        rowOrder: 0,
        revealed: const [],
        importance: rating('importance'),
        success: rating('success'),
      );
    }
    await storage.replacePersonalResults(updates);
    return updates.values.fold<int>(
      0,
      (count, rows) =>
          count +
          rows.values
              .where((row) => row.importance != null || row.success != null)
              .length,
    );
  });

  Future<int> clearLocalResults() => _enqueue(() async {
    await storage.clearPersonalResults();
    return 0;
  });

  Future<int> upload(String url) => _enqueue(() async {
    final entries = <Map<String, dynamic>>[];
    for (final table in (await storage.loadPersonalResults()).entries) {
      for (final row in table.value.entries) {
        if (row.key.trim().isEmpty ||
            (row.value.importance == null && row.value.success == null))
          continue;
        entries.add({
          'table': table.key,
          'entry': row.key,
          'importance': row.value.importance,
          'success': row.value.success,
        });
      }
    }
    await _request(
      url,
      body: {'version': 2, 'mode': 'replace', 'entries': entries},
    );
    return entries.length;
  });
}
