import 'dart:convert';

import 'package:finamp/models/catalog_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/screens/artist_screen.dart';
import 'package:finamp/screens/catalog_artist_screen.dart';
import 'package:finamp/services/artist_identity_service.dart';
import 'package:finamp/services/artist_resolution_helper.dart';
import 'package:finamp/services/catalog_api_client.dart';
import 'package:finamp/services/catalog_credential_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _TestNavigatorObserver extends NavigatorObserver {
  final List<String?> pushedRoutes = [];
  final List<dynamic> pushedArguments = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route.settings.name);
    pushedArguments.add(route.settings.arguments);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      pushedRoutes.add(newRoute.settings.name);
      pushedArguments.add(newRoute.settings.arguments);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

class _TestCredentials implements CatalogCredentialStore {
  @override
  Future<CatalogCredentials?> read() async => CatalogCredentials(
        endpoint: Uri.parse('http://127.0.0.1:8765'),
        token: 'test-token',
      );
  @override
  Future<void> save(CatalogCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}

class _MockHttpClient extends http.BaseClient {
  _MockHttpClient(this._handler);
  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ArtistIdentityService.resetForTesting();
    ArtistIdentityService.mockIsOffline = null;

    if (GetIt.instance.isRegistered<CatalogApiClient>()) {
      GetIt.instance.unregister<CatalogApiClient>();
    }
  });

  tearDown(() {
    ArtistIdentityService.mockIsOffline = null;
    if (GetIt.instance.isRegistered<CatalogApiClient>()) {
      GetIt.instance.unregister<CatalogApiClient>();
    }
  });

  group('Artist Navigation ID Resolution Regression Tests', () {
    test('resolves genuine artist when artistItems provides valid ID', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: [
          NameIdPair(id: BaseItemId('artist-uuid-5678'), name: 'Real Artist'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('artist-uuid-5678'));
      expect(target.name, equals('Real Artist'));
    });

    test('resolves genuine artist from albumArtists when artistItems is null', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: null,
        albumArtists: [
          NameIdPair(id: BaseItemId('album-artist-uuid-9999'), name: 'Album Artist'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('album-artist-uuid-9999'));
      expect(target.name, equals('Album Artist'));
    });

    test('falls back to albumArtists when artistItems is an empty list', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: [],
        albumArtists: [
          NameIdPair(id: BaseItemId('album-artist-uuid-1111'), name: 'Fallback Album Artist'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('album-artist-uuid-1111'));
      expect(target.name, equals('Fallback Album Artist'));
    });

    test('falls back to albumArtists when artistItems has only empty or whitespace IDs', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: [
          NameIdPair(id: BaseItemId('   '), name: 'Empty ID Artist'),
          NameIdPair(id: BaseItemId(''), name: 'Blank Artist'),
        ],
        albumArtists: [
          NameIdPair(id: BaseItemId('album-artist-uuid-2222'), name: 'Valid Album Artist'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('album-artist-uuid-2222'));
      expect(target.name, equals('Valid Album Artist'));
    });

    test('returns null when all artistItems and albumArtists IDs are empty', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: [
          NameIdPair(id: BaseItemId(''), name: 'Blank'),
        ],
        albumArtists: [
          NameIdPair(id: BaseItemId('  '), name: 'Whitespace'),
        ],
      );

      expect(target, isNull);
    });

    test('returns null when artistItems and albumArtists are both null or empty', () {
      expect(ArtistResolutionHelper.resolveGenuineArtist(), isNull);
      expect(
        ArtistResolutionHelper.resolveGenuineArtist(artistItems: [], albumArtists: []),
        isNull,
      );
    });

    test('resolveArtistNavigationTarget preserves track providerIds including MusicBrainzArtist', () {
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Bad Habit',
        type: 'Audio',
        artistItems: [
          NameIdPair(id: BaseItemId('artist-jf-id-349'), name: 'Steve Lacy'),
        ],
        providerIds: {
          'MusicBrainzArtist': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
          'MusicBrainzReleaseGroup': 'ab1c1fd8-f769-4d78-90bc-4677f8ad8c22',
        },
      );

      final target = ArtistResolutionHelper.resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'Steve Lacy',
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('artist-jf-id-349'));
      expect(target.name, equals('Steve Lacy'));
      expect(target.type, equals('MusicArtist'));
      expect(target.providerIds, isNotNull);
      expect(target.providerIds!['MusicBrainzArtist'], equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));
    });

    test('resolveArtistNavigationTarget falls back to albumArtists when artistItems is an empty list', () {
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Track Title',
        type: 'Audio',
        artistItems: [],
        albumArtists: [
          NameIdPair(id: BaseItemId('album-artist-uuid-3333'), name: 'Album Artist 3333'),
        ],
      );

      final target = ArtistResolutionHelper.resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'Album Artist 3333',
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('album-artist-uuid-3333'));
      expect(target.name, equals('Album Artist 3333'));
      expect(target.type, equals('MusicArtist'));
    });

    test('resolveArtistNavigationTarget refuses to fabricate artist target with track ID', () {
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Track Title',
        type: 'Audio',
        artists: ['String-Only Artist'],
        artistItems: [],
        albumArtists: [
          NameIdPair(id: BaseItemId('   '), name: 'Whitespace ID'),
        ],
      );

      final target = ArtistResolutionHelper.resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'String-Only Artist',
      );

      expect(target, isNull);
    });

    testWidgets('navigateToArtist resolves Steve Lacy embedded MBID from track without hardcoded artistMbid', (tester) async {
      final testObserver = _TestNavigatorObserver();
      final track = BaseItemDto(
        id: const BaseItemId('track-steve-lacy-1'),
        name: 'Bad Habit',
        type: 'Audio',
        artistItems: [
          NameIdPair(id: const BaseItemId('349ff016da8eade9fb2ba11ed655a2b9'), name: 'Steve Lacy'),
        ],
        providerIds: {
          'MusicBrainzArtist': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
          'MusicBrainzReleaseGroup': 'ab1c1fd8-f769-4d78-90bc-4677f8ad8c22',
        },
      );

      final artistTarget = ArtistResolutionHelper.resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'Steve Lacy',
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [testObserver],
          routes: {
            CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogArtistScreen')),
            ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
          },
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                // Notice: artistMbid is NOT passed (null), resolving purely from artistTarget
                ArtistResolutionHelper.navigateToArtist(
                  context,
                  artistItem: artistTarget,
                  artistName: 'Steve Lacy',
                );
              },
              child: const Text('Go Steve Lacy'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go Steve Lacy'));
      await tester.pumpAndSettle();

      expect(testObserver.pushedRoutes, contains(CatalogArtistScreen.routeName));
      expect(find.text('CatalogArtistScreen'), findsOneWidget);

      final args = testObserver.pushedArguments.whereType<CatalogArtistScreenArguments>().first;
      expect(args.artistMbid, equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));
      expect(args.artistMbid, isNot(equals('ca9766a0-1c30-43e6-a213-bac1334efc4a'))); // Not jazz saxophonist
    });

    testWidgets('navigateToArtist resolves from remote catalog for Library Artists item with no providerIds', (tester) async {
      final client = CatalogApiClient(
        credentials: _TestCredentials(),
        client: _MockHttpClient((request) async {
          expect(request.url.path, '/v1/artists/resolve');
          expect(request.url.queryParameters['item_id'], '349ff016da8eade9fb2ba11ed655a2b9');
          expect(request.url.queryParameters['name'], 'Steve Lacy');
          return http.Response(
            jsonEncode({
              'id': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
              'artist_id': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
              'name': 'Steve Lacy',
              'item_id': '349ff016da8eade9fb2ba11ed655a2b9',
              'confidence': 'exact',
            }),
            200,
          );
        }),
      );
      GetIt.instance.registerSingleton<CatalogApiClient>(client);

      final testObserver = _TestNavigatorObserver();
      // An artist item from Library -> Artists (has NO providerIds)
      final libraryArtistItem = BaseItemDto(
        id: const BaseItemId('349ff016da8eade9fb2ba11ed655a2b9'),
        name: 'Steve Lacy',
        type: 'MusicArtist',
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [testObserver],
          routes: {
            CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogArtistScreen')),
            ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
          },
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                ArtistResolutionHelper.navigateToArtist(
                  context,
                  artistItem: libraryArtistItem,
                );
              },
              child: const Text('Tap Library Artist'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Library Artist'));
      await tester.pumpAndSettle();

      expect(testObserver.pushedRoutes, contains(CatalogArtistScreen.routeName));
      expect(find.text('CatalogArtistScreen'), findsOneWidget);

      final args = testObserver.pushedArguments.whereType<CatalogArtistScreenArguments>().first;
      expect(args.artistMbid, equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));
    });

    testWidgets('navigateToArtist resolves Metro Boomin from remote catalog without hardcoded artistMbid', (tester) async {
      final client = CatalogApiClient(
        credentials: _TestCredentials(),
        client: _MockHttpClient((request) async {
          expect(request.url.path, '/v1/artists/resolve');
          expect(request.url.queryParameters['item_id'], '3abb1a64b01694b0df1411d4f6ee051e');
          expect(request.url.queryParameters['name'], 'Metro Boomin');
          return http.Response(
            jsonEncode({
              'id': '59db3d82-86ea-451f-881f-dffc8ec387c9',
              'artist_id': '59db3d82-86ea-451f-881f-dffc8ec387c9',
              'name': 'Metro Boomin',
              'item_id': '3abb1a64b01694b0df1411d4f6ee051e',
              'confidence': 'exact',
            }),
            200,
          );
        }),
      );
      GetIt.instance.registerSingleton<CatalogApiClient>(client);

      final testObserver = _TestNavigatorObserver();
      final metroArtistItem = BaseItemDto(
        id: const BaseItemId('3abb1a64b01694b0df1411d4f6ee051e'),
        name: 'Metro Boomin',
        type: 'MusicArtist',
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [testObserver],
          routes: {
            CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogArtistScreen')),
            ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
          },
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                ArtistResolutionHelper.navigateToArtist(
                  context,
                  artistItem: metroArtistItem,
                );
              },
              child: const Text('Tap Metro Boomin'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Metro Boomin'));
      await tester.pumpAndSettle();

      expect(testObserver.pushedRoutes, contains(CatalogArtistScreen.routeName));
      expect(find.text('CatalogArtistScreen'), findsOneWidget);

      final args = testObserver.pushedArguments.whereType<CatalogArtistScreenArguments>().first;
      expect(args.artistMbid, equals('59db3d82-86ea-451f-881f-dffc8ec387c9'));
    });

    testWidgets('navigateToArtist falls back to ArtistScreen when offline', (tester) async {
      ArtistIdentityService.mockIsOffline = true;
      try {
        final testObserver = _TestNavigatorObserver();
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [testObserver],
            routes: {
              CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogScreen')),
              ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
            },
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ArtistResolutionHelper.navigateToArtist(
                    context,
                    jellyfinId: '3abb1a64b01694b0df1411d4f6ee051e',
                    artistName: 'Metro Boomin',
                  );
                },
                child: const Text('Go'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();

        expect(testObserver.pushedRoutes, contains(ArtistScreen.routeName));
        expect(find.text('LocalArtistScreen'), findsOneWidget);
      } finally {
        ArtistIdentityService.mockIsOffline = null;
      }
    });

    testWidgets('physically tapping artist in Now Playing routes to CatalogArtistScreen online', (tester) async {
      final testObserver = _TestNavigatorObserver();
      final track = BaseItemDto(
        id: const BaseItemId('track-now-playing-1'),
        name: 'Helmet',
        type: 'Audio',
        artistItems: [
          NameIdPair(id: const BaseItemId('349ff016da8eade9fb2ba11ed655a2b9'), name: 'Steve Lacy'),
        ],
        providerIds: {
          'MusicBrainzArtist': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [testObserver],
          routes: {
            CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogArtistScreen')),
            ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
          },
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final artistTarget = ArtistResolutionHelper.resolveArtistNavigationTarget(
                  track: track,
                  fallbackArtistName: 'Steve Lacy',
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // In real app (track_name_content.dart), artistMbid is not passed:
                    ArtistResolutionHelper.navigateToArtist(
                      context,
                      artistItem: artistTarget,
                      artistName: 'Steve Lacy',
                    );
                  },
                  child: const Text('NowPlaying Steve Lacy'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('NowPlaying Steve Lacy'));
      await tester.pumpAndSettle();

      expect(testObserver.pushedRoutes, contains(CatalogArtistScreen.routeName));
      expect(find.text('CatalogArtistScreen'), findsOneWidget);
      final args = testObserver.pushedArguments.whereType<CatalogArtistScreenArguments>().first;
      expect(args.artistMbid, equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));
    });

    testWidgets('physically tapping artist on album routes to CatalogArtistScreen online', (tester) async {
      final testObserver = _TestNavigatorObserver();
      final album = BaseItemDto(
        id: const BaseItemId('album-gemini-rights'),
        name: 'Gemini Rights',
        type: 'MusicAlbum',
        artistItems: [
          NameIdPair(id: const BaseItemId('349ff016da8eade9fb2ba11ed655a2b9'), name: 'Steve Lacy'),
        ],
        providerIds: {
          'MusicBrainzArtist': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [testObserver],
          routes: {
            CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogArtistScreen')),
            ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
          },
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final artistTarget = ArtistResolutionHelper.resolveArtistNavigationTarget(
                  track: album,
                  fallbackArtistName: 'Steve Lacy',
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // In real app (album_screen.dart), artistMbid is not passed:
                    ArtistResolutionHelper.navigateToArtist(
                      context,
                      artistItem: artistTarget,
                      artistName: 'Steve Lacy',
                    );
                  },
                  child: const Text('Album Steve Lacy'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Album Steve Lacy'));
      await tester.pumpAndSettle();

      expect(testObserver.pushedRoutes, contains(CatalogArtistScreen.routeName));
      expect(find.text('CatalogArtistScreen'), findsOneWidget);
      final args = testObserver.pushedArguments.whereType<CatalogArtistScreenArguments>().first;
      expect(args.artistMbid, equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));
    });

    testWidgets('disambiguated_local_presence routes to R&B Steve Lacy and caches mapping', (tester) async {
      final client = CatalogApiClient(
        credentials: _TestCredentials(),
        client: _MockHttpClient((request) async {
          expect(request.url.path, '/v1/artists/resolve');
          return http.Response(
            jsonEncode({
              'id': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
              'artist_id': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
              'name': 'Steve Lacy',
              'confidence': 'disambiguated_local_presence',
            }),
            200,
          );
        }),
      );
      GetIt.instance.registerSingleton<CatalogApiClient>(client);

      final mbid = await ArtistIdentityService.resolveArtistMbid(
        name: 'Steve Lacy',
      );

      expect(mbid, equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));
      expect(mbid, isNot(equals('ca9766a0-1c30-43e6-a213-bac1334efc4a')));

      // Subsequent resolution resolves from memory cache without network call
      final cachedMbid = await ArtistIdentityService.resolveArtistMbid(
        name: 'Steve Lacy',
      );
      expect(cachedMbid, equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));
    });

    testWidgets('credited_identity confidence routes Steve Lacy by itemId and persists mapping', (tester) async {
      final client = CatalogApiClient(
        credentials: _TestCredentials(),
        client: _MockHttpClient((request) async {
          expect(request.url.path, '/v1/artists/resolve');
          expect(request.url.queryParameters['item_id'], '349ff016da8eade9fb2ba11ed655a2b9');
          return http.Response(
            jsonEncode({
              'id': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
              'artist_id': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
              'name': 'Steve Lacy',
              'confidence': 'credited_identity',
            }),
            200,
          );
        }),
      );
      GetIt.instance.registerSingleton<CatalogApiClient>(client);

      final mbid = await ArtistIdentityService.resolveArtistMbid(
        jellyfinId: '349ff016da8eade9fb2ba11ed655a2b9',
        name: 'Steve Lacy',
      );

      expect(mbid, equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));

      // Check persistent prefs
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('artist_mbid_by_jf:349ff016da8eade9fb2ba11ed655a2b9'), equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));
      expect(prefs.getString('artist_mbid_by_name:steve lacy'), equals('b29020d6-5dbf-4c99-b16f-c009f8a712ff'));
    });

    testWidgets('The Mamas & the Papas resolves accurately preserving name and ampersand', (tester) async {
      final client = CatalogApiClient(
        credentials: _TestCredentials(),
        client: _MockHttpClient((request) async {
          expect(request.url.path, '/v1/artists/resolve');
          return http.Response(
            jsonEncode({
              'id': 'ff294730-0315-440d-a543-54005779c15b',
              'artist_id': 'ff294730-0315-440d-a543-54005779c15b',
              'name': 'The Mamas & the Papas',
              'confidence': 'canonical_identity',
            }),
            200,
          );
        }),
      );
      GetIt.instance.registerSingleton<CatalogApiClient>(client);

      final testObserver = _TestNavigatorObserver();
      final mamasArtistItem = BaseItemDto(
        id: const BaseItemId('b15fc9bf8c3c5667e13a0312cf4beb10'),
        name: 'The Mamas & the Papas',
        type: 'MusicArtist',
        providerIds: {
          'MusicBrainzArtist': 'ff294730-0315-440d-a543-54005779c15b',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [testObserver],
          routes: {
            CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogArtistScreen')),
            ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
          },
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                ArtistResolutionHelper.navigateToArtist(
                  context,
                  artistItem: mamasArtistItem,
                );
              },
              child: const Text('Tap The Mamas & the Papas'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap The Mamas & the Papas'));
      await tester.pumpAndSettle();

      expect(testObserver.pushedRoutes, contains(CatalogArtistScreen.routeName));
      final args = testObserver.pushedArguments.whereType<CatalogArtistScreenArguments>().first;
      expect(args.artistMbid, equals('ff294730-0315-440d-a543-54005779c15b'));
      expect(args.initialName, equals('The Mamas & the Papas'));
    });

    testWidgets('unresolvable ambiguity does not guess and safely falls back to local ArtistScreen', (tester) async {
      final client = CatalogApiClient(
        credentials: _TestCredentials(),
        client: _MockHttpClient((request) async {
          expect(request.url.path, '/v1/artists/resolve');
          return http.Response(
            jsonEncode({
              'confidence': 'ambiguous',
              'candidates': [
                {'id': 'ca9766a0-1c30-43e6-a213-bac1334efc4a', 'name': 'Steve Lacy'},
                {'id': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff', 'name': 'Steve Lacy'},
              ],
            }),
            200,
          );
        }),
      );
      GetIt.instance.registerSingleton<CatalogApiClient>(client);

      final testObserver = _TestNavigatorObserver();
      final ambiguousArtist = BaseItemDto(
        id: const BaseItemId('unknown-jf-id'),
        name: 'Steve Lacy',
        type: 'MusicArtist',
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [testObserver],
          routes: {
            CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogArtistScreen')),
            ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
          },
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                ArtistResolutionHelper.navigateToArtist(
                  context,
                  artistItem: ambiguousArtist,
                );
              },
              child: const Text('Tap Ambiguous Artist'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Ambiguous Artist'));
      await tester.pumpAndSettle();

      // Verified: falls back safely to local ArtistScreen, never blindly picks the wrong MBID
      expect(testObserver.pushedRoutes, contains(ArtistScreen.routeName));
      expect(find.text('LocalArtistScreen'), findsOneWidget);
    });

    testWidgets('offline navigation from Now Playing opens local ArtistScreen', (tester) async {
      ArtistIdentityService.mockIsOffline = true;
      try {
        final testObserver = _TestNavigatorObserver();
        final track = BaseItemDto(
          id: const BaseItemId('offline-track-1'),
          name: 'Buttons',
          type: 'Audio',
          artistItems: [
            NameIdPair(id: const BaseItemId('349ff016da8eade9fb2ba11ed655a2b9'), name: 'Steve Lacy'),
          ],
          providerIds: {
            'MusicBrainzArtist': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [testObserver],
            routes: {
              CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogArtistScreen')),
              ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
            },
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final artistTarget = ArtistResolutionHelper.resolveArtistNavigationTarget(
                    track: track,
                    fallbackArtistName: 'Steve Lacy',
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      ArtistResolutionHelper.navigateToArtist(
                        context,
                        artistItem: artistTarget,
                        artistName: 'Steve Lacy',
                      );
                    },
                    child: const Text('NowPlaying Offline'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('NowPlaying Offline'));
        await tester.pumpAndSettle();

        expect(testObserver.pushedRoutes, contains(ArtistScreen.routeName));
        expect(find.text('LocalArtistScreen'), findsOneWidget);
      } finally {
        ArtistIdentityService.mockIsOffline = null;
      }
    });

    testWidgets('offline navigation from Album Screen opens local ArtistScreen', (tester) async {
      ArtistIdentityService.mockIsOffline = true;
      try {
        final testObserver = _TestNavigatorObserver();
        final album = BaseItemDto(
          id: const BaseItemId('album-offline-1'),
          name: 'Gemini Rights',
          type: 'MusicAlbum',
          artistItems: [
            NameIdPair(id: const BaseItemId('349ff016da8eade9fb2ba11ed655a2b9'), name: 'Steve Lacy'),
          ],
          providerIds: {
            'MusicBrainzArtist': 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [testObserver],
            routes: {
              CatalogArtistScreen.routeName: (context) => const Scaffold(body: Text('CatalogArtistScreen')),
              ArtistScreen.routeName: (context) => const Scaffold(body: Text('LocalArtistScreen')),
            },
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final artistTarget = ArtistResolutionHelper.resolveArtistNavigationTarget(
                    track: album,
                    fallbackArtistName: 'Steve Lacy',
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      ArtistResolutionHelper.navigateToArtist(
                        context,
                        artistItem: artistTarget,
                        artistName: 'Steve Lacy',
                      );
                    },
                    child: const Text('Album Offline'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Album Offline'));
        await tester.pumpAndSettle();

        expect(testObserver.pushedRoutes, contains(ArtistScreen.routeName));
        expect(find.text('LocalArtistScreen'), findsOneWidget);
      } finally {
        ArtistIdentityService.mockIsOffline = null;
      }
    });
  });
}
