import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../components/MusicScreen/sort_and_filter_row.dart';
import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import 'downloads_screen.dart';
import 'liked_songs_screen.dart';
import 'music_screen.dart';

class LibraryScreenContent extends ConsumerWidget {
  const LibraryScreenContent({super.key});

  static const Color appleAccentColor = Color(0xFFFA2D48);

  void _openTab(BuildContext context, ContentType contentType) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MusicScreen(
          singleTabConfig: HomeScreenSectionConfiguration(
            base: TabsHomeSection(
              libraryId: currentLibraryPlaceholder,
              contentType: contentType,
            ),
            sortConfig: SortAndFilterController.trackSettings(contentType).resolveConfig(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final categories = [
      {
        'title': 'Playlists',
        'icon': TablerIcons.playlist,
        'action': () => _openTab(context, ContentType.playlists),
      },
      {
        'title': 'Artists',
        'icon': TablerIcons.microphone_2,
        'action': () => _openTab(context, ContentType.genericArtists),
      },
      {
        'title': 'Albums',
        'icon': TablerIcons.disc,
        'action': () => _openTab(context, ContentType.albums),
      },
      {
        'title': 'Songs',
        'icon': TablerIcons.music,
        'action': () => _openTab(context, ContentType.tracks),
      },
      {
        'title': 'Liked Songs',
        'icon': TablerIcons.heart,
        'action': () => Navigator.of(context).pushNamed(LikedSongsScreen.routeName),
      },
      {
        'title': 'Downloaded',
        'icon': TablerIcons.download,
        'action': () => Navigator.of(context).pushNamed(DownloadsScreen.routeName),
      },
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(
              'Library',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            separatorBuilder: (_, _) => Divider(
              indent: 52,
              height: 1,
              color: isDark ? Colors.white12 : Colors.black12,
            ),
            itemBuilder: (context, index) {
              final cat = categories[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: Icon(
                  cat['icon'] as IconData,
                  color: appleAccentColor,
                  size: 26,
                ),
                title: Text(
                  cat['title'] as String,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                  size: 20,
                ),
                onTap: cat['action'] as VoidCallback,
              );
            },
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 150)),
      ],
    );
  }
}
