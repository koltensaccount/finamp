import 'package:finamp/services/artist_resolution_helper.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/jellyfin_models.dart';
import '../../services/jellyfin_api_helper.dart';

List<TextSpan> getArtistsTextSpans(BaseItemDto item, BuildContext context, bool popRoutes) {
  final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
  List<TextSpan> separatedArtistTextSpans = [];

  List<NameIdPair>? artists = item.type == "MusicAlbum" ? item.albumArtists : item.artistItems;

  if (artists?.isEmpty ?? true) {
    separatedArtistTextSpans = [TextSpan(text: "Unknown Artist", style: Theme.of(context).textTheme.bodyMedium)];
  } else {
    artists
        ?.map(
          (e) => TextSpan(
            text: e.name,
            style: Theme.of(context).textTheme.bodyMedium,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                if (FinampSettingsHelper.finampSettings.isOffline) {
                  ArtistResolutionHelper.navigateToArtist(
                    context,
                    jellyfinId: e.id.raw,
                    artistName: e.name,
                    popFirst: popRoutes,
                  );
                  return;
                }

                jellyfinApiHelper.getItemById(e.id).then((artist) {
                  if (context.mounted) {
                    ArtistResolutionHelper.navigateToArtist(
                      context,
                      artistItem: artist,
                      jellyfinId: e.id.raw,
                      artistName: e.name,
                      popFirst: popRoutes,
                    );
                  }
                });
              },
          ),
        )
        .forEach((artistTextSpan) {
          separatedArtistTextSpans.add(artistTextSpan);
          separatedArtistTextSpans.add(TextSpan(text: ", ", style: Theme.of(context).textTheme.bodyMedium));
        });
    separatedArtistTextSpans.removeLast();
  }
  return separatedArtistTextSpans;
}
