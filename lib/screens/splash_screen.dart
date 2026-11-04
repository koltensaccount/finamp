import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:finamp/screens/login_screen.dart';
import 'package:finamp/screens/music_screen.dart';
import 'package:finamp/screens/view_selector.dart';
import 'package:finamp/screens/catalog_artist_screen.dart';
import 'package:finamp/screens/catalog_album_screen.dart';
import 'package:finamp/screens/catalog_search_screen.dart';
import 'package:finamp/screens/liked_songs_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const routeName = "/";

  @override
  Widget build(BuildContext context) {
    const debugRoute = String.fromEnvironment('DEBUG_ROUTE', defaultValue: '');
    if (debugRoute == 'artist') {
      return const CatalogArtistScreen();
    }
    if (debugRoute == 'search') {
      return const CatalogSearchScreen();
    }
    if (debugRoute == 'liked-songs') {
      return const LikedSongsScreen();
    }
    if (debugRoute == 'album') {
      return const CatalogAlbumScreen();
    }

    final finampUserHelper = GetIt.instance<FinampUserHelper>();

    if (finampUserHelper.currentUser == null) {
      return const LoginScreen();
    } else if (finampUserHelper.currentUser!.currentView == null) {
      return const ViewSelector();
    } else {
      return const MusicScreen();
    }
  }
}
