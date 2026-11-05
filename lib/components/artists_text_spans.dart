import 'package:finamp/services/artist_resolution_helper.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/jellyfin_models.dart';
import '../../services/jellyfin_api_helper.dart';
import '../services/downloads_service.dart';

List<TextSpan> buildArtistsTextSpans(BaseItemDto item, Color? textColour, BuildContext context, bool popRoutes) {
  final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
  final isarDownloader = GetIt.instance<DownloadsService>();
  List<TextSpan> separatedArtistTextSpans = [];

  List<NameIdPair>? artists = item.type == "MusicAlbum" ? item.albumArtists : item.artistItems;

  if (artists?.isEmpty ?? true) {
    separatedArtistTextSpans = [
      TextSpan(
        text: "Unknown Artist",
        style: TextStyle(color: textColour),
      ),
    ];
  } else {
    artists
        ?.map(
          (e) => TextSpan(
            text: e.name,
            style: TextStyle(color: textColour),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                Future<BaseItemDto>? artistFuture = FinampSettingsHelper.finampSettings.isOffline
                    ? isarDownloader.getCollectionInfo(id: e.id).then((value) => value!.baseItem!)
                    : jellyfinApiHelper.getItemById(e.id);

                artistFuture.then((artist) {
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
          separatedArtistTextSpans.add(
            TextSpan(
              text: ", ",
              style: TextStyle(color: textColour),
            ),
          );
        });
    separatedArtistTextSpans.removeLast();
  }
  return separatedArtistTextSpans;
}
