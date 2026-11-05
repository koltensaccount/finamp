import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class EpubParsedChapter {
  const EpubParsedChapter({
    required this.index,
    required this.id,
    required this.title,
    required this.href,
    required this.htmlContent,
    required this.plainText,
    required this.paragraphs,
  });

  final int index;
  final String id;
  final String title;
  final String href;
  final String htmlContent;
  final String plainText;
  final List<String> paragraphs;
}

class EpubBookData {
  const EpubBookData({
    required this.title,
    required this.author,
    required this.chapters,
  });

  final String title;
  final String author;
  final List<EpubParsedChapter> chapters;

  int totalParagraphs() => chapters.fold(0, (sum, ch) => sum + ch.paragraphs.length);

  String makeCfi(int chapterIndex, int paragraphIndex) {
    if (chapterIndex < 0 || chapterIndex >= chapters.length) return '/6/2!/4/2';
    final ch = chapters[chapterIndex];
    final spineNum = (chapterIndex + 1) * 2;
    final paraNum = (paragraphIndex + 1) * 2;
    return '/6/$spineNum[${ch.id}]!/4/$paraNum';
  }

  (int chapterIndex, int paragraphIndex) parseCfi(String? cfi) {
    if (cfi == null || !cfi.startsWith('/6/')) return (0, 0);
    try {
      final parts = cfi.split('!');
      if (parts.isEmpty) return (0, 0);
      final spinePart = parts[0].replaceAll('/6/', '');
      final bracketIdx = spinePart.indexOf('[');
      final spineStr = bracketIdx != -1 ? spinePart.substring(0, bracketIdx) : spinePart;
      final spineNum = int.tryParse(spineStr) ?? 2;
      final chapterIdx = (spineNum ~/ 2) - 1;

      int paraIdx = 0;
      if (parts.length > 1) {
        final paraPart = parts[1].replaceAll('/4/', '');
        final colonIdx = paraPart.indexOf(':');
        final cleanParaStr = colonIdx != -1 ? paraPart.substring(0, colonIdx) : paraPart;
        final paraNum = int.tryParse(cleanParaStr) ?? 2;
        paraIdx = (paraNum ~/ 2) - 1;
      }
      return (
        chapterIdx.clamp(0, chapters.isEmpty ? 0 : chapters.length - 1),
        paraIdx.clamp(0, 99999),
      );
    } catch (_) {
      return (0, 0);
    }
  }
}

class EpubReaderService {
  static EpubBookData parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Find container.xml
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      throw Exception('Invalid EPUB: META-INF/container.xml missing');
    }

    final containerDoc = html_parser.parse(utf8.decode(containerFile.content as List<int>));
    final rootfileElem = containerDoc.querySelector('rootfile');
    final opfPath = rootfileElem?.attributes['full-path'] ?? 'OEBPS/content.opf';
    final opfDir = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';

    // 2. Read OPF file
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('Invalid EPUB: OPF package document not found at $opfPath');
    }

    final opfDoc = html_parser.parse(utf8.decode(opfFile.content as List<int>));
    String title = 'Untitled Book';
    String author = 'Unknown Author';

    for (final elem in opfDoc.querySelectorAll('*')) {
      final tag = elem.localName?.toLowerCase() ?? '';
      if (tag == 'title' || tag.endsWith(':title')) {
        final t = elem.text.trim();
        if (t.isNotEmpty && title == 'Untitled Book') title = t;
      } else if (tag == 'creator' || tag.endsWith(':creator') || tag == 'author') {
        final a = elem.text.trim();
        if (a.isNotEmpty && author == 'Unknown Author') author = a;
      }
    }

    // 3. Manifest mapping: id -> href
    final manifestMap = <String, String>{};
    for (final item in opfDoc.querySelectorAll('*')) {
      final tag = item.localName?.toLowerCase() ?? '';
      if (tag == 'item' || tag.endsWith(':item')) {
        final id = item.attributes['id'];
        final href = item.attributes['href'];
        if (id != null && href != null) {
          manifestMap[id] = href;
        }
      }
    }

    // 4. TOC titles: try finding NCX or nav document
    final tocTitles = <String, String>{};
    for (final file in archive.files) {
      if (file.name.endsWith('.ncx')) {
        try {
          final ncxDoc = html_parser.parse(utf8.decode(file.content as List<int>));
          for (final navPoint in ncxDoc.querySelectorAll('*')) {
            if (navPoint.localName?.toLowerCase() == 'navpoint') {
              final textElem = navPoint.querySelector('*');
              final text = navPoint.text.trim();
              final contentElem = navPoint.querySelectorAll('*').firstWhere(
                (e) => e.localName?.toLowerCase() == 'content',
                orElse: () => dom.Element.tag('span'),
              );
              final src = contentElem.attributes['src'];
              if (text.isNotEmpty && src != null) {
                final cleanSrc = src.contains('#') ? src.substring(0, src.indexOf('#')) : src;
                tocTitles[cleanSrc] = text;
              }
            }
          }
        } catch (_) {}
      }
    }

    // 5. Spine itemrefs
    final chapters = <EpubParsedChapter>[];
    int chapterIndex = 0;

    for (final itemref in opfDoc.querySelectorAll('*')) {
      final tag = itemref.localName?.toLowerCase() ?? '';
      if (tag != 'itemref' && !tag.endsWith(':itemref')) continue;
      final idref = itemref.attributes['idref'];
      if (idref == null) continue;
      final relativeHref = manifestMap[idref];
      if (relativeHref == null) continue;

      final fullHref = opfDir.isNotEmpty ? '$opfDir$relativeHref' : relativeHref;
      final chapterFile = archive.findFile(fullHref) ?? archive.findFile(relativeHref);
      if (chapterFile == null) continue;

      String rawHtml = '';
      try {
        rawHtml = utf8.decode(chapterFile.content as List<int>);
      } catch (_) {
        rawHtml = latin1.decode(chapterFile.content as List<int>);
      }

      final chapterDoc = html_parser.parse(rawHtml);
      final body = chapterDoc.body;
      if (body == null) continue;

      // Extract paragraphs / text blocks
      final paragraphs = <String>[];
      for (final p in body.querySelectorAll('p, h1, h2, h3, h4, blockquote, div')) {
        final text = p.text.trim();
        if (text.isNotEmpty && text.length > 5 && !paragraphs.contains(text)) {
          paragraphs.add(text);
        }
      }

      final plainText = body.text.trim();
      if (plainText.isEmpty) continue;

      // Title determination
      String chapterTitle = tocTitles[relativeHref] ?? '';
      if (chapterTitle.isEmpty) {
        final heading = body.querySelector('h1, h2, h3, title')?.text.trim();
        if (heading != null && heading.isNotEmpty && heading.length < 80) {
          chapterTitle = heading;
        } else {
          chapterTitle = 'Chapter ${chapterIndex + 1}';
        }
      }

      chapters.add(EpubParsedChapter(
        index: chapterIndex,
        id: idref,
        title: chapterTitle,
        href: relativeHref,
        htmlContent: rawHtml,
        plainText: plainText,
        paragraphs: paragraphs.isNotEmpty ? paragraphs : [plainText],
      ));

      chapterIndex++;
    }

    return EpubBookData(
      title: title,
      author: author,
      chapters: chapters,
    );
  }
}
