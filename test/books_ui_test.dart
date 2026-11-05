import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:finamp/models/book_models.dart';
import 'package:finamp/screens/book_detail_screen.dart';
import 'package:finamp/screens/books_screen.dart';
import 'package:finamp/screens/catalog_settings_screen.dart';
import 'package:finamp/screens/epub_reader_screen.dart';
import 'package:finamp/services/books_api_client.dart';
import 'package:finamp/services/books_download_service.dart';
import 'package:finamp/services/catalog_credential_store.dart';

import 'books_service_test.dart' show createTestEpub;

class FakeCredStore implements CatalogCredentialStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CatalogCredentials?> read() async => CatalogCredentials(endpoint: Uri.parse('http://127.0.0.1:8765'), token: 'tok');
  @override
  Future<void> save(CatalogCredentials credentials) async {}
}

void main() {
  final getIt = GetIt.instance;

  tearDown(() {
    getIt.reset();
  });

  group('Books UI & Interaction Tests', () {
    testWidgets('BooksScreen renders list, filter chips, and reacts to taps', (tester) async {
      final sampleBooks = [
        {
          'id': 'work-gatsby',
          'title': 'The Great Gatsby',
          'author': 'F. Scott Fitzgerald',
          'available_formats': ['epub', 'audiobook'],
          'is_paired': true,
          'progress': {
            'reading_percentage': 0.45,
            'last_active_format': 'reading',
          },
        },
        {
          'id': 'work-hobbit',
          'title': 'The Hobbit',
          'author': 'J.R.R. Tolkien',
          'available_formats': ['audiobook'],
          'is_paired': false,
          'progress': {},
        },
      ];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/books') {
          return http.Response(jsonEncode({'books': sampleBooks}), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not found', 404);
      });

      final apiClient = BooksApiClient(credentials: FakeCredStore(), client: mockClient);
      getIt.registerSingleton<BooksApiClient>(apiClient);
      final downloadService = BooksDownloadService(apiClient: apiClient);
      getIt.registerSingleton<BooksDownloadService>(downloadService);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BooksScreen(),
          ),
        ),
      );

      // Wait for books to load
      await tester.pumpAndSettle();

      expect(find.text('Books'), findsOneWidget);
      expect(find.text('The Great Gatsby'), findsWidgets);
      expect(find.text('The Hobbit'), findsWidgets);

      // Test filter chips
      expect(find.text('All'), findsOneWidget);
      expect(find.text('E-Books'), findsOneWidget);
      expect(find.text('Audiobooks'), findsOneWidget);

      await tester.tap(find.text('Audiobooks'));
      await tester.pumpAndSettle();
    });

    testWidgets('BookDetailScreen displays metadata and download button', (tester) async {
      final sampleDetail = {
        'id': 'work-gatsby',
        'title': 'The Great Gatsby',
        'author': 'F. Scott Fitzgerald',
        'description': 'A novel of the roaring twenties',
        'genres': ['Fiction', 'Classic'],
        'available_formats': ['epub', 'audiobook'],
        'is_paired': true,
        'editions': [
          {
            'id': 'ed-gatsby-epub',
            'work_id': 'work-gatsby',
            'format': 'epub',
            'title': 'The Great Gatsby',
            'publisher': 'Scribner',
            'published_year': 1925,
            'language': 'en',
            'isbn': '9780743273565',
            'chapters': [
              {'id': 'ch-1', 'edition_id': 'ed-gatsby-epub', 'index_num': 1, 'title': 'Chapter I'},
              {'id': 'ch-2', 'edition_id': 'ed-gatsby-epub', 'index_num': 2, 'title': 'Chapter II'},
            ],
            'assets': [],
          },
          {
            'id': 'ed-gatsby-audio',
            'work_id': 'work-gatsby',
            'format': 'audiobook',
            'title': 'The Great Gatsby',
            'publisher': 'Scribner Audio',
            'published_year': 2002,
            'language': 'en',
            'chapters': [],
            'assets': [],
          }
        ],
        'progress': {
          'reading_percentage': 0.1,
          'reading_cfi': '/6/2[ch1]!/4/2',
        },
      };

      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/books/work-gatsby') {
          return http.Response(jsonEncode(sampleDetail), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not found', 404);
      });

      final apiClient = BooksApiClient(credentials: FakeCredStore(), client: mockClient);
      getIt.registerSingleton<BooksApiClient>(apiClient);
      final downloadService = BooksDownloadService(apiClient: apiClient);
      getIt.registerSingleton<BooksDownloadService>(downloadService);

      await tester.pumpWidget(
        const MaterialApp(
          home: BookDetailScreen(workId: 'work-gatsby'),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('The Great Gatsby'), findsWidgets);
      expect(find.text('F. Scott Fitzgerald'), findsOneWidget);
      expect(find.text('Resume Reading'), findsOneWidget);
      expect(find.text('Listen'), findsOneWidget);
      expect(find.text('Download for Offline Use'), findsOneWidget);
      expect(find.text('PAIRED SYNC'), findsOneWidget);
      expect(find.text('Scribner'), findsWidgets);
    });

    testWidgets('EpubReaderScreen displays content, changes theme, and advances chapters', (tester) async {
      final epubBytes = createTestEpub();

      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/books/work-gatsby/epub') {
          return http.Response.bytes(epubBytes, 200, headers: {'content-type': 'application/epub+zip'});
        }
        if (request.url.path == '/v1/books/work-gatsby/progress') {
          return http.Response(jsonEncode({'status': 'ok'}), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not found', 404);
      });

      final apiClient = BooksApiClient(credentials: FakeCredStore(), client: mockClient);
      getIt.registerSingleton<BooksApiClient>(apiClient);

      await tester.pumpWidget(
        const MaterialApp(
          home: EpubReaderScreen(
            workId: 'work-gatsby',
            title: 'The Great Gatsby',
            author: 'F. Scott Fitzgerald',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Gatsby text rendered
      expect(find.textContaining('In my younger and more vulnerable years'), findsOneWidget);
      expect(find.text('Chapter I'), findsWidgets);

      // Open Appearance bottom sheet
      final aaButton = find.byIcon(Icons.format_size_rounded);
      expect(aaButton, findsOneWidget);
      await tester.tap(aaButton);
      await tester.pumpAndSettle();

      // Theme options visible
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Sepia'), findsOneWidget);

      // Select Sepia theme
      await tester.tap(find.text('Sepia'));
      await tester.pumpAndSettle();

      // Close bottom sheet
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Advance to next chapter
      final nextChapterButton = find.byIcon(Icons.arrow_forward_ios_rounded);
      expect(nextChapterButton, findsOneWidget);
      await tester.tap(nextChapterButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('About half way between West Egg and New York'), findsOneWidget);
      expect(find.text('Chapter II'), findsWidgets);
    });

    testWidgets('BooksScreen falls back to offline downloaded books when backend is unreachable', (tester) async {
      // Mock client that fails network requests (simulating offline mode)
      final failingClient = MockClient((request) async {
        return http.Response('Network unreachable', 503);
      });

      final apiClient = BooksApiClient(credentials: FakeCredStore(), client: failingClient);
      getIt.registerSingleton<BooksApiClient>(apiClient);

      final fakeOfflineBook = BookSummary(
        id: 'work-offline-1',
        title: 'The Hobbit (Downloaded)',
        author: 'J.R.R. Tolkien',
        availableFormats: const ['audiobook'],
        isPaired: false,
        progress: const BookProgress(),
      );

      final mockDownloadService = _MockOfflineDownloadService([fakeOfflineBook], apiClient: apiClient);
      getIt.registerSingleton<BooksDownloadService>(mockDownloadService);

      await tester.pumpWidget(
        const MaterialApp(
          home: BooksScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that offline book is loaded and displayed despite network failure
      expect(find.text('The Hobbit (Downloaded)'), findsWidgets);
      expect(find.text('J.R.R. Tolkien'), findsWidgets);
      expect(find.text('Offline Library'), findsOneWidget);
    });

    testWidgets('BooksScreen displays setup action when credentials are not configured', (tester) async {
      final unconfiguredClient = BooksApiClient(credentials: _EmptyCredStore());
      getIt.registerSingleton<BooksApiClient>(unconfiguredClient);
      final downloadService = _MockOfflineDownloadService([], apiClient: unconfiguredClient);
      getIt.registerSingleton<BooksDownloadService>(downloadService);

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            CatalogSettingsScreen.routeName: (context) => const Scaffold(body: Text('Settings Screen Content')),
          },
          home: const Scaffold(
            body: BooksScreen(),
          ),
        ),
      );

      // Pump microtasks and frames for _loadBooks Future to complete
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Connect Books & Catalog'), findsOneWidget);
      expect(find.text('Configure Connection'), findsOneWidget);
      expect(find.text('Unable to load books'), findsNothing);

      // Tap configure connection to verify it navigates to CatalogSettingsScreen
      await tester.tap(find.text('Configure Connection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Settings Screen Content'), findsOneWidget);
    });
  });
}

class _EmptyCredStore implements CatalogCredentialStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CatalogCredentials?> read() async => null;
  @override
  Future<void> save(CatalogCredentials credentials) async {}
}

class _MockOfflineDownloadService extends BooksDownloadService {
  final List<BookSummary> _offline;
  _MockOfflineDownloadService(this._offline, {required super.apiClient});

  @override
  Future<List<BookSummary>> listDownloadedBooks() async => _offline;

  @override
  bool isDownloaded(String workId) => _offline.any((b) => b.id == workId);
}
