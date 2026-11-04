import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finamp/models/book_models.dart';
import 'package:finamp/services/books_api_client.dart';
import 'package:finamp/services/books_download_service.dart';
import 'package:finamp/services/catalog_credential_store.dart';
import 'package:finamp/services/epub_reader_service.dart';
import 'package:http/http.dart' as http;

Uint8List createTestEpub() {
  final archive = Archive();

  // mimetype
  archive.addFile(ArchiveFile.noCompress('mimetype', 20, utf8.encode('application/epub+zip')));

  // container.xml
  const containerXml = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
  archive.addFile(ArchiveFile('META-INF/container.xml', containerXml.length, utf8.encode(containerXml)));

  // content.opf
  const opfXml = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>The Great Gatsby</dc:title>
    <dc:creator>F. Scott Fitzgerald</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''';
  archive.addFile(ArchiveFile('OEBPS/content.opf', opfXml.length, utf8.encode(opfXml)));

  // ch1.xhtml
  const ch1Xhtml = '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html>
<head><title>Chapter I</title></head>
<body>
  <h1>Chapter I</h1>
  <p>In my younger and more vulnerable years my father gave me some advice that I’ve been turning over in my mind ever since.</p>
  <p>Whenever you feel like criticizing anyone, he told me, just remember that all the people in this world haven’t had the advantages that you’ve had.</p>
</body>
</html>''';
  archive.addFile(ArchiveFile('OEBPS/ch1.xhtml', ch1Xhtml.length, utf8.encode(ch1Xhtml)));

  // ch2.xhtml
  const ch2Xhtml = '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html>
<head><title>Chapter II</title></head>
<body>
  <h1>Chapter II</h1>
  <p>About half way between West Egg and New York the motor road hastily joins the railroad and runs beside it for a quarter of a mile.</p>
</body>
</html>''';
  archive.addFile(ArchiveFile('OEBPS/ch2.xhtml', ch2Xhtml.length, utf8.encode(ch2Xhtml)));

  final zipBytes = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipBytes!);
}

void main() {
  group('Book Models Tests', () {
    test('BookProgress handles serialization and format detection', () {
      final prog = BookProgress(
        readingCfi: '/6/2[ch1]!/4/2',
        readingPercentage: 0.25,
        listeningSeconds: 120.0,
        lastActiveFormat: 'reading',
      );
      expect(prog.hasReadingProgress, isTrue);
      expect(prog.hasListeningProgress, isTrue);
      expect(prog.hasProgress, isTrue);

      final json = prog.toJson();
      final restored = BookProgress.fromJson(json);
      expect(restored.readingCfi, '/6/2[ch1]!/4/2');
      expect(restored.readingPercentage, 0.25);
      expect(restored.listeningSeconds, 120.0);
      expect(restored.lastActiveFormat, 'reading');
    });

    test('BookSummary correctly parses formats and flags', () {
      final summary = BookSummary.fromJson({
        'id': 'work-gatsby',
        'title': 'The Great Gatsby',
        'author': 'F. Scott Fitzgerald',
        'available_formats': ['epub', 'audiobook'],
        'is_paired': true,
        'progress': {
          'reading_percentage': 0.5,
        },
      });

      expect(summary.hasEpub, isTrue);
      expect(summary.hasAudiobook, isTrue);
      expect(summary.isPaired, isTrue);
      expect(summary.progress.readingPercentage, 0.5);
    });
  });

  group('EpubReaderService Tests', () {
    test('parses EPUB archive, extracts chapters and metadata', () {
      final epubBytes = createTestEpub();
      final book = EpubReaderService.parse(epubBytes);

      expect(book.title, 'The Great Gatsby');
      expect(book.author, 'F. Scott Fitzgerald');
      expect(book.chapters.length, 2);

      final ch1 = book.chapters[0];
      expect(ch1.title, 'Chapter I');
      expect(ch1.paragraphs.length, 3);
      expect(ch1.paragraphs[1], contains('In my younger and more vulnerable years'));

      final ch2 = book.chapters[1];
      expect(ch2.title, 'Chapter II');
      expect(ch2.paragraphs.length, 2);
      expect(ch2.paragraphs[1], contains('About half way between West Egg'));
    });

    test('generates and parses stable EPUB CFIs', () {
      final epubBytes = createTestEpub();
      final book = EpubReaderService.parse(epubBytes);

      final cfi = book.makeCfi(0, 1);
      expect(cfi, '/6/2[ch1]!/4/4');

      final (chIdx, pIdx) = book.parseCfi(cfi);
      expect(chIdx, 0);
      expect(pIdx, 1);

      final cfiCh2 = book.makeCfi(1, 0);
      expect(cfiCh2, '/6/4[ch2]!/4/2');
      final (ch2Idx, p2Idx) = book.parseCfi(cfiCh2);
      expect(ch2Idx, 1);
      expect(p2Idx, 0);
    });
  });

  group('BooksDownloadService Tests', () {
    test('manages download state and reactive notifiers', () {
      final creds = FakeCredentials();
      final apiClient = BooksApiClient(credentials: creds);
      final downloadService = BooksDownloadService(apiClient: apiClient);

      expect(downloadService.isDownloaded('work-1'), isFalse);
      expect(downloadService.isDownloading('work-1'), isFalse);

      downloadService.downloadedWorkIds.value = {'work-1'};
      expect(downloadService.isDownloaded('work-1'), isTrue);
      expect(downloadService.isDownloaded('work-2'), isFalse);
    });
  });
}

class FakeCredentials implements CatalogCredentialStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CatalogCredentials?> read() async => CatalogCredentials(endpoint: Uri.parse('http://localhost:8765'), token: 'test-token');
  @override
  Future<void> save(CatalogCredentials credentials) async {}
}
