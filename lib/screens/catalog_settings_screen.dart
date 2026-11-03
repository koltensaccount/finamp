import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../components/finamp_app_bar_back_button.dart';
import '../services/catalog_api_client.dart';
import '../services/catalog_credential_store.dart';

class CatalogSettingsScreen extends StatefulWidget {
  const CatalogSettingsScreen({super.key});
  static const routeName = '/settings/catalog';

  @override
  State<CatalogSettingsScreen> createState() => _CatalogSettingsScreenState();
}

class _CatalogSettingsScreenState extends State<CatalogSettingsScreen> {
  final _endpointController = TextEditingController(text: 'http://127.0.0.1:8765');
  final _tokenController = TextEditingController();
  final _credentialStore = SecureCatalogCredentialStore();

  bool _loading = true;
  bool _testing = false;
  bool _obscureToken = true;
  String? _statusMessage;
  bool _statusSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final credentials = await _credentialStore.read();
    if (credentials != null) {
      _endpointController.text = credentials.endpoint.toString();
      _tokenController.text = credentials.token;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final endpointStr = _endpointController.text.trim();
    final token = _tokenController.text.trim();
    final uri = Uri.tryParse(endpointStr);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter a valid HTTP/HTTPS endpoint URI.';
        _statusSuccess = false;
      });
      return;
    }
    if (token.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter an authorization token.';
        _statusSuccess = false;
      });
      return;
    }

    setState(() {
      _testing = true;
      _statusMessage = null;
    });

    try {
      final tempStore = _StaticCredentialStore(CatalogCredentials(endpoint: uri, token: token));
      final testClient = CatalogApiClient(credentials: tempStore);
      final res = await testClient.search('test');
      setState(() {
        _statusSuccess = true;
        _statusMessage = 'Connection successful! (Cached hits: ${res.results.length})';
      });
    } catch (e) {
      setState(() {
        _statusSuccess = false;
        _statusMessage = 'Connection failed: $e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final endpointStr = _endpointController.text.trim();
    final token = _tokenController.text.trim();
    final uri = Uri.tryParse(endpointStr);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid endpoint URI')),
      );
      return;
    }

    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token cannot be empty')),
      );
      return;
    }

    await _credentialStore.save(CatalogCredentials(endpoint: uri, token: token));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catalog credentials saved successfully.')),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _clear() async {
    await _credentialStore.clear();
    _tokenController.clear();
    if (mounted) {
      setState(() {
        _statusMessage = 'Credentials cleared.';
        _statusSuccess = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catalog credentials cleared.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Catalog Discovery'),
          leading: const FinampAppBarBackButton(),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog Discovery'),
        leading: const FinampAppBarBackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Connect to your server-side music discovery catalog. '
            'This enables unified search across MusicBrainz and your self-hosted Jellyfin server.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _endpointController,
            decoration: const InputDecoration(
              labelText: 'Catalog API Endpoint',
              hintText: 'http://127.0.0.1:8765',
              prefixIcon: Icon(TablerIcons.server),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            obscureText: _obscureToken,
            decoration: InputDecoration(
              labelText: 'Bearer Token',
              prefixIcon: const Icon(TablerIcons.key),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusSuccess ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _statusSuccess ? Colors.green : Colors.red,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusSuccess ? Icons.check_circle : Icons.error,
                    color: _statusSuccess ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        color: _statusSuccess ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(TablerIcons.plug_connected),
                  label: const Text('Test Connection'),
                  onPressed: _testing ? null : _testConnection,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  onPressed: _save,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Clear Credentials', style: TextStyle(color: Colors.red)),
            onPressed: _clear,
          ),
        ],
      ),
    );
  }
}

class _StaticCredentialStore implements CatalogCredentialStore {
  _StaticCredentialStore(this.credentials);
  final CatalogCredentials credentials;

  @override
  Future<CatalogCredentials?> read() async => credentials;
  @override
  Future<void> save(CatalogCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}
