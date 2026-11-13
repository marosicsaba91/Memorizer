import 'package:material_ui/material_ui.dart';

import '../models/profile_settings.dart';
import '../services/ratings_sync_service.dart';
import '../services/storage_service.dart';

class ProfileScreen extends StatefulWidget {
  final RatingsSyncService sync;

  const ProfileScreen({super.key, required this.sync});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = StorageService();
  final _url = TextEditingController();
  bool _autoSync = false;
  bool _loading = true;
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _storage.loadProfileSettings();
    if (!mounted) return;
    setState(() {
      _url.text = settings.syncUrl;
      _autoSync = settings.autoSync;
      _loading = false;
    });
  }

  Future<void> _run({bool? download}) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final url = _url.text.trim();
      if (url.isNotEmpty) RatingsSyncService.endpoint(url);
      if (url.isEmpty && (_autoSync || download != null)) {
        throw const FormatException(
          'Enter a sync URL first, or disable autosync to use local storage only.',
        );
      }
      await _storage.saveProfileSettings(
        ProfileSettings(syncUrl: url, autoSync: _autoSync),
      );
      String message = 'Profile settings saved.';
      if (download != null) {
        final count = download
            ? await widget.sync.download(url)
            : await widget.sync.upload(url);
        message = download
            ? 'Downloaded ratings for $count entries.'
            : 'Uploaded ratings for $count entries.';
      }
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _clearResults() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.sync.clearLocalResults();
      if (mounted)
        setState(
          () => _message =
              'Local personal results cleared. Table defaults are restored. Web results are unchanged.',
        );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Personal ratings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sync Importance and Success across devices. Leave the URL empty to use local storage only.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _url,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Sync URL',
                  hintText: 'https://script.google.com/macros/s/…/exec',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable autosync'),
                subtitle: const Text(
                  'Download when the app starts. Upload after each Importance or Success change.',
                ),
                value: _autoSync,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _autoSync = value),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : () => _run(),
                child: const Text('Save settings'),
              ),
              const SizedBox(height: 24),
              const Text(
                'Only personal changes are synced. Empty values use table defaults. Download replaces local personal results; upload replaces web personal results, including resets.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(download: true),
                icon: const Icon(Icons.download),
                label: const Text('Refresh local data from web'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(download: false),
                icon: const Icon(Icons.upload),
                label: const Text('Refresh web data from local'),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _busy ? null : _clearResults,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear All Local Personal Results'),
              ),
              const Text(
                'Restores table defaults locally. Web results stay unchanged until you upload.',
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: LinearProgressIndicator(),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Sync failed: $_error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
  );
}
