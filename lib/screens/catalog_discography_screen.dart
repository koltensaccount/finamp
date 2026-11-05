import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../components/finamp_app_bar_back_button.dart';
import '../components/now_playing_bar.dart';
import '../models/catalog_models.dart';
import 'catalog_album_screen.dart';

enum DiscographyOwnershipFilter { all, inLibrary, unowned }

class CatalogDiscographyScreenArguments {
  const CatalogDiscographyScreenArguments({required this.title, required this.artistName, required this.items});

  final String title;
  final String artistName;
  final List<CatalogSearchResult> items;
}

class CatalogDiscographyScreen extends StatefulWidget {
  const CatalogDiscographyScreen({super.key});
  static const routeName = '/catalog/discography';

  @override
  State<CatalogDiscographyScreen> createState() => _CatalogDiscographyScreenState();
}

class _CatalogDiscographyScreenState extends State<CatalogDiscographyScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  DiscographyOwnershipFilter _filter = DiscographyOwnershipFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    if (rawArgs is! CatalogDiscographyScreenArguments) {
      return Scaffold(
        appBar: AppBar(leading: const FinampAppBarBackButton(), title: const Text('Discography')),
        body: const Center(child: Text('No discography data provided.')),
      );
    }

    final args = rawArgs;
    final allItems = args.items;

    final inLibraryCount = allItems.where((i) => i.isFullyOwned || i.isPartiallyOwned).length;
    final unownedCount = allItems.where((i) => !i.isFullyOwned && !i.isPartiallyOwned).length;

    // Filter items by search query and ownership
    final filtered = allItems
        .where((item) {
          // Ownership filter
          if (_filter == DiscographyOwnershipFilter.inLibrary && !item.isFullyOwned && !item.isPartiallyOwned) {
            return false;
          }
          if (_filter == DiscographyOwnershipFilter.unowned && (item.isFullyOwned || item.isPartiallyOwned)) {
            return false;
          }

          // Query filter
          if (_query.isNotEmpty) {
            final q = _query.toLowerCase();
            final matchTitle = item.title.toLowerCase().contains(q);
            final matchYear = item.firstDate?.toLowerCase().contains(q) ?? false;
            final matchTypes = item.secondaryTypes.any((t) => t.toLowerCase().contains(q));
            if (!matchTitle && !matchYear && !matchTypes) {
              return false;
            }
          }

          return true;
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        leading: const FinampAppBarBackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(args.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              args.artistName,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const NowPlayingBar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search ${args.title.toLowerCase()}...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) => setState(() => _query = val.trim()),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                FilterChip(
                  label: Text('All (${allItems.length})'),
                  selected: _filter == DiscographyOwnershipFilter.all,
                  onSelected: (_) => setState(() => _filter = DiscographyOwnershipFilter.all),
                ),
                if (inLibraryCount > 0) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: const Icon(Icons.check_circle, size: 14, color: Colors.green),
                    label: Text('In Library ($inLibraryCount)'),
                    selected: _filter == DiscographyOwnershipFilter.inLibrary,
                    onSelected: (_) => setState(() => _filter = DiscographyOwnershipFilter.inLibrary),
                  ),
                ],
                if (unownedCount > 0) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: const Icon(Icons.cloud_outlined, size: 14),
                    label: Text('Unowned ($unownedCount)'),
                    selected: _filter == DiscographyOwnershipFilter.unowned,
                    onSelected: (_) => setState(() => _filter = DiscographyOwnershipFilter.unowned),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            _query.isNotEmpty
                                ? 'No ${args.title.toLowerCase()} matching "$_query"'
                                : 'No items match the selected filter',
                            style: const TextStyle(color: Colors.grey, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final album = filtered[index];
                      return _buildAlbumTile(album);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumTile(CatalogSearchResult album) {
    Widget leadingWidget;
    if (album.imageUrl != null && album.imageUrl!.isNotEmpty) {
      leadingWidget = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          album.imageUrl!,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 50,
            height: 50,
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(TablerIcons.disc, size: 28),
          ),
        ),
      );
    } else {
      leadingWidget = Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(TablerIcons.disc, size: 28),
      );
    }

    Widget trailingWidget;
    if (album.isFullyOwned) {
      trailingWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green, width: 1),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: Colors.green),
            SizedBox(width: 4),
            Text(
              'In Library',
              style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    } else if (album.isPartiallyOwned) {
      trailingWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade800, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pie_chart, size: 12, color: Colors.amber.shade800),
            const SizedBox(width: 4),
            Text(
              'Partial',
              style: TextStyle(color: Colors.amber.shade800, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    } else {
      trailingWidget = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_outlined, size: 16, color: Colors.grey),
          SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ],
      );
    }

    final year = album.firstDate != null && album.firstDate!.length >= 4 ? album.firstDate!.substring(0, 4) : null;
    final info = [
      ?year,
      if (album.primaryType != null) album.primaryType,
      if (album.secondaryTypes.isNotEmpty) album.secondaryTypes.join(', '),
    ].join(' • ');

    return ListTile(
      leading: leadingWidget,
      title: Text(
        album.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(info.isNotEmpty ? info : 'Album', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailingWidget,
      onTap: () => Navigator.of(
        context,
      ).pushNamed(CatalogAlbumScreen.routeName, arguments: CatalogAlbumScreenArguments.fromSearchResult(album)),
    );
  }
}
