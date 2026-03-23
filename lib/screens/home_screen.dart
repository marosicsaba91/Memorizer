import 'package:flutter/material.dart';

import '../models/knowledge_table.dart';
import '../services/sheets_service.dart';
import '../services/storage_service.dart';
import 'knowledge_table_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _sheetsService = SheetsService();
  final _storageService = StorageService();

  List<KnowledgeTable> _tables = [];
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    final tables = await _storageService.loadKnowledgeTables();
    if (mounted) setState(() => _tables = tables);
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      final entries = await _sheetsService.fetchMainSheet();

      final tables = <KnowledgeTable>[];
      for (final entry in entries) {
        final table = await _sheetsService.fetchKnowledgeTable(entry);
        tables.add(table);
      }

      await _storageService.saveKnowledgeTables(tables);
      if (mounted) {
        setState(() => _tables = tables);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${tables.length} table${tables.length == 1 ? '' : 's'} updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memorizer'),
        actions: [
          _isRefreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh tables',
                  onPressed: _refresh,
                ),
        ],
      ),
      body: _tables.isEmpty
          ? const Center(
              child: Text(
                'No tables saved yet.\nTap the refresh button to download.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _tables.length,
              itemBuilder: (context, index) {
                final table = _tables[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.table_chart_outlined),
                    title: Text(table.name),
                    subtitle: Text(
                        '${table.rows.length} row${table.rows.length == 1 ? '' : 's'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            KnowledgeTableScreen(table: table),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
