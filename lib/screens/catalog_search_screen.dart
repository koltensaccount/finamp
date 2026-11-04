import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../components/finamp_app_bar_back_button.dart';
import '../components/now_playing_bar.dart';
import '../models/catalog_models.dart';
import '../services/catalog_api_client.dart';
import '../services/catalog_playback_helper.dart';
import 'catalog_album_screen.dart';
import 'catalog_artist_screen.dart';
import '../services/artist_image_service.dart';

enum CatalogSearchCategory { all, artists, albums, songs }
enum CatalogSearchScope { musicSearch, library }

class RecentSearchItem {
  const RecentSearchItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String kind;
  final String? imageUrl;
}

class CatalogSearchScreen extends StatefulWidget {
  const CatalogSearchScreen({super.key, this.isTab = false});
  static const routeName = '/catalog-search';
  final bool isTab;

  @override
  State<CatalogSearchScreen> createState() => _CatalogSearchScreenState();
}

class _CatalogSearchScreenState extends State<CatalogSearchScreen> {
  final _controller = TextEditingController();
  CatalogSearchResponse? _response;
  String? _error;
  bool _loading = false;
  CatalogSearchCategory _category = CatalogSearchCategory.all;
  CatalogSearchScope _scope = CatalogSearchScope.musicSearch;

  static const Color appleAccentColor = Color(0xFFFA2D48);

  final List<RecentSearchItem> _recentSearches = [
    RecentSearchItem(
      id: 'e0c97a4d-c392-41a9-a374-57af3e3eeab3',
      title: 'Geese',
      subtitle: 'Artist',
      kind: 'artist',
      imageUrl: ArtistImageService.getKnownArtistImageUrl('geese'),
    ),
    RecentSearchItem(
      id: 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
      title: 'The Beatles',
      subtitle: 'Artist',
      kind: 'artist',
      imageUrl: ArtistImageService.getKnownArtistImageUrl('the beatles'),
    ),
  ];

  @override
  void initState() {
    super.initState();
    const initialQuery = String.fromEnvironment('DEBUG_SEARCH_QUERY', defaultValue: '');
    if (initialQuery.isNotEmpty) {
      _controller.text = initialQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  void _addRecentSearch(RecentSearchItem item) {
    _recentSearches.removeWhere((x) => x.id == item.id || x.title.toLowerCase() == item.title.toLowerCase());
    _recentSearches.insert(0, item);
    if (_recentSearches.length > 12) _recentSearches.removeLast();
  }

  Future<void> _search({bool refresh = false}) async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _category = CatalogSearchCategory.all;
    });

    try {
      final client = GetIt.instance<CatalogApiClient>();
      _response = await client.search(query, refresh: refresh);
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      appBar: widget.isTab
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: const FinampAppBarBackButton(),
              title: null,
            ),
      bottomNavigationBar: widget.isTab ? null : const NowPlayingBar(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Apple-style Large Left-Aligned Page Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                'Search',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            // Clean Apple-style Search Input Field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Artists, Songs, Lyrics & More',
                          hintStyle: TextStyle(
                            fontSize: 14.5,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_controller.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _controller.clear();
                          setState(() => _response = null);
                        },
                        child: Icon(
                          Icons.cancel_rounded,
                          size: 18,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Apple-style Cupertino Sliding Segmented Scope Switcher
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<CatalogSearchScope>(
                  groupValue: _scope,
                  backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
                  thumbColor: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                  children: {
                    CatalogSearchScope.musicSearch: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      child: Text(
                        'Music Search',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    CatalogSearchScope.library: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      child: Text(
                        'Library',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  },
                  onValueChanged: (val) {
                    if (val != null) setState(() => _scope = val);
                  },
                ),
              ),
            ),
            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: appleAccentColor,
              ),
            Expanded(
              child: _buildBodyContent(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent(bool isDark) {
    if (_response == null && !_loading && _error == null) {
      return _buildRecentlySearchedView(isDark);
    }

    final allResults = _response?.results ?? const [];
    final results = _scope == CatalogSearchScope.library
        ? allResults
            .where((r) => r.isFullyOwned || r.isPartiallyOwned || (r.availability?.canPlay ?? false))
            .toList()
        : allResults;

    if (results.isEmpty && !_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _scope == CatalogSearchScope.library
                  ? 'No matching items found in your library'
                  : 'No catalog results found',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (_scope == CatalogSearchScope.library)
              TextButton(
                child: const Text('Search full catalog', style: TextStyle(color: appleAccentColor)),
                onPressed: () => setState(() => _scope = CatalogSearchScope.musicSearch),
              )
            else
              TextButton(
                child: const Text('Retry Search', style: TextStyle(color: appleAccentColor)),
                onPressed: () => _search(refresh: true),
              ),
          ],
        ),
      );
    }

    final artists = results.where((r) => r.kind == 'artist').toList();
    final albums = results.where((r) => r.kind == 'album').toList();
    final tracks = results.where((r) => r.kind == 'track').toList();

    return switch (_category) {
      CatalogSearchCategory.artists => _buildCategoryList(artists, 'Artists', isDark),
      CatalogSearchCategory.albums => _buildCategoryList(albums, 'Albums', isDark),
      CatalogSearchCategory.songs => _buildCategoryList(tracks, 'Songs', isDark),
      CatalogSearchCategory.all => _buildAllResultsView(
          artists: artists,
          albums: albums,
          tracks: tracks,
          isDark: isDark,
        ),
    };
  }

  Widget _buildCategoryList(List<CatalogSearchResult> items, String title, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: () => setState(() => _category = CatalogSearchCategory.all),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: items.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 72,
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
            ),
            itemBuilder: (context, index) => _tile(items[index], isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentlySearchedView(bool isDark) {
    if (_recentSearches.isEmpty) {
      return Center(
        child: Text(
          'Artists, Songs, Lyrics & More',
          style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recently Searched',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => setState(() => _recentSearches.clear()),
              child: const Text(
                'Clear',
                style: TextStyle(color: appleAccentColor, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ..._recentSearches.map((item) {
          final artistImg = item.imageUrl ??
              ArtistImageService.getKnownArtistImageUrl(item.title) ??
              ArtistImageService.getKnownArtistImageUrl(item.id);
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 2),
            leading: item.kind == 'artist'
                ? ClipOval(
                    child: artistImg != null
                        ? Image.network(
                            artistImg,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => CircleAvatar(
                              radius: 22,
                              backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                              child: const Icon(Icons.person, size: 22),
                            ),
                          )
                        : CircleAvatar(
                            radius: 22,
                            backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                            child: const Icon(Icons.person, size: 22),
                          ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 44,
                      height: 44,
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                      child: const Icon(Icons.album_rounded, size: 24),
                    ),
                  ),
            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            subtitle: Text(item.subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
            onTap: () {
              if (item.kind == 'artist') {
                Navigator.of(context).pushNamed(
                  CatalogArtistScreen.routeName,
                  arguments: CatalogArtistScreenArguments(artistMbid: item.id, initialName: item.title),
                );
              } else {
                _controller.text = item.title;
                _search();
              }
            },
          );
        }),
      ],
    );
  }

  Widget _buildAllResultsView({
    required List<CatalogSearchResult> artists,
    required List<CatalogSearchResult> albums,
    required List<CatalogSearchResult> tracks,
    required bool isDark,
  }) {
    CatalogSearchResult? topResult;
    final queryLower = _controller.text.trim().toLowerCase();

    if (artists.isNotEmpty) {
      topResult = artists.firstWhere(
        (a) => a.title.toLowerCase() == queryLower,
        orElse: () => artists.first,
      );
    } else if (albums.isNotEmpty) {
      topResult = albums.first;
    } else if (tracks.isNotEmpty) {
      topResult = tracks.first;
    }

    final otherArtists = topResult != null && topResult.kind == 'artist'
        ? artists.where((a) => a.id != topResult!.id).toList()
        : artists;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        if (topResult != null) ...[
          _buildSectionHeader('Top Result', null),
          _buildTopResultCard(topResult, isDark),
          const SizedBox(height: 16),
        ],
        if (albums.isNotEmpty) ...[
          _buildSectionHeader(
            'Albums',
            albums.length,
            onSeeAll: () => setState(() => _category = CatalogSearchCategory.albums),
          ),
          ...albums.take(4).map((a) => _tile(a, isDark)),
          const SizedBox(height: 16),
        ],
        if (tracks.isNotEmpty) ...[
          _buildSectionHeader(
            'Songs',
            tracks.length,
            onSeeAll: () => setState(() => _category = CatalogSearchCategory.songs),
          ),
          ...tracks.take(5).map((t) => _tile(t, isDark)),
          const SizedBox(height: 16),
        ],
        if (otherArtists.isNotEmpty) ...[
          _buildSectionHeader(
            'Artists',
            otherArtists.length,
            onSeeAll: () => setState(() => _category = CatalogSearchCategory.artists),
          ),
          ...otherArtists.take(3).map((ar) => _tile(ar, isDark)),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildTopResultCard(CatalogSearchResult result, bool isDark) {
    if (result.kind == 'artist') {
      final artistImg = result.imageUrl ??
          ArtistImageService.getKnownArtistImageUrl(result.title) ??
          ArtistImageService.getKnownArtistImageUrl(result.id);
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _addRecentSearch(RecentSearchItem(
              id: result.id,
              title: result.title,
              subtitle: 'Artist',
              kind: 'artist',
              imageUrl: artistImg,
            ));
            Navigator.of(context).pushNamed(
              CatalogArtistScreen.routeName,
              arguments: CatalogArtistScreenArguments(artistMbid: result.id, initialName: result.title),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ClipOval(
                  child: artistImg != null
                      ? Image.network(
                          artistImg,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => CircleAvatar(
                            radius: 32,
                            backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                            child: const Icon(Icons.person, size: 32),
                          ),
                        )
                      : CircleAvatar(
                          radius: 32,
                          backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          child: const Icon(Icons.person, size: 32),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Artist',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 24, color: Colors.grey),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _addRecentSearch(RecentSearchItem(
            id: result.id,
            title: result.title,
            subtitle: result.displayArtist ?? 'Album',
            kind: 'album',
          ));
          Navigator.of(context).pushNamed(
            CatalogAlbumScreen.routeName,
            arguments: CatalogAlbumScreenArguments.fromSearchResult(result),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: result.imageUrl != null && result.imageUrl!.isNotEmpty
                    ? Image.network(
                        result.imageUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 64,
                          height: 64,
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          child: const Icon(Icons.album_rounded, size: 32),
                        ),
                      )
                    : Container(
                        width: 64,
                        height: 64,
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        child: const Icon(Icons.album_rounded, size: 32),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (result.displayArtist != null) result.displayArtist!,
                        'Album',
                        if (result.firstDate != null && result.firstDate!.length >= 4)
                          result.firstDate!.substring(0, 4),
                      ].join(' • '),
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 24, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int? count, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See All',
                style: TextStyle(
                  color: appleAccentColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(CatalogSearchResult result, bool isDark) {
    if (result.kind == 'artist') {
      final artistImg = result.imageUrl ??
          ArtistImageService.getKnownArtistImageUrl(result.title) ??
          ArtistImageService.getKnownArtistImageUrl(result.id);
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: ClipOval(
          child: artistImg != null
              ? Image.network(
                  artistImg,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => CircleAvatar(
                    radius: 22,
                    backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    child: const Icon(Icons.person, size: 22),
                  ),
                )
              : CircleAvatar(
                  radius: 22,
                  backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                  child: const Icon(Icons.person, size: 22),
                ),
        ),
        title: Text(result.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: const Text('Artist', style: TextStyle(color: Colors.grey, fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
        onTap: () {
          _addRecentSearch(RecentSearchItem(
            id: result.id,
            title: result.title,
            subtitle: 'Artist',
            kind: 'artist',
            imageUrl: artistImg,
          ));
          Navigator.of(context).pushNamed(
            CatalogArtistScreen.routeName,
            arguments: CatalogArtistScreenArguments.fromSearchResult(result),
          );
        },
      );
    }

    if (result.kind == 'album') {
      final info = [
        if (result.displayArtist != null && result.displayArtist!.isNotEmpty) result.displayArtist!,
        if (result.primaryType != null) result.primaryType,
        if (result.firstDate != null && result.firstDate!.length >= 4)
          result.firstDate!.substring(0, 4)
        else if (result.firstDate != null)
          result.firstDate!,
      ].join(' • ');

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: result.imageUrl != null && result.imageUrl!.isNotEmpty
              ? Image.network(
                  result.imageUrl!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 44,
                    height: 44,
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    child: Icon(Icons.album_rounded, size: 24, color: isDark ? Colors.white38 : Colors.black38),
                  ),
                )
              : Container(
                  width: 44,
                  height: 44,
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                  child: Icon(Icons.album_rounded, size: 24, color: isDark ? Colors.white38 : Colors.black38),
                ),
        ),
        title: Text(result.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(info, style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
        onTap: () {
          _addRecentSearch(RecentSearchItem(
            id: result.id,
            title: result.title,
            subtitle: result.displayArtist ?? 'Album',
            kind: 'album',
          ));
          Navigator.of(context).pushNamed(
            CatalogAlbumScreen.routeName,
            arguments: CatalogAlbumScreenArguments.fromSearchResult(result),
          );
        },
      );
    }

    final subtitleParts = [
      if (result.displayArtist != null && result.displayArtist!.isNotEmpty) result.displayArtist!,
      if (result.formattedDuration.isNotEmpty) result.formattedDuration,
    ];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: result.imageUrl != null && result.imageUrl!.isNotEmpty
            ? Image.network(
                result.imageUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 44,
                  height: 44,
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                  child: Icon(Icons.music_note_rounded, size: 22, color: isDark ? Colors.white38 : Colors.black38),
                ),
              )
            : Container(
                width: 44,
                height: 44,
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                child: Icon(Icons.music_note_rounded, size: 22, color: isDark ? Colors.white38 : Colors.black38),
              ),
      ),
      title: Text(result.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(
        subtitleParts.join(' • '),
        style: const TextStyle(color: Colors.grey, fontSize: 12.5),
      ),
      trailing: const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
      onTap: () => CatalogPlaybackHelper.handleTrackTap(
        context,
        title: result.title,
        availability: result.availability,
      ),
    );
  }
}
