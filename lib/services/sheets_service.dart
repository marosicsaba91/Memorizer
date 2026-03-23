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
        .map((r) =>
            KnowledgeEntry(name: r[0].trim(), sheetUrl: r[1].trim()))
        .toList();
  }

  /// Downloads a single knowledge table and returns it as a
  /// [KnowledgeTable] with all rows (including any header row).
  Future<KnowledgeTable> fetchKnowledgeTable(KnowledgeEntry entry) async {
    final csvUrl =
        _toExportCsvUrl(entry.sheetUrl) ?? entry.sheetUrl;
    final rows = await _fetchCsv(csvUrl);
    return KnowledgeTable(name: entry.name, rows: rows);
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  Future<List<List<String>>> _fetchCsv(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception(
          'HTTP ${response.statusCode} when fetching $url');
    }
    // Explicitly decode as UTF-8 to properly handle special characters.
    final body = utf8.decode(response.bodyBytes);
    return _parseCsv(body);
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
      gid = uri.fragment
          .split('gid=')
          .last
          .split('&')
          .first;
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
    final text =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

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
      if (row.isNotEmpty &&
          !(row.length == 1 && row[0].isEmpty)) {
        result.add(row);
      }

      if (i >= text.length) break;
    }

    return result;
  }
}
