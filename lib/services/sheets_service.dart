import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/knowledge_entry.dart';
import '../models/knowledge_table.dart';

/// ---------------------------------------------------------------
///  CONFIGURE THIS: replace with your main index sheet's URL.
///  Accepts the regular "share" URL or the /export?format=csv form.
/// ---------------------------------------------------------------
const String kMainSheetUrl =
    'https://docs.google.com/spreadsheets/d/e/2PACX-1vQjnWRTHvXlPrQ32VgPR8qmVU0P-4gEIDmKQyTXxvGx_4hEHlOGOpcJs40xYg44xYeDrh7vnJoKi8Zv/pub?gid=0&single=true&output=csv';

class SheetsService {
  final http.Client? client;

  SheetsService({this.client});

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  /// Downloads the main index sheet and returns one [KnowledgeEntry]
  /// per non-empty row.  Expected CSV format: name , sheet_url
  Future<List<KnowledgeEntry>> fetchMainSheet() async {
    final csvUrl = _toExportCsvUrl(kMainSheetUrl) ?? kMainSheetUrl;
    final rows = await _fetchCsv(csvUrl);
    return rows
        .where((r) => r.length >= 2 && r[0].trim().isNotEmpty)
        .map((r) => KnowledgeEntry(name: r[0].trim(), sheetUrl: r[1].trim()))
        .toList();
  }

  /// Downloads a single knowledge table and returns it as a
  /// [KnowledgeTable] with all rows (including any header row).
  Future<KnowledgeTable> fetchKnowledgeTable(KnowledgeEntry entry) async {
    final csvUrl = _toExportCsvUrl(entry.sheetUrl) ?? entry.sheetUrl;
    final rows = await _fetchCsv(csvUrl);
    final limitedRows = rows.take(_findFirstEmptyRow(rows)).toList();
    final separator = _findFirstEmptyColumn(limitedRows);
    final importance = <String, int>{};
    if (limitedRows.isNotEmpty) {
      final headers = limitedRows.first;
      for (var column = separator + 1; column < headers.length; column++) {
        if (headers[column].trim().toLowerCase() != 'importance') continue;
        for (final row in limitedRows.skip(1)) {
          if (row.isEmpty) continue;
          importance[row.first] =
              (column < row.length ? int.tryParse(row[column].trim()) ?? 5 : 5)
                  .clamp(1, 10);
        }
      }
    }
    return KnowledgeTable(
      importance: importance,
      name: entry.name,
      sourceUrl: entry.sheetUrl,
      rows: _trimTable(rows),
    );
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  Future<List<List<String>>> _fetchCsv(String url) async {
    final response =
        await (client?.get(Uri.parse(url)) ?? http.get(Uri.parse(url)));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} when fetching $url');
    }
    // Explicitly decode as UTF-8 to properly handle special characters.
    final body = utf8.decode(response.bodyBytes);
    return _parseCsv(body);
  }

  /// Crops a table to a rectangular region bounded by:
  /// - the first completely empty row (exclusive), and
  /// - the first completely empty column (exclusive).
  List<List<String>> _trimTable(List<List<String>> rows) {
    if (rows.isEmpty) return rows;

    final rowLimit = _findFirstEmptyRow(rows);
    if (rowLimit == 0) return const <List<String>>[];

    final limitedRows = rows.take(rowLimit).toList(growable: false);
    final columnLimit = _findFirstEmptyColumn(limitedRows);
    if (columnLimit == 0) return const <List<String>>[];

    return limitedRows
        .map((row) => row.take(columnLimit).toList(growable: false))
        .toList(growable: false);
  }

  int _findFirstEmptyRow(List<List<String>> rows) {
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final hasNonEmptyCell = row.any((cell) => cell.trim().isNotEmpty);
      if (!hasNonEmptyCell) return rowIndex;
    }
    return rows.length;
  }

  int _findFirstEmptyColumn(List<List<String>> rows) {
    var maxColumns = 0;
    for (final row in rows) {
      if (row.length > maxColumns) maxColumns = row.length;
    }

    for (var columnIndex = 0; columnIndex < maxColumns; columnIndex++) {
      var hasNonEmptyCell = false;
      for (final row in rows) {
        final cell = columnIndex < row.length ? row[columnIndex] : '';
        if (cell.trim().isNotEmpty) {
          hasNonEmptyCell = true;
          break;
        }
      }
      if (!hasNonEmptyCell) return columnIndex;
    }
    return maxColumns;
  }

  /// Converts any supported Google Sheets URL into the CSV export form.
  /// Returns null when the URL is not a recognised Google Sheets link.
  String? _toExportCsvUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host != 'docs.google.com') return null;

    final segments = uri.pathSegments;
    final dIndex = segments.indexOf('d');
    if (dIndex == -1 || dIndex + 1 >= segments.length) return null;

    final sheetId = segments[dIndex + 1];

    // Pass through any URL that already delivers CSV directly:
    // – /export URLs  (e.g. .../export?format=csv)
    // – /pub URLs with output=csv  (the "published" share format)
    if (segments.contains('export')) return raw.trim();
    if (uri.queryParameters['output'] == 'csv') return raw.trim();

    // Extract gid from the fragment (#gid=0) or query parameter.
    String? gid = uri.queryParameters['gid'];
    if (gid == null && uri.fragment.contains('gid=')) {
      gid = uri.fragment.split('gid=').last.split('&').first;
    }

    var exportUrl =
        'https://docs.google.com/spreadsheets/d/$sheetId/export?format=csv';
    if (gid != null && gid.isNotEmpty) exportUrl += '&gid=$gid';
    return exportUrl;
  }

  /// RFC-4180-compatible CSV parser that handles quoted fields and
  /// quoted fields containing commas or newlines.
  List<List<String>> _parseCsv(String content) {
    // Normalise line endings so we can work with '\n' only.
    final text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final result = <List<String>>[];
    var i = 0;

    while (i <= text.length) {
      final row = <String>[];

      // Parse all fields in the current row.
      while (true) {
        if (i >= text.length) {
          row.add('');
          break;
        }

        if (text[i] == '"') {
          // Quoted field
          i++; // skip opening quote
          final buf = StringBuffer();
          while (i < text.length) {
            final ch = text[i];
            if (ch == '"') {
              if (i + 1 < text.length && text[i + 1] == '"') {
                buf.write('"'); // escaped quote
                i += 2;
              } else {
                i++; // skip closing quote
                break;
              }
            } else {
              buf.write(ch);
              i++;
            }
          }
          row.add(buf.toString());
          // After a quoted field, the next char must be ',' or '\n' or EOF.
          if (i < text.length && text[i] == ',') {
            i++;
            continue; // next field
          }
          break; // end of row
        } else {
          // Unquoted field
          final start = i;
          while (i < text.length && text[i] != ',' && text[i] != '\n') {
            i++;
          }
          row.add(text.substring(start, i));
          if (i < text.length && text[i] == ',') {
            i++;
            continue; // next field
          }
          break; // end of row ('\n' or EOF)
        }
      }

      // Skip the row-ending newline.
      if (i < text.length && text[i] == '\n') i++;

      // Skip completely empty rows (blank lines at end of file).
      if (row.isNotEmpty && !(row.length == 1 && row[0].isEmpty)) {
        result.add(row);
      }

      if (i >= text.length) break;
    }

    return result;
  }
}
