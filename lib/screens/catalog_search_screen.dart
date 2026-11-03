import 'package:finamp/models/catalog_models.dart';
import 'package:finamp/services/catalog_api_client.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

class CatalogSearchScreen extends StatefulWidget {
  const CatalogSearchScreen({super.key});
  static const routeName = '/catalog-search';
  @override
  State<CatalogSearchScreen> createState() => _CatalogSearchScreenState();
}

class _CatalogSearchScreenState extends State<CatalogSearchScreen> {
  final _controller = TextEditingController();
  CatalogSearchResponse? _response;
  String? _error;
  bool _loading = false;

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _response = await GetIt.instance<CatalogApiClient>().search(query);
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Artists, albums, and tracks',
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Catalog unavailable. Your downloaded and Jellyfin music remain available.\n$_error'),
          ),
        Expanded(child: ListView(children: _response?.results.map(_tile).toList() ?? const [])),
      ],
    ),
  );

  Widget _tile(CatalogSearchResult result) {
    final availability = result.availability;
    final status = availability == null
        ? result.kind
        : switch (availability.state) {
            CatalogAvailabilityState.available => availability.canPlay ? 'Available' : 'Choose a local version',
            CatalogAvailabilityState.possiblyAvailable => 'Possibly available',
            CatalogAvailabilityState.pending => 'Requested',
            CatalogAvailabilityState.notFound => 'Not in your library',
          };
    return ListTile(
      title: Text(result.title),
      subtitle: Text(status),
      trailing: result.kind == 'album' && result.editionIds.isNotEmpty
          ? IconButton(icon: const Icon(Icons.add), onPressed: () => _request(result.editionIds.first))
          : null,
    );
  }

  Future<void> _request(String releaseId) async {
    final request = await GetIt.instance<CatalogApiClient>().requestAlbum(releaseId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(request.dispatchEnabled ? request.state : 'Request queued; downloading is not enabled yet.'),
        ),
      );
    }
  }
}
