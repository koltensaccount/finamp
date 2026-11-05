import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:finamp/models/book_models.dart';
import 'package:finamp/screens/book_detail_screen.dart';
import 'package:finamp/screens/books_screen.dart';
import 'package:finamp/services/books_api_client.dart';
import 'package:finamp/services/catalog_credential_store.dart';

class FakeCredStore implements CatalogCredentialStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CatalogCredentials?> read() async =>
      CatalogCredentials(endpoint: Uri.parse('http://127.0.0.1:8765'), token: 'tok');
  @override
  Future<void> save(CatalogCredentials credentials) async {}
}

void main() {
  final getIt = GetIt.instance;

  tearDown(() {
    getIt.reset();
  });

  group('Worldwide Discovery & Acquisition Tests', () {
    test('WorldwideBookResult parses Open Library & local enrichment correctly', () {
      final json = {
        'source': 'open_library',
        'external_id': 'OL123W',
        'title': 'Project Hail Mary',
        'author': 'Andy Weir',
        'authors': ['Andy Weir'],
        'published_year': 2021,
        'cover_url': 'https://covers.openlibrary.org/b/id/10523366-L.jpg',
        'isbns': ['9780593135204'],
        'edition_count': 12,
        'languages': ['eng'],
        'description': 'A lone astronaut must save the earth.',
        'is_local': true,
        'local_work_id': 'work-phm-1',
        'owned_formats': ['audiobook'],
        'request_id': 'req-1',
        'request_state': 'available',
        'acquired_formats': ['audiobook'],
        'acquisition_progress': 1.0,
      };

      final result = WorldwideBookResult.fromJson(json);
      expect(result.title, 'Project Hail Mary');
      expect(result.author, 'Andy Weir');
      expect(result.publishedYear, 2021);
      expect(result.isLocal, isTrue);
      expect(result.localWorkId, 'work-phm-1');
      expect(result.ownedFormats, contains('audiobook'));
      expect(result.requestState, 'available');
      expect(result.acquisitionProgress, 1.0);
    });

    test('BookRequestItem parses active server acquisition job', () {
      final json = {
        'id': 'req-time-machine',
        'title': 'The Time Machine',
        'author': 'H.G. Wells',
        'desired_format': 'epub',
        'state': 'acquiring',
        'progress_percentage': 0.65,
        'acquired_formats': ['epub'],
        'error_message': null,
        'created_at': 1730750000.0,
      };

      final req = BookRequestItem.fromJson(json);
      expect(req.id, 'req-time-machine');
      expect(req.title, 'The Time Machine');
      expect(req.state, 'acquiring');
      expect(req.progressPercentage, 0.65);
      expect(req.isCompleted, isFalse);
      expect(req.acquiredFormats, ['epub']);
    });

    testWidgets('BooksScreen performs worldwide discovery search and displays results with badges', (tester) async {
      final sampleWorldwideResults = [
        {
          'source': 'open_library',
          'external_id': 'OL111W',
          'title': 'Project Hail Mary',
          'author': 'Andy Weir',
          'published_year': 2021,
          'is_local': false,
          'owned_formats': <String>[],
          'request_id': null,
          'request_state': null,
        },
        {
          'source': 'open_library',
          'external_id': 'OL222W',
          'title': 'The Time Machine',
          'author': 'H.G. Wells',
          'published_year': 1895,
          'is_local': true,
          'local_work_id': 'work-time-machine',
          'owned_formats': ['epub'],
        },
      ];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/books') {
          return http.Response(jsonEncode({'books': []}), 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path == '/v1/books/search') {
          return http.Response(
            jsonEncode({
              'query': request.url.queryParameters['q'],
              'total': sampleWorldwideResults.length,
              'results': sampleWorldwideResults,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = BooksApiClient(credentials: FakeCredStore(), client: mockClient);
      getIt.registerSingleton<BooksApiClient>(apiClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BooksScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Books'), findsOneWidget);

      // Search worldwide
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Hail Mary');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify results and badges
      expect(find.text('Worldwide Results (2)'), findsOneWidget);
      expect(find.text('Project Hail Mary'), findsWidgets);
      expect(find.text('The Time Machine'), findsWidgets);
      expect(find.text('WORLDWIDE'), findsOneWidget);
      expect(find.text('IN LIBRARY'), findsOneWidget);
    });

    testWidgets('BookDetailScreen shows Request Book button for unowned worldwide books', (tester) async {
      const worldwideItem = WorldwideBookResult(
        source: 'open_library',
        externalId: 'OL123W',
        title: 'Project Hail Mary',
        author: 'Andy Weir',
        publishedYear: 2021,
        description: 'A lone astronaut awakens on a spaceship.',
        isLocal: false,
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/books/requests') {
          return http.Response(
            jsonEncode({
              'id': 'req-new',
              'title': 'Project Hail Mary',
              'author': 'Andy Weir',
              'desired_format': 'both',
              'state': 'searching',
              'progress_percentage': 0.1,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = BooksApiClient(credentials: FakeCredStore(), client: mockClient);
      getIt.registerSingleton<BooksApiClient>(apiClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BookDetailScreen(
              worldwideItem: worldwideItem,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Project Hail Mary'), findsOneWidget);
      expect(find.text('Andy Weir'), findsOneWidget);
      expect(find.text('WORLDWIDE DISCOVERY'), findsOneWidget);
      expect(find.text('Request Book'), findsOneWidget);
    });
  });
}
