import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:finamp/models/book_models.dart';
import 'package:finamp/screens/audiobook_player_screen.dart';
import 'package:finamp/screens/epub_reader_screen.dart';
import 'package:finamp/services/books_api_client.dart';
import 'package:finamp/services/books_download_service.dart';
import 'package:finamp/services/catalog_credential_store.dart';

class MockCatalogCredentialStore implements CatalogCredentialStore {
  @override
  Future<CatalogCredentials?> read() async {
    return CatalogCredentials(
      endpoint: Uri.parse('http://127.0.0.1:8765'),
      token: 'test-token',
    );
  }

  @override
  Future<void> save(CatalogCredentials credentials) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4: Forced Alignment & Handoff Tests', () {
    late BooksApiClient apiClient;
    late MockClient mockClient;

    setUp(() {
      GetIt.instance.reset();
      final credStore = MockCatalogCredentialStore();
      GetIt.instance.registerSingleton<CatalogCredentialStore>(credStore);

      mockClient = MockClient((request) async {
        final path = request.url.path;

        if (path.contains('/align/audio-to-cfi')) {
          return http.Response(
            jsonEncode({
              'epub_cfi': '/6/6[chapter-1.xhtml]!/4/2/1:0',
              'sentence_idx': 1,
              'confidence': 0.986,
              'text': 'The Time Traveller was expounding a recondite matter to us.',
              'alignment_level': 'sentence',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (path.contains('/align/cfi-to-audio')) {
          return http.Response(
            jsonEncode({
              'audio_track': 1,
              'audio_timestamp_seconds': 25.64,
              'confidence': 0.986,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (path.contains('/alignment')) {
          return http.Response(
            jsonEncode({
              'work_id': 'work-the-time-machine-h-g-wells',
              'alignment_level': 'sentence',
              'confidence': 0.844,
              'mapping_data': [
                {
                  'sentence_idx': 1,
                  'epub_cfi': '/6/6[chapter-1.xhtml]!/4/2/1:0',
                  'audio_track': 1,
                  'audio_start_sec': 25.64,
                  'audio_end_sec': 31.50,
                  'confidence': 0.986,
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('{"status": "ok"}', 200, headers: {'content-type': 'application/json'});
      });

      apiClient = BooksApiClient(credentials: credStore, client: mockClient);
      GetIt.instance.registerSingleton<BooksApiClient>(apiClient);
    });

    test('BooksApiClient maps audio position to EPUB CFI', () async {
      final res = await apiClient.mapAudioToReadingLocation(
        'work-the-time-machine-h-g-wells',
        track: 1,
        seconds: 28.0,
      );

      expect(res, isNotNull);
      expect(res!['epub_cfi'], '/6/6[chapter-1.xhtml]!/4/2/1:0');
      expect(res['sentence_idx'], 1);
      expect(res['confidence'], 0.986);
      expect(res['alignment_level'], 'sentence');
    });

    test('BooksApiClient maps reading CFI to audio position', () async {
      final res = await apiClient.mapReadingLocationToAudio(
        'work-the-time-machine-h-g-wells',
        cfi: '/6/6[chapter-1.xhtml]!/4/2/1:0',
      );

      expect(res, isNotNull);
      expect(res!['audio_track'], 1);
      expect(res['audio_timestamp_seconds'], 25.64);
      expect(res['confidence'], 0.986);
    });

    testWidgets('AudiobookPlayerScreen initializes with initialTrack and initialPosition', (tester) async {
      final book = BookDetail(
        id: 'work-the-time-machine-h-g-wells',
        title: 'The Time Machine',
        author: 'H. G. Wells',
        description: 'Time travel classic',
        genres: ['Science Fiction'],
        seriesName: null,
        seriesOrder: null,
        coverUrl: null,
        availableFormats: ['epub', 'audiobook'],
        isPaired: true,
        progress: const BookProgress(
          readingCfi: '/6/6[chapter-1.xhtml]!/4/2/1:0',
          readingPercentage: 0.15,
          readingUpdatedAt: 1000,
          listeningSeconds: 25.0,
          listeningTrackId: null,
          listeningPercentage: 0.05,
          listeningUpdatedAt: 1000,
          lastActiveFormat: 'audiobook',
          isFinished: false,
        ),
        editions: [
          const BookEdition(
            id: 'ed-audio',
            workId: 'work-the-time-machine-h-g-wells',
            format: 'audiobook',
            title: 'The Time Machine',
            authors: ['H. G. Wells'],
            narrators: ['Bob Neufeld'],
            publisher: 'LibriVox',
            publishedYear: 1895,
            language: 'en',
            isbn: null,
            asin: null,
            description: null,
            coverUrl: null,
            chapters: [
              BookChapter(
                id: 'ch-1',
                editionId: 'ed-audio',
                indexNum: 1,
                title: 'Chapter 1',
                startSeconds: 0.0,
                endSeconds: 1280.0,
                epubCfi: '/6/6[chapter-1.xhtml]!/4/2/1:0',
              ),
              BookChapter(
                id: 'ch-2',
                editionId: 'ed-audio',
                indexNum: 2,
                title: 'Chapter 2',
                startSeconds: 1280.0,
                endSeconds: 2108.0,
                epubCfi: '/6/6[chapter-2.xhtml]!/4/2/1:0',
              ),
            ],
            assets: [
              BookAsset(
                id: 'asset-1',
                editionId: 'ed-audio',
                kind: 'audio_track',
                format: 'mp3',
                trackNumber: 1,
                durationSeconds: 1280.0,
              ),
              BookAsset(
                id: 'asset-2',
                editionId: 'ed-audio',
                kind: 'audio_track',
                format: 'mp3',
                trackNumber: 2,
                durationSeconds: 828.0,
              ),
            ],
          ),
        ],
        alignment: {
          'alignment_level': 'sentence',
          'confidence': 0.844,
          'mapping_data': [
            {
              'sentence_idx': 1,
              'epub_cfi': '/6/6[chapter-1.xhtml]!/4/2/1:0',
              'audio_track': 1,
              'audio_start_sec': 25.64,
              'audio_end_sec': 31.50,
            }
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AudiobookPlayerScreen(
            book: book,
            audioEdition: book.audioEdition!,
            initialTrack: 1,
            initialPosition: const Duration(seconds: 26),
          ),
        ),
      );

      expect(find.text('The Time Machine'), findsWidgets);
      expect(find.text('H. G. Wells'), findsWidgets);
      expect(find.text('Read From Here'), findsOneWidget);
    });
  });
}
