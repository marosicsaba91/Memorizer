import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../models/knowledge_entry.dart';
import '../models/knowledge_table.dart';
import '../services/sheets_service.dart';
import '../services/storage_service.dart';
import '../services/ratings_sync_service.dart';
import 'knowledge_table_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final RatingsSyncService? syncService;

  const HomeScreen({super.key, this.syncService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _sheetsService = SheetsService();
  final _storageService = StorageService();
  late final _sync = widget.syncService ?? RatingsSyncService();
  bool _starting = true;

  List<KnowledgeTable> _tables = [];
  bool _isRefreshing = false;
  final Set<String> _updatingTableNames = <String>{};

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _loadLocal();
      final settings = await _storageService.loadProfileSettings();
      if (settings.autoSync && settings.syncUrl.isNotEmpty) {
        await _sync.download(settings.syncUrl);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Startup sync failed. Local data is available: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _ratingsChanged() async {
    final settings = await _storageService.loadProfileSettings();
    if (settings.autoSync && settings.syncUrl.isNotEmpty) {
      await _sync.upload(settings.syncUrl);
    }
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
              '${tables.length} table${tables.length == 1 ? '' : 's'} updated',
            ),
          ),
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

  Future<void> _refreshSingleTable(KnowledgeTable table) async {
    if (_updatingTableNames.contains(table.name)) return;

    final sourceUrl = table.sourceUrl?.trim();
    if (sourceUrl == null || sourceUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This table has no saved source URL to update from.'),
          ),
        );
      }
      return;
    }

    setState(() => _updatingTableNames.add(table.name));
    try {
      final refreshed = await _sheetsService.fetchKnowledgeTable(
        KnowledgeEntry(name: table.name, sheetUrl: sourceUrl),
      );

      final index = _tables.indexWhere((t) => t.name == table.name);
      if (index == -1) return;

      final updatedTables = List<KnowledgeTable>.from(_tables);
      updatedTables[index] = refreshed;
      await _storageService.saveKnowledgeTables(updatedTables);

      if (mounted) {
        setState(() => _tables = updatedTables);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Updated ${table.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed for ${table.name}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingTableNames.remove(table.name));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Memorizer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: _starting
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(sync: _sync),
                    ),
                  ),
          ),
          _isRefreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 3.5),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh tables',
                  onPressed: _starting ? null : _refresh,
                ),
        ],
      ),
      body: _starting
          ? const Center(child: CircularProgressIndicator())
          : _tables.isEmpty
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
                final dataRowCount = max(0, table.rows.length - 1);
                final isUpdating = _updatingTableNames.contains(table.name);
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.table_chart_outlined),
                    title: Text(table.name),
                    subtitle: Text(
                      '$dataRowCount row${dataRowCount == 1 ? '' : 's'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isUpdating)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Update this table',
                            onPressed: () => _refreshSingleTable(table),
                          ),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => KnowledgeTableScreen(
                          table: table,
                          onRatingsChanged: _ratingsChanged,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
