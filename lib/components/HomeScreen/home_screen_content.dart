import 'dart:math';
import 'dart:ui';

import 'package:balanced_text/balanced_text.dart';
import 'package:finamp/components/AlbumScreen/download_button.dart';
import 'package:finamp/components/Buttons/cta_small.dart';
import 'package:finamp/components/HomeScreen/home_screen_quick_action_button.dart';
import 'package:finamp/components/HomeScreen/quick_action_editor.dart';
import 'package:finamp/components/MusicScreen/item_card.dart';
import 'package:finamp/components/MusicScreen/item_wrapper.dart';
import 'package:finamp/components/MusicScreen/music_screen_tab_view.dart';
import 'package:finamp/components/finamp_section_header.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/menus/components/icon_button_with_semantics.dart';
import 'package:finamp/menus/home_section_menu.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/music_models.dart';
import 'package:finamp/screens/catalog_artist_screen.dart';
import 'package:finamp/screens/home_screen_settings_screen.dart';
import 'package:finamp/screens/liked_songs_screen.dart';
import 'package:finamp/services/audio_service_helper.dart';
import 'package:finamp/screens/music_screen.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/music_screen_provider.dart';
import 'package:finamp/services/queue_service.dart';
import 'package:finamp/services/quick_actions_service.dart';
import 'package:finamp/utils/platform_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:logging/logging.dart';

import '../../extensions/localizations.dart';
import '../../services/finamp_user_helper.dart';
import '../../services/liked_songs_service.dart';
import '../../services/music_providers.dart';

final _homeScreenLogger = Logger("HomeScreen");

class HomeScreenContent extends ConsumerStatefulWidget {
  const HomeScreenContent({super.key, this.refresh});

  final MusicRefreshCallback? refresh;

  @override
  ConsumerState<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends ConsumerState<HomeScreenContent>
    with AutomaticKeepAliveClientMixin<HomeScreenContent> {
  // tabs on the music screen should be kept alive
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (GetIt.instance.isRegistered<LikedSongsService>()) {
        GetIt.instance<LikedSongsService>().syncWithJellyfin();
      }
    });
  }

  void _refresh() async {
    for (var section in ref.watch(finampSettingsProvider.homeScreenConfiguration).sections) {
      final displayable = await ref.watch(resolveSectionProvider(section).future);
      ref.read(pagedContentProvider(displayable).notifier).refresh();
    }
    ref.invalidate(UserInfoProviders.userInfoProvider);
    if (GetIt.instance.isRegistered<LikedSongsService>()) {
      await ref.read(likedSongsProvider).syncWithJellyfin(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    widget.refresh?.callback = _refresh;
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildTopPicksSection(context),
          ),
          SliverToBoxAdapter(
            child: _buildFeaturedArtistsSection(context),
          ),
          if (ref.watch(finampSettingsProvider.homeScreenConfiguration).actions.isNotEmpty)
            SliverPadding(padding: const EdgeInsets.only(top: 10.0)),
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final double maxWidth = isDesktop ? 800.0 : 600.0;
              final viewPadding = MediaQuery.paddingOf(context);
              final usableWidth = constraints.crossAxisExtent - viewPadding.left - viewPadding.right;
              // center action buttons
              // Mandatory padding should be enough to clear scrollbar
              final horizontalPadding = max(0, (usableWidth - maxWidth) / 2) + 14.0;
              final configuredQuickActions = ref.watch(finampSettingsProvider.homeScreenConfiguration).actions;
              return SliverPadding(
                padding: EdgeInsets.only(
                  left: horizontalPadding + viewPadding.left,
                  right: horizontalPadding + viewPadding.right,
                ),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: isDesktop ? 4.0 : 0,
                    runSpacing: 8,
                    direction: Axis.horizontal,
                    alignment: WrapAlignment.spaceBetween,
                    runAlignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: configuredQuickActions.indexed.map((indexedAction) {
                      final (index, action) = indexedAction;
                      //!!! custom adaptive grid
                      // calculate button width based on available space and number of actions per row
                      final double quickActionsWidth = min(
                        usableWidth - horizontalPadding - horizontalPadding,
                        maxWidth,
                      );
                      double verticalButtonWidth = (quickActionsWidth / 3) - 2 * (5.0);
                      double horizontalButtonWidth = (quickActionsWidth / 2) - 1 * (8.0);
                      double singleButtonWidth = quickActionsWidth;
                      double buttonWidth;
                      // always fill each row completely
                      if (configuredQuickActions.length == 1) {
                        buttonWidth = singleButtonWidth;
                      } else if (configuredQuickActions.length % 3 == 0) {
                        buttonWidth = verticalButtonWidth;
                      } else if (configuredQuickActions.length == 4) {
                        buttonWidth = horizontalButtonWidth;
                      } else if ((configuredQuickActions.length % 3 == 1 &&
                              configuredQuickActions.length - index <= 4) ||
                          (configuredQuickActions.length % 3 == 2 && configuredQuickActions.length - index < 3)) {
                        buttonWidth = horizontalButtonWidth;
                      } else {
                        buttonWidth = verticalButtonWidth;
                      }
                      //TODO possibly use CustomMultiChildLayout instead of Wrap to allow actions to stretch in height to fill each row, in case of multi-line actions
                      return HomeScreenQuickActionButton(
                        width: buttonWidth,
                        text: action.getTitle(context.l10n),
                        label: action.action.getDescription(context),
                        icon: action.action.getIcon(),
                        vertical: buttonWidth == verticalButtonWidth,
                        onPressed: () async => QuickActionsService.handleAction(action, context),
                        onSecondaryPressed: () => editQuickAction(context, index),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(top: 4.0)),
          SliverMainAxisGroup(
            slivers: ref
                .watch(finampSettingsProvider.homeScreenConfiguration)
                .sections
                .map((sectionInfo) => HomeScreenSection(sectionInfo: sectionInfo))
                .toList(),
          ),
          const SliverPadding(padding: EdgeInsets.only(top: 30)),
          ...[
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 200),
                  child: BalancedText(
                    context.l10n.lookingForSomethingElse,
                    textAlign: TextAlign.center,
                    style: TextTheme.of(context).bodySmall,
                  ),
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(top: 12)),
            SliverToBoxAdapter(
              child: Center(
                child: CTASmall(
                  text: context.l10n.customizeHomeScreen,
                  icon: TablerIcons.settings,
                  onPressed: () => Navigator.pushNamed(context, HomeScreenSettingsScreen.routeName),
                ),
              ),
            ),
          ],
          /*const SliverPadding(padding: EdgeInsets.only(top: 60)),
          ...[
            // monochrome icon
            SliverToBoxAdapter(
              child: FinampIcon(56, 56, overrideColor: TextTheme.of(context).bodySmall?.color?.withOpacity(0.4)),
            ),
            const SliverPadding(padding: EdgeInsets.only(top: 16)),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 200),
                  child: BalancedText(
                    context.l10n.builtWithByTheFinampContributors,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: TextTheme.of(context).bodySmall?.color?.withOpacity(0.6)),
                  ),
                ),
              ),
            ),
          ],*/
          SliverSafeArea(top: false, sliver: SliverPadding(padding: const EdgeInsets.only(bottom: 120.0))),
        ],
      ),
    );
  }

  Widget _buildTopPicksSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text(
            'Top Picks for You',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
          ),
        ),
        SizedBox(
          height: 308,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildLikedSongsCard(context),
              const SizedBox(width: 14),
              _buildEssentialsCard(context),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildFeaturedArtistsSection(BuildContext context) {
    final featured = [
      {
        'name': 'The Beatles',
        'mbid': 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d',
        'imageUrl': 'https://e-cdns-images.dzcdn.net/images/artist/16925ed8f96eb621ecd56c2c8ba3da6e/500x500-000000-80-0-0.jpg',
      },
      {
        'name': 'Geese',
        'mbid': 'e0c97a4d-c392-41a9-a374-57af3e3eeab3',
        'imageUrl': 'https://e-cdns-images.dzcdn.net/images/artist/f21589416d59cc1b172748ad72e8a3e9/500x500-000000-80-0-0.jpg',
      },
      {
        'name': 'Radiohead',
        'mbid': 'a74b1b7f-71a5-4011-9441-d0b5e4122711',
        'imageUrl': 'https://cdn-images.dzcdn.net/images/artist/0d58cfbc90f2e776608bcdc0c45a4711/500x500-000000-80-0-0.jpg',
      },
      {
        'name': 'Pink Floyd',
        'mbid': '83d91898-7763-47d7-b03b-b92132375c47',
        'imageUrl': 'https://cdn-images.dzcdn.net/images/artist/0aaad29662a33e33350f999d6b26e517/250x250-000000-80-0-0.jpg',
      },
      {
        'name': 'Black Country, New Road',
        'mbid': 'f72671c6-11f2-452f-87a3-4889c6569106',
        'imageUrl': 'https://cdn-images.dzcdn.net/images/artist/5d8bf8877cefa207508196c2e61a2ad8/250x250-000000-80-0-0.jpg',
      },
      {
        'name': 'Led Zeppelin',
        'mbid': '678d88b2-87b0-403b-b63d-5da7465aecc3',
        'imageUrl': 'https://cdn-images.dzcdn.net/images/artist/2cf138b96a63da677ac6fb79846607c8/500x500-000000-80-0-0.jpg',
      },
      {
        'name': 'The Rolling Stones',
        'mbid': 'b071f9f8-14b0-4217-8e97-eb41da73f59e',
        'imageUrl': 'https://cdn-images.dzcdn.net/images/artist/cac467bef484959b4ad503c4cb7ef83d/500x500-000000-80-0-0.jpg',
      },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Text(
                'Featured Artists',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 22, color: Colors.grey),
            ],
          ),
        ),
        SizedBox(
          height: 135,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: featured.length,
            separatorBuilder: (_, _) => const SizedBox(width: 18),
            itemBuilder: (context, i) {
              final a = featured[i];
              return InkWell(
                borderRadius: BorderRadius.circular(44),
                onTap: () => Navigator.of(context).pushNamed(
                  CatalogArtistScreen.routeName,
                  arguments: CatalogArtistScreenArguments(artistMbid: a['mbid']!, initialName: a['name']!),
                ),
                child: SizedBox(
                  width: 82,
                  child: Column(
                    children: [
                      ClipOval(
                        child: Image.network(
                          a['imageUrl']!,
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => CircleAvatar(
                            radius: 38,
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(TablerIcons.user, size: 36),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        a['name']!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Artist',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildLikedSongsCard(BuildContext context) {
    final likedSongs = ref.watch(likedSongsProvider);
    final count = likedSongs.count;
    final subtitle = count > 0
        ? '$count favorite songs in Jellyfin'
        : 'All your favorite tracks in one place';

    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(LikedSongsScreen.routeName),
      child: Container(
        width: 236,
        decoration: BoxDecoration(
          color: const Color(0xFF222226),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 156,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF4A148C),
                    Color(0xFF1A237E),
                    Color(0xFF1DB954),
                  ],
                ),
              ),
              child: const Center(
                child: Icon(Icons.favorite, size: 60, color: Colors.white),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Made By You',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Liked Songs',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.25,
                color: Color(0xFF98989F),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEssentialsCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        GetIt.instance<AudioServiceHelper>().playRandomItem();
      },
      child: Container(
        width: 236,
        decoration: BoxDecoration(
          color: const Color(0xFF222226),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 156,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0D47A1),
                    Color(0xFF880E4F),
                    Color(0xFFE65100),
                  ],
                ),
              ),
              child: const Center(
                child: Icon(TablerIcons.flame, size: 60, color: Colors.white),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Made for You',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Heavy Rotation',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Instant mix from your music library',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.25,
                color: Color(0xFF98989F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreenSection extends ConsumerWidget {
  const HomeScreenSection({super.key, required this.sectionInfo});

  final HomeScreenSectionConfiguration sectionInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionDisplayable = ref.watch(resolveSectionProvider(sectionInfo)).value;

    final viewPadding = MediaQuery.paddingOf(context);
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 20.0),
      sliver: FinampSectionHeader(
        sticky: false,
        key: Key(sectionInfo.toString()),
        title: sectionInfo.getTitle(context.l10n),
        label: context.l10n.showAll,
        titleTrailingIcon: TablerIcons.chevron_right,
        headerPadding: EdgeInsets.only(left: viewPadding.left + 14.0, right: viewPadding.right + 20.0),
        contentPadding: EdgeInsets.zero,
        actions: [
          if (sectionDisplayable is FinampPlayable) ...[
            IconButtonWithSemantics(
              onPressed: () async {
                final queueService = GetIt.instance<QueueService>();
                final playable = sectionDisplayable as FinampPlayable;
                await queueService.startSlicePlayback(
                  await ref.read(getPlayableSliceProvider(item: playable, startingOffset: 0).future),
                );
              },
              label: AppLocalizations.of(context)!.playButtonLabel,
              icon: TablerIcons.player_play,
            ),
            IconButtonWithSemantics(
              onPressed: () async {
                final queueService = GetIt.instance<QueueService>();
                final playable = sectionDisplayable as FinampPlayable;
                // TODO better shuffling?  need to think about shuffle all versus shuffle first
                await queueService.startSlicePlayback(
                  (await ref.read(getPlayableSliceProvider(item: playable, startingOffset: 0).future)).shuffle(),
                );
              },
              label: context.l10n.shuffleButtonLabel,
              icon: TablerIcons.arrows_shuffle,
            ),
          ],
          // bind function result to downloadInfo and proceed if not null
          if (getHomeDownloadInfo(ref, context.l10n, sectionInfo, sectionDisplayable?.maybeItem) case var downloadInfo?)
            DownloadButton(
              item: downloadInfo.stub,
              allowServerDelete: false,
              warningMessage: downloadInfo.warning,
              downloadOnly: true,
            ),
        ],
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<MusicScreen>(builder: (context) => MusicScreen(singleTabConfig: sectionInfo)));
        },
        onSecondaryTap: () => showModalHomeSectionMenu(context: context, section: sectionInfo),
        onDismiss: null,
        sectionContentSliver: SliverToBoxAdapter(
          /* child: ShaderMask(
            shaderCallback: (bounds) {
              final leftFade = 9.0 / bounds.width;
              final rightFade = 20.0 / bounds.width;
              final leftOffset = 5.0 / bounds.width;
              final rightOffset = 20.0 / bounds.width;
              return LinearGradient(
                colors: [
                  Color.fromARGB(0, 255, 255, 255),
                  Color.fromARGB(0, 255, 255, 255),
                  Color.fromARGB(255, 255, 255, 255),
                  Color.fromARGB(255, 255, 255, 255),
                  Color.fromARGB(0, 255, 255, 255),
                  Color.fromARGB(0, 255, 255, 255),
                ],
                stops: [0.0, leftOffset, leftOffset + leftFade, 1.0 - rightOffset - rightFade, 1.0 - rightOffset, 1.0],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(bounds);
            },
            child: HomeScreenSectionContent(sectionInfo: sectionInfo),
          ) */
          child: HomeScreenSectionContent(sectionInfo: sectionInfo),
        ),
      ),
    );
  }
}

class HomeScreenSectionContent extends ConsumerWidget {
  const HomeScreenSectionContent({super.key, required this.sectionInfo, this.interactive = true});

  final HomeScreenSectionConfiguration sectionInfo;
  final bool interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool isOffline = ref.watch(finampSettingsProvider.isOffline);

    final asyncDisplayable = ref.watch(resolveSectionProvider(sectionInfo));
    if (asyncDisplayable.isLoading) {
      return _buildHorizontalSkeletonLoader(ref);
    } else if (asyncDisplayable.hasError) {
      _homeScreenLogger.severe("Error resolving library: ${asyncDisplayable.error}", asyncDisplayable.error);
      return Center(child: Text(context.l10n.failedToLoadSection, maxLines: 1));
    } else if (asyncDisplayable.value == null) {
      return isOffline
          ? Center(child: Text(context.l10n.sectionContentsNotDownloaded, maxLines: 1))
          : Center(child: Text(context.l10n.failedToLoadSectionMissingItem, maxLines: 1));
    }
    final displayable = asyncDisplayable.value!;
    if (displayable is UnavailableHomeSectionPlayable) {
      assert(isOffline);
      return Center(child: Text(context.l10n.notAvailableInOfflineMode, maxLines: 1));
    }

    final pageState = ref.watch(pagedContentProvider(displayable));
    final items = pageState.items;
    if (items == null) {
      if (pageState.isLoading) {
        return _buildHorizontalSkeletonLoader(ref);
      } else if (pageState.error != null) {
        _homeScreenLogger.severe("Error loading items: ${pageState.error}", pageState.error);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 30,
          children: [
            Text(context.l10n.errorLoadingItems, maxLines: 1),
            CTASmall(
              icon: TablerIcons.refresh,
              text: context.l10n.retry,
              onPressed: () {
                ref.read(pagedContentProvider(displayable).notifier).retry();
              },
            ),
          ],
        );
      } else {
        ref.read(pagedContentProvider(displayable).notifier).fetchHomeScreenItems();
        return _buildHorizontalSkeletonLoader(ref);
      }
    } else if (items.isEmpty) {
      return isOffline
          ? Center(child: Text(context.l10n.sectionContentsNotDownloaded, maxLines: 1))
          : Center(child: Text(context.l10n.noItemsAvailable, maxLines: 1));
    } else {
      return SizedBox(
        height: calculateItemCollectionCardHeight(
          ref: ref,
          sectionInfo: sectionInfo,
          itemType: null,
          forHomeScreen: true,
        ),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: ListView.separated(
            addAutomaticKeepAlives: true,
            scrollDirection: Axis.horizontal,
            itemCount: items.length + 2,
            itemBuilder: (context, rawIndex) {
              if (rawIndex == 0) {
                return SizedBox(width: 6.0); // initial padding, + separator
              } else if (rawIndex == items.length + 1) {
                // Add extra right padding if we have hit the end of list and there are no more items available
                if (items.length < homeScreenSectionItemLimit) {
                  return SizedBox(width: 40);
                } else {
                  return SizedBox(width: 0);
                }
              }
              final index = rawIndex - 1;
              switch (items[index]) {
                case FinampPlayableDto item:
                  return ItemWrapper(
                    key: ValueKey(item.item.id),
                    item: item.item,
                    isGrid: true,
                    forHomeScreen: true,
                    interactive: interactive,
                    source: displayable.source,
                  );
                case PlayableQueue queue:
                  return HomeScreenQueueTile(key: ValueKey(queue.queue.creation), info: queue.queue);
                case LatestQueues():
                case PrecalculatedPlayable():
                case UnavailableHomeSectionPlayable():
                case MusicScreenPlayable<FinampPlayableDto>():
                  throw UnsupportedError("Unexpected item ${items[index]} in home screen section");
              }
            },
            separatorBuilder: (context, index) => const SizedBox(width: 8, height: 1),
          ),
        ),
      );
    }
  }

  Widget _buildHorizontalSkeletonLoader(WidgetRef ref) {
    final skeletonCount = homeScreenSectionItemLimit;

    final skeletonBaseColor = Theme.brightnessOf(ref.context) == Brightness.light
        ? Colors.grey.shade300
        : Colors.grey.shade800;
    final skeletonOverlay = Theme.brightnessOf(ref.context) == Brightness.light
        ? Colors.grey.shade400
        : Colors.grey.shade700;
    return SizedBox(
      height: calculateItemCollectionCardHeight(
        ref: ref,
        sectionInfo: sectionInfo,
        itemType: null,
        forHomeScreen: true,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: skeletonCount + 1, // Show [skeletonCount] skeleton items
        itemBuilder: (context, index) {
          if (index == 0) {
            return SizedBox(width: 4.0); // initial padding, + separator
          }
          final double cardWidth;
          final double cardHeight;
          final bool showText;
          if (sectionInfo.base is QueuesHomeSection) {
            cardWidth = queuesHomeSectionWidth;
            cardHeight = queuesHomeSectionHeight;
            showText = false;
          } else {
            cardWidth = calculateItemCollectionCardWidth(ref, forHomeScreen: true).$1;
            cardHeight = calculateItemCollectionCardWidth(ref, forHomeScreen: true).$1;
            showText = true;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RepeatingAnimationBuilder<double>(
                animatable: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 700),
                repeatMode: RepeatMode.reverse,
                curve: Curves.easeInOut,
                builder: (BuildContext context, double opacity, Widget? child) {
                  return Stack(
                    children: [
                      Container(
                        width: cardWidth,
                        height: cardHeight,
                        decoration: BoxDecoration(color: skeletonBaseColor, borderRadius: BorderRadius.circular(8)),
                      ),
                      Opacity(
                        opacity: opacity * 0.7,
                        child: Container(
                          width: cardWidth,
                          height: cardHeight,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.center,
                              radius: 3.0,
                              colors: [skeletonOverlay, Colors.transparent],
                              stops: const [0.1, 1.0],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (showText) ...[
                SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Container(
                    width: cardWidth * Random().nextDouble().clamp(0.2, 0.9),
                    height: max(
                      calculateTextHeight(
                            style: TextTheme.of(context).bodySmall!,
                            lines: 1,
                            scaling: MediaQuery.textScalerOf(context),
                          ) -
                          4,
                      0,
                    ),
                    decoration: BoxDecoration(color: skeletonBaseColor, borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Container(
                    width: cardWidth * Random().nextDouble().clamp(0.2, 0.9),
                    height: max(
                      calculateTextHeight(
                            style: TextTheme.of(context).bodySmall!,
                            lines: 1,
                            scaling: MediaQuery.textScalerOf(context),
                          ) -
                          4,
                      0,
                    ),
                    decoration: BoxDecoration(color: skeletonBaseColor, borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          );
        },
        separatorBuilder: (context, index) => const SizedBox(width: 8),
      ),
    );
  }
}
