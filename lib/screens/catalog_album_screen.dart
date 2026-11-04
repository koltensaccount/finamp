import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/now_playing_bar.dart';
import '../models/catalog_models.dart';
import '../services/catalog_api_client.dart';
import '../services/catalog_playback_helper.dart';
import 'catalog_artist_screen.dart';

class CatalogAlbumScreenArguments {
  const CatalogAlbumScreenArguments({
    required this.releaseGroupMbid,
    this.initialTitle,
    this.initialArtist,
    this.initialImageUrl,
    this.initialYear,
  });

  factory CatalogAlbumScreenArguments.fromSearchResult(CatalogSearchResult result) =>
      CatalogAlbumScreenArguments(
        releaseGroupMbid: result.id,
        initialTitle: result.title,
        initialArtist: result.displayArtist,
        initialImageUrl: result.imageUrl,
        initialYear: result.firstDate,
      );

  final String releaseGroupMbid;
  final String? initialTitle;
  final String? initialArtist;
  final String? initialImageUrl;
  final String? initialYear;
}

class CatalogAlbumScreen extends StatefulWidget {
  const CatalogAlbumScreen({super.key});
  static const routeName = '/catalog-album';

  @override
  State<CatalogAlbumScreen> createState() => _CatalogAlbumScreenState();
}

class _CatalogAlbumScreenState extends State<CatalogAlbumScreen> {
  CatalogAlbumScreenArguments? _args;
  CatalogAlbumGroup? _albumGroup;
  CatalogRelease? _activeRelease;
  String? _error;
  bool _loading = true;
  bool _requesting = false;

  static const Color appleAccentColor = Color(0xFFFA2D48);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalArgs = ModalRoute.of(context)?.settings.arguments;
    if (modalArgs is CatalogAlbumScreenArguments && _args == null) {
      _args = modalArgs;
      _loadAlbum();
    } else if (_args == null) {
      const debugMbid = String.fromEnvironment(
        'DEBUG_ALBUM_MBID',
        defaultValue: 'dc396430-1e1c-4f0b-8b05-d69603d7fb12', // Charli
      );
      if (debugMbid.isNotEmpty) {
        _args = const CatalogAlbumScreenArguments(
          releaseGroupMbid: debugMbid,
          initialTitle: 'Charli',
          initialArtist: 'Charli XCX',
        );
        _loadAlbum();
      }
    }
  }

  Future<void> _loadAlbum() async {
    final args = _args;
    if (args == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = GetIt.instance<CatalogApiClient>();
      final group = await client.getAlbumGroup(args.releaseGroupMbid);
      _albumGroup = group;
      if (group.editions.isNotEmpty) {
        final preferred = group.editions.firstWhere(
          (e) => e.isFullyOwned,
          orElse: () => group.editions.firstWhere(
            (e) => e.isPartiallyOwned,
            orElse: () => group.editions.first,
          ),
        );
        _activeRelease = await client.getRelease(preferred.id);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestAlbum() async {
    final releaseId = _activeRelease?.id;
    if (releaseId == null) return;

    setState(() => _requesting = true);
    try {
      final client = GetIt.instance<CatalogApiClient>();
      await client.requestAlbum(releaseId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1C1C1E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: appleAccentColor, size: 20),
                SizedBox(width: 10),
                Text('Added to library download queue', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: CircleAvatar(
              radius: 18,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.chevron_left, color: isDark ? Colors.white : Colors.black87, size: 26),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  (_activeRelease?.isFullyOwned ?? false) ? Icons.check : Icons.add,
                  color: appleAccentColor,
                  size: 22,
                ),
                onPressed: _requesting ? null : _requestAlbum,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_horiz, color: isDark ? Colors.white : Colors.black87, size: 20),
                onPressed: () {},
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const NowPlayingBar(),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Could not load album', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(backgroundColor: appleAccentColor),
                onPressed: _loadAlbum,
              ),
            ],
          ),
        ),
      );
    }

    final release = _activeRelease;
    if (release == null) {
      return const Center(child: Text('No editions found for this album.'));
    }

    final imageUrl = release.imageUrl ?? _albumGroup?.imageUrl ?? _args?.initialImageUrl;
    final displayArtist = release.displayArtist ?? _args?.initialArtist ?? 'Unknown Artist';
    final releaseYear = _albumGroup?.firstDate != null && _albumGroup!.firstDate!.length >= 4
        ? _albumGroup!.firstDate!.substring(0, 4)
        : (_args?.initialYear ?? '');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        // Apple Music Hero Album Artwork
        Center(
          child: Container(
            width: 210,
            height: 210,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      width: 210,
                      height: 210,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        child: const Icon(Icons.album_rounded, size: 80, color: Colors.grey),
                      ),
                    )
                  : Container(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                      child: const Icon(Icons.album_rounded, size: 80, color: Colors.grey),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Album Title
        Text(
          release.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        // Artist Name (Tappable with Apple red accent)
        GestureDetector(
          onTap: () {
            if (release.artistCredits.isNotEmpty) {
              Navigator.of(context).pushNamed(
                CatalogArtistScreen.routeName,
                arguments: CatalogArtistScreenArguments(
                  artistMbid: release.artistCredits.first.artistId,
                  initialName: release.artistCredits.first.name,
                ),
              );
            }
          },
          child: Text(
            displayArtist,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: appleAccentColor,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Metadata: Album • Year • Lossless
        Text(
          [
            if (_albumGroup?.primaryType != null) _albumGroup!.primaryType else 'Album',
            if (releaseYear.isNotEmpty) releaseYear,
            'Lossless',
          ].join(' • '),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        // Dual Apple Music Play & Shuffle Capsule Buttons
        Row(
          children: [
            Expanded(
              child: _buildAppleActionButton(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                isDark: isDark,
                onTap: () {
                  final firstPlayable = release.tracks.firstWhere(
                    (t) => t.availability?.canPlay ?? false,
                    orElse: () => release.tracks.first,
                  );
                  CatalogPlaybackHelper.handleTrackTap(
                    context,
                    title: firstPlayable.title,
                    availability: firstPlayable.availability,
                    albumEditionId: release.id,
                    onRequestAlbum: _requestAlbum,
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAppleActionButton(
                icon: TablerIcons.arrows_shuffle,
                label: 'Shuffle',
                isDark: isDark,
                onTap: () {
                  final playableTracks = release.tracks.where((t) => t.availability?.canPlay ?? false).toList();
                  if (playableTracks.isNotEmpty) {
                    final randomTrack = playableTracks[Random().nextInt(playableTracks.length)];
                    CatalogPlaybackHelper.handleTrackTap(
                      context,
                      title: randomTrack.title,
                      availability: randomTrack.availability,
                      albumEditionId: release.id,
                      onRequestAlbum: _requestAlbum,
                    );
                  } else {
                    _requestAlbum();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Track List
        ...release.tracks.map((track) => _buildTrackTile(track, release.id, isDark)),
      ],
    );
  }

  Widget _buildAppleActionButton({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: appleAccentColor, size: 24),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: appleAccentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackTile(CatalogTrack track, String releaseId, bool isDark) {
    final availability = track.availability;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          leading: SizedBox(
            width: 28,
            child: Text(
              '${track.position}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: -0.2,
            ),
          ),
          subtitle: track.displayArtist != null && track.displayArtist!.isNotEmpty
              ? Text(
                  track.displayArtist!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track.formattedDuration.isNotEmpty)
                Text(
                  track.formattedDuration,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
            ],
          ),
          onTap: () => CatalogPlaybackHelper.handleTrackTap(
            context,
            title: track.title,
            availability: availability,
            albumEditionId: releaseId,
            onRequestAlbum: _requestAlbum,
          ),
        ),
        Divider(
          height: 1,
          indent: 48,
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      ],
    );
  }
}
