import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../models/book_models.dart';
import '../services/books_api_client.dart';
import '../services/books_download_service.dart';
import '../services/epub_reader_service.dart';
import 'audiobook_player_screen.dart';

enum ReadingTheme { dark, light, sepia }

class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({
    super.key,
    required this.workId,
    required this.title,
    required this.author,
    this.initialCfi,
    this.hasPairedAudio = false,
  });

  static const routeName = '/epub_reader';
  final String workId;
  final String title;
  final String author;
  final String? initialCfi;
  final bool hasPairedAudio;

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  late final BooksApiClient _apiClient;
  final ScrollController _scrollController = ScrollController();

  EpubBookData? _bookData;
  bool _isLoading = true;
  String? _errorMessage;

  int _currentChapterIndex = 0;
  double _fontSize = 17.0;
  double _lineHeight = 1.6;
  ReadingTheme _theme = ReadingTheme.dark;
  String _fontFamily = 'System'; // 'System', 'Serif', 'Monospace'

  bool _showControls = true;
  bool _isBookmarked = false;
  bool _readAlongEnabled = true;
  String? _activeHighlightCfi;
  int _highlightedParagraphIndex = -1;

  @override
  void initState() {
    super.initState();
    _apiClient = GetIt.instance<BooksApiClient>();
    _scrollController.addListener(_onScroll);
    _loadEpub();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEpub() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Uint8List? bytes;
      if (GetIt.instance.isRegistered<BooksDownloadService>()) {
        final downloadService = GetIt.instance<BooksDownloadService>();
        if (downloadService.isDownloaded(widget.workId)) {
          bytes = await downloadService.getLocalEpubBytes(widget.workId);
        }
      }
      bytes ??= await _apiClient.downloadEpub(widget.workId);
      final parsed = EpubReaderService.parse(bytes);

      int targetChapter = 0;
      int targetParagraph = 0;
      if (widget.initialCfi != null) {
        final (chIdx, pIdx) = parsed.parseCfi(widget.initialCfi);
        targetChapter = chIdx;
        targetParagraph = pIdx;
        _activeHighlightCfi = widget.initialCfi;
        _highlightedParagraphIndex = pIdx;
      }

      if (mounted) {
        setState(() {
          _bookData = parsed;
          _currentChapterIndex = targetChapter;
          _isLoading = false;
        });

        if (targetParagraph > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final totalParas = parsed.chapters[targetChapter].paragraphs.length;
              if (totalParas > 0) {
                final ratio = (targetParagraph / totalParas).clamp(0.0, 1.0);
                final targetOffset = ratio * _scrollController.position.maxScrollExtent;
                _scrollController.jumpTo(targetOffset);
              }
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onScroll() {
    if (_bookData == null || _bookData!.chapters.isEmpty) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll <= 0) return;

    final progressRatio = (currentScroll / maxScroll).clamp(0.0, 1.0);
    final overallProgress = ((_currentChapterIndex + progressRatio) / _bookData!.chapters.length).clamp(0.0, 1.0);

    final totalParas = _bookData!.chapters[_currentChapterIndex].paragraphs.length;
    final paraIdx = totalParas > 0 ? (progressRatio * totalParas).floor() : 0;
    final cfi = _bookData!.makeCfi(_currentChapterIndex, paraIdx);
    _saveProgress(cfi, overallProgress);
  }

  Future<void> _saveProgress(String cfi, double percentage) async {
    try {
      await _apiClient.updateProgress(
        widget.workId,
        readingCfi: cfi,
        readingPercentage: percentage,
        activeFormat: 'reading',
      );
    } catch (_) {}
  }

  void _goToChapter(int chapterIndex) {
    if (_bookData == null || chapterIndex < 0 || chapterIndex >= _bookData!.chapters.length) return;
    setState(() {
      _currentChapterIndex = chapterIndex;
    });
    _scrollController.jumpTo(0);

    final cfi = _bookData!.makeCfi(_currentChapterIndex, 0);
    final pct = (_currentChapterIndex / _bookData!.chapters.length).clamp(0.0, 1.0);
    _saveProgress(cfi, pct);
  }

  Color get _backgroundColor {
    switch (_theme) {
      case ReadingTheme.dark:
        return const Color(0xFF000000);
      case ReadingTheme.light:
        return const Color(0xFFFFFFFF);
      case ReadingTheme.sepia:
        return const Color(0xFFF7F1E3);
    }
  }

  Color get _textColor {
    switch (_theme) {
      case ReadingTheme.dark:
        return const Color(0xFFE2E2E6);
      case ReadingTheme.light:
        return const Color(0xFF1C1C1E);
      case ReadingTheme.sepia:
        return const Color(0xFF433422);
    }
  }

  TextStyle get _bodyTextStyle {
    TextStyle style = TextStyle(fontSize: _fontSize, height: _lineHeight, color: _textColor, letterSpacing: -0.1);
    if (_fontFamily == 'Serif') {
      style = style.copyWith(fontFamily: 'Georgia');
    } else if (_fontFamily == 'Monospace') {
      style = style.copyWith(fontFamily: 'Courier');
    }
    return style;
  }

  void _showAppearanceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _theme == ReadingTheme.dark ? const Color(0xFF1E1E22) : const Color(0xFFF2F2F7),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Themes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildThemeOption(
                        'Dark',
                        ReadingTheme.dark,
                        const Color(0xFF000000),
                        Colors.white,
                        setSheetState,
                      ),
                      const SizedBox(width: 12),
                      _buildThemeOption(
                        'Sepia',
                        ReadingTheme.sepia,
                        const Color(0xFFF7F1E3),
                        const Color(0xFF433422),
                        setSheetState,
                      ),
                      const SizedBox(width: 12),
                      _buildThemeOption(
                        'Light',
                        ReadingTheme.light,
                        const Color(0xFFFFFFFF),
                        Colors.black,
                        setSheetState,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Text Size', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.remove_rounded),
                        onPressed: _fontSize > 13
                            ? () {
                                setState(() => _fontSize -= 1.0);
                                setSheetState(() {});
                              }
                            : null,
                      ),
                      Expanded(
                        child: Center(
                          child: Text('${_fontSize.toInt()} pt', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.add_rounded),
                        onPressed: _fontSize < 28
                            ? () {
                                setState(() => _fontSize += 1.0);
                                setSheetState(() {});
                              }
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThemeOption(String label, ReadingTheme theme, Color bg, Color text, StateSetter setSheetState) {
    final isSelected = _theme == theme;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _theme = theme);
          setSheetState(() {});
        },
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? const Color(0xFFFA2D48) : Colors.white24, width: isSelected ? 2 : 1),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }

  void _showTocSheet() {
    if (_bookData == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _backgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, controller) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _textColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        'Contents',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _textColor),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: _bookData!.chapters.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: _textColor.withValues(alpha: 0.1)),
                    itemBuilder: (context, idx) {
                      final ch = _bookData!.chapters[idx];
                      final isSelected = idx == _currentChapterIndex;
                      return ListTile(
                        title: Text(
                          ch.title,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFFFA2D48) : _textColor,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: Color(0xFFFA2D48), size: 18)
                            : null,
                        onTap: () {
                          Navigator.of(context).pop();
                          _goToChapter(idx);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleListenFromHere(BuildContext context) async {
    if (_bookData == null) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final progressRatio = maxScroll > 0 ? (currentScroll / maxScroll).clamp(0.0, 1.0) : 0.0;
    final totalParas = _bookData!.chapters[_currentChapterIndex].paragraphs.length;
    final paraIdx = totalParas > 0 ? (progressRatio * totalParas).floor() : 0;
    final cfi = _bookData!.makeCfi(_currentChapterIndex, paraIdx);

    int mappedTrack = _currentChapterIndex + 1;
    double mappedSec = 0.0;

    try {
      final aud = await _apiClient.mapReadingLocationToAudio(widget.workId, cfi: cfi);
      if (aud != null && aud['audio_track'] != null) {
        mappedTrack = (aud['audio_track'] as num).toInt();
        mappedSec = (aud['audio_timestamp_seconds'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}

    BookDetail? book;
    if (GetIt.instance.isRegistered<BooksDownloadService>()) {
      final ds = GetIt.instance<BooksDownloadService>();
      book = await ds.getLocalBookDetail(widget.workId);
    }
    if (book == null) {
      try {
        book = await _apiClient.getBook(widget.workId);
      } catch (_) {}
    }

    if (mappedSec == 0.0 && book?.alignment != null) {
      final align = book!.alignment!;
      if (align['mapping_data'] is List) {
        for (final item in align['mapping_data'] as List) {
          if (item is Map<String, dynamic> && item['epub_cfi'] == cfi) {
            mappedTrack = (item['audio_track'] as num?)?.toInt() ?? mappedTrack;
            mappedSec = (item['audio_start_sec'] as num?)?.toDouble() ?? 0.0;
            break;
          }
        }
      }
    }

    if (book == null || book.audioEdition == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audiobook edition not available')));
      }
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AudiobookPlayerScreen(
          book: book!,
          audioEdition: book.audioEdition!,
          initialTrack: mappedTrack,
          initialPosition: Duration(seconds: mappedSec.toInt()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_errorMessage != null || _bookData == null || _bookData!.chapters.isEmpty) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_rounded, size: 48, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text('Could not open book: $_errorMessage', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.tonal(onPressed: _loadEpub, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final currentChapter = _bookData!.chapters[_currentChapterIndex];

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            // Chapter Content
            SafeArea(
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      currentChapter.title,
                      style: TextStyle(
                        fontSize: _fontSize + 8,
                        fontWeight: FontWeight.w800,
                        color: _textColor,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ...currentChapter.paragraphs.asMap().entries.map((entry) {
                      final pIdx = entry.key;
                      final pText = entry.value;
                      final isHighlighted =
                          _readAlongEnabled &&
                          (_highlightedParagraphIndex == pIdx ||
                              (_activeHighlightCfi != null &&
                                  _bookData!.makeCfi(_currentChapterIndex, pIdx) == _activeHighlightCfi));

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          decoration: isHighlighted
                              ? BoxDecoration(
                                  color: const Color(0xFFFA2D48).withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFFA2D48).withValues(alpha: 0.35)),
                                )
                              : null,
                          padding: isHighlighted
                              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                              : EdgeInsets.zero,
                          child: Text(pText, style: _bodyTextStyle),
                        ),
                      );
                    }),
                    const SizedBox(height: 48),
                    // Chapter navigation controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (_currentChapterIndex > 0)
                          TextButton.icon(
                            onPressed: () => _goToChapter(_currentChapterIndex - 1),
                            icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                            label: const Text('Previous Chapter'),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFA2D48)),
                          )
                        else
                          const SizedBox.shrink(),
                        if (_currentChapterIndex < _bookData!.chapters.length - 1)
                          TextButton.icon(
                            onPressed: () => _goToChapter(_currentChapterIndex + 1),
                            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                            label: const Text('Next Chapter'),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFA2D48)),
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            // Top Bar Controls
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: _backgroundColor.withValues(alpha: 0.95),
                  padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, bottom: 8, left: 12, right: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _textColor),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: _textColor, fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            Text(
                              currentChapter.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: _textColor.withValues(alpha: 0.6), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (widget.hasPairedAudio) ...[
                        IconButton(
                          tooltip: _readAlongEnabled ? 'Disable Read-Along Highlight' : 'Enable Read-Along Highlight',
                          icon: Icon(
                            _readAlongEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                            color: _readAlongEnabled ? const Color(0xFFFA2D48) : _textColor,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _readAlongEnabled = !_readAlongEnabled),
                        ),
                        IconButton(
                          tooltip: 'Listen From Here',
                          icon: const Icon(Icons.headphones_rounded, color: Color(0xFFFA2D48), size: 20),
                          onPressed: () => _handleListenFromHere(context),
                        ),
                      ],
                      IconButton(
                        icon: Icon(
                          _isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          color: _isBookmarked ? const Color(0xFFFA2D48) : _textColor,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _isBookmarked = !_isBookmarked),
                      ),
                      IconButton(
                        icon: Icon(Icons.format_size_rounded, color: _textColor, size: 20),
                        onPressed: _showAppearanceSheet,
                      ),
                      IconButton(
                        icon: Icon(Icons.list_rounded, color: _textColor, size: 22),
                        onPressed: _showTocSheet,
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom Progress Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 6,
                  top: 6,
                  left: 20,
                  right: 20,
                ),
                color: _backgroundColor.withValues(alpha: 0.9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Chapter ${_currentChapterIndex + 1} of ${_bookData!.chapters.length}',
                      style: TextStyle(fontSize: 11, color: _textColor.withValues(alpha: 0.5)),
                    ),
                    Text(
                      '${((_currentChapterIndex + 1) / _bookData!.chapters.length * 100).toInt()}%',
                      style: TextStyle(fontSize: 11, color: _textColor.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
