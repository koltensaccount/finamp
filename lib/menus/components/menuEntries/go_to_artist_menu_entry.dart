import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/menus/components/menuEntries/menu_entry.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/artist_resolution_helper.dart';
import 'package:finamp/services/downloads_service.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/jellyfin_api_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

class GoToArtistMenuEntry extends ConsumerWidget implements HideableMenuEntry {
  final BaseItemDto baseItem;

  const GoToArtistMenuEntry({super.key, required this.baseItem});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();

    final artistItem = ArtistResolutionHelper.resolveGenuineArtist(
      artistItems: baseItem.artistItems,
      albumArtists: baseItem.albumArtists,
    );
    final canGoToArtist = artistItem != null && artistItem.id.raw.isNotEmpty;

    return Visibility(
      visible: canGoToArtist,
      child: MenuEntry(
        icon: TablerIcons.user,
        title: AppLocalizations.of(context)!.goToArtist,
        onTap: () async {
          if (artistItem == null || artistItem.id.raw.isEmpty) {
            return;
          }
          final artistId = artistItem.id;
          late BaseItemDto artist;
          try {
            if (FinampSettingsHelper.finampSettings.isOffline) {
              final downloadsService = GetIt.instance<DownloadsService>();
              artist = (await downloadsService.getCollectionInfo(id: artistId))!.baseItem!;
            } else {
              artist = await jellyfinApiHelper.getItemById(artistId);
            }
          } catch (e) {
            GlobalSnackbar.error(e);
            return;
          }
          if (context.mounted) {
            Navigator.pop(context);
            await ArtistResolutionHelper.navigateToArtist(
              context,
              artistItem: artist,
              jellyfinId: artistId.raw,
              artistName: artistItem.name,
            );
          }
        },
      ),
    );
  }

  @override
  bool get isVisible {
    return ArtistResolutionHelper.resolveGenuineArtist(
      artistItems: baseItem.artistItems,
      albumArtists: baseItem.albumArtists,
    ) != null;
  }
}
