import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/jellyfin_models.dart';
import '../../services/jellyfin_api_helper.dart';
import '../screens/artist_screen.dart';

List<TextSpan> getArtistsTextSpans(BaseItemDto item, BuildContext context, bool popRoutes) {
  final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
  List<TextSpan> separatedArtistTextSpans = [];

  List<NameIdPair>? artists = item.type == "MusicAlbum" ? item.albumArtists : item.artistItems;

  if (artists?.isEmpty ?? true) {
    separatedArtistTextSpans = [TextSpan(text: "Unknown Artist", style: Theme.of(context).textTheme.bodyMedium)];
  } else {
    final collabRegex = RegExp(r'(\s+(?:feat\.?|ft\.?|featuring)\s+|\s+&\s+)', caseSensitive: false);

    for (int i = 0; i < artists!.length; i++) {
      final e = artists[i];
      final artistName = e.name ?? '';
      final matches = collabRegex.allMatches(artistName).toList();

      if (matches.isNotEmpty) {
        int lastIndex = 0;
        for (final match in matches) {
          final prefix = artistName.substring(lastIndex, match.start).trim();
          final delim = match.group(0)!;
          if (prefix.isNotEmpty) {
            separatedArtistTextSpans.add(
              TextSpan(
                text: prefix,
                style: Theme.of(context).textTheme.bodyMedium,
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    if (FinampSettingsHelper.finampSettings.isOffline) return;
                    if (e.id != null) {
                      jellyfinApiHelper.getItemById(e.id).then(
                            (artist) => popRoutes
                                ? Navigator.of(context).popAndPushNamed(ArtistScreen.routeName, arguments: artist)
                                : Navigator.of(context).pushNamed(ArtistScreen.routeName, arguments: artist),
                          );
                    } else {
                      final fallback = BaseItemDto(name: prefix, type: "MusicArtist");
                      popRoutes
                          ? Navigator.of(context).popAndPushNamed(ArtistScreen.routeName, arguments: fallback)
                          : Navigator.of(context).pushNamed(ArtistScreen.routeName, arguments: fallback);
                    }
                  },
              ),
            );
          }
          separatedArtistTextSpans.add(TextSpan(text: delim, style: Theme.of(context).textTheme.bodyMedium));
          lastIndex = match.end;
        }
        final suffix = artistName.substring(lastIndex).trim();
        if (suffix.isNotEmpty) {
          separatedArtistTextSpans.add(
            TextSpan(
              text: suffix,
              style: Theme.of(context).textTheme.bodyMedium,
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  if (FinampSettingsHelper.finampSettings.isOffline) return;
                  final fallback = BaseItemDto(name: suffix, type: "MusicArtist");
                  popRoutes
                      ? Navigator.of(context).popAndPushNamed(ArtistScreen.routeName, arguments: fallback)
                      : Navigator.of(context).pushNamed(ArtistScreen.routeName, arguments: fallback);
                },
            ),
          );
        }
      } else {
        separatedArtistTextSpans.add(
          TextSpan(
            text: e.name,
            style: Theme.of(context).textTheme.bodyMedium,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                if (FinampSettingsHelper.finampSettings.isOffline) return;
                jellyfinApiHelper.getItemById(e.id).then(
                      (artist) => popRoutes
                          ? Navigator.of(context).popAndPushNamed(ArtistScreen.routeName, arguments: artist)
                          : Navigator.of(context).pushNamed(ArtistScreen.routeName, arguments: artist),
                    );
              },
          ),
        );
      }

      if (i < artists.length - 1) {
        separatedArtistTextSpans.add(TextSpan(text: ", ", style: Theme.of(context).textTheme.bodyMedium));
      }
    }
  }
  return separatedArtistTextSpans;
}
