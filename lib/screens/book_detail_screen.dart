import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../models/book_models.dart';
import '../services/books_api_client.dart';
import '../services/books_download_service.dart';
import 'audiobook_player_screen.dart';
import 'epub_reader_screen.dart';

class BookDetailScreen extends StatefulWidget {
  const BookDetailScreen({
    super.key,
    this.workId,
    this.worldwideItem,
  }) : assert(workId != null || worldwideItem != null);

  static const routeName = '/book_detail';
  final String? workId;
  final WorldwideBookResult? worldwideItem;

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late final BooksApiClient _apiClient;
  BooksDownloadService? _downloadService;
  BookDetail? _book;
  WorldwideBookResult? _worldwideItem;
  BookRequestItem? _requestItem;
  Timer? _pollTimer;
  bool _isLoading = true;
  bool _isRequesting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _apiClient = GetIt.instance<BooksApiClient>();
    if (GetIt.instance.isRegistered<BooksDownloadService>()) {
      _downloadService = GetIt.instance<BooksDownloadService>();
    }
    _worldwideItem = widget.worldwideItem;

    final targetWorkId = widget.workId ?? widget.worldwideItem?.localWorkId;
    if (targetWorkId != null && targetWorkId.isNotEmpty) {
      _loadBook(targetWorkId);
    } else if (widget.worldwideItem != null) {
      _isLoading = false;
      if (widget.worldwideItem!.requestId != null) {
        _startPollingRequest(widget.worldwideItem!.requestId!);
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBook([String? workId]) async {
    final wid = workId ?? widget.workId ?? _worldwideItem?.localWorkId;
    if (wid == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final book = await _apiClient.getBook(wid);
      if (mounted) {
        setState(() {
          _book = book;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (_downloadService != null) {
          final localDetail = await _downloadService!.getLocalBookDetail(wid);
          if (localDetail != null) {
            setState(() {
              _book = localDetail;
              _isLoading = false;
              _errorMessage = null;
            });
            return;
          }
        }
        // If this is a worldwide item not yet in library, error is expected
        if (_worldwideItem != null) {
          setState(() {
            _isLoading = false;
            _errorMessage = null;
          });
        } else {
          setState(() {
            _errorMessage = e.toString();
            _isLoading = false;
          });
        }
      }
    }
  }

  void _startPollingRequest(String reqId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final req = await _apiClient.getBookRequest(reqId);
        if (req != null && mounted) {
          setState(() {
            _requestItem = req;
          });
          if (req.isCompleted) {
            timer.cancel();
            if (req.workId != null) {
              await _loadBook(req.workId);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Book successfully acquired and ready to read/listen!'),
                  backgroundColor: Color(0xFF34C759),
                ),
              );
            }
          } else if (req.isFailed) {
            timer.cancel();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(req.errorMessage ?? 'Acquisition could not be completed'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _handleBookRequest(String format) async {
    final title = _book?.title ?? _worldwideItem?.title;
    final author = _book?.author ?? _worldwideItem?.author;
    if (title == null || author == null) return;

    setState(() => _isRequesting = true);
    try {
      final req = await _apiClient.submitBookRequest(
        title: title,
        author: author,
        isbn: _worldwideItem?.isbns.isNotEmpty == true ? _worldwideItem!.isbns.first : null,
        format: format,
      );
      if (mounted) {
        setState(() {
          _requestItem = req;
          _isRequesting = false;
        });
        _startPollingRequest(req.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Requested "$title". Searching authorized sources...'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRequesting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request failed: $e')),
        );
      }
    }
  }

  void _openReader(BuildContext context) {
    if (_book == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EpubReaderScreen(
          workId: _book!.id,
          title: _book!.title,
          author: _book!.author,
          initialCfi: _book!.progress.readingCfi,
          hasPairedAudio: _book!.hasAudiobook,
        ),
      ),
    ).then((_) => _loadBook());
  }

  void _openAudioPlayer(BuildContext context) {
    if (_book == null) return;
    final audioEd = _book!.audioEdition;
    if (audioEd == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudiobookPlayerScreen(
          book: _book!,
          audioEdition: audioEd,
        ),
      ),
    ).then((_) => _loadBook());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, size: 22),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text('Error: $_errorMessage'),
                      const SizedBox(height: 12),
                      FilledButton.tonal(onPressed: _loadBook, child: const Text('Retry')),
                    ],
                  ),
                )
              : _book == null && _worldwideItem == null
                  ? const Center(child: Text('Book not found'))
                  : _buildDetailContent(context, theme, isDark),
    );
  }

  Widget _buildDetailContent(BuildContext context, ThemeData theme, bool isDark) {
    final title = _book?.title ?? _worldwideItem!.title;
    final author = _book?.author ?? _worldwideItem!.author;
    final coverUrl = _book?.coverUrl ?? _worldwideItem?.coverUrl;
    final seriesName = _book?.seriesName;
    final description = _book?.description ?? _worldwideItem?.description;
    final hasEpub = _book?.hasEpub ?? _worldwideItem?.hasEpub ?? false;
    final hasAudiobook = _book?.hasAudiobook ?? _worldwideItem?.hasAudiobook ?? false;
    final isPaired = _book?.isPaired ?? false;
    final isOwned = _book != null;
    final activeState = _requestItem?.state ?? _worldwideItem?.requestState;
    final isAcquiring = _isRequesting || (activeState != null && !const ['available', 'failed', 'imported'].contains(activeState));

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Book Cover Hero
          Center(
            child: Container(
              width: 170,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: coverUrl != null
                    ? Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholderCover(),
                      )
                    : _buildPlaceholderCover(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Title & Author
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            author,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          if (seriesName != null) ...[
            const SizedBox(height: 4),
            Text(
              '$seriesName • Book ${_book?.seriesOrder ?? 1}',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Badges Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isOwned) ...[
                if (hasEpub)
                  _buildFormatTag('EPUB', Icons.menu_book_rounded, isDark),
                if (hasEpub && hasAudiobook)
                  const SizedBox(width: 8),
                if (hasAudiobook)
                  _buildFormatTag('AUDIOBOOK', Icons.headphones_rounded, isDark),
                if (isPaired) ...[
                  const SizedBox(width: 8),
                  _buildFormatTag('PAIRED SYNC', Icons.sync_rounded, isDark, accent: true),
                ],
              ] else if (isAcquiring) ...[
                _buildFormatTag('ACQUIRING MEDIA', Icons.sync_rounded, isDark, accent: true),
              ] else ...[
                _buildFormatTag('WORLDWIDE DISCOVERY', Icons.public_rounded, isDark),
              ],
            ],
          ),
          const SizedBox(height: 24),
          // Action Buttons
          if (isOwned) ...[
            Row(
              children: [
                if (hasEpub)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openReader(context),
                      icon: const Icon(Icons.auto_stories_rounded, size: 18),
                      label: Text(_book!.progress.readingPercentage > 0 ? 'Resume Reading' : 'Read'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFA2D48),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                if (hasEpub && hasAudiobook)
                  const SizedBox(width: 12),
                if (hasAudiobook)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openAudioPlayer(context),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(_book!.progress.listeningSeconds > 0 ? 'Resume Audio' : 'Listen'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
              ],
            ),
            if (hasEpub || hasAudiobook) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _buildDownloadButton(context, isDark),
              ),
            ],
            if (isPaired) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFA2D48).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFA2D48).withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.sync_rounded, color: Color(0xFFFA2D48), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sentence-level reading & listening synchronization enabled',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFA2D48)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else if (isAcquiring) ...[
            // Acquisition in progress card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF0F0F3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFA2D48).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFA2D48)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Server Acquisition In Progress',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stage: ${(activeState ?? "searching").toUpperCase()} • ${(_requestItem?.progressPercentage ?? 25.0).toInt()}% completed',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ((_requestItem?.progressPercentage ?? 25.0) / 100.0).clamp(0.05, 1.0),
                      color: const Color(0xFFFA2D48),
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Request Book Action
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _showRequestDialog(context, isDark),
                icon: const Icon(Icons.cloud_download_rounded, size: 20),
                label: const Text('Request Book'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFA2D48),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          // Description
          if (description != null && description.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'About this book',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 28),
          ],
          // Chapters Section (if owned)
          if (_book != null) _buildChaptersSection(theme, isDark),
          const SizedBox(height: 28),
          // Metadata Details
          _buildMetadataDetails(theme, isDark),
        ],
      ),
    );
  }

  void _showRequestDialog(BuildContext context, bool isDark) {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1B1B1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Request for Home Server',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.auto_stories_rounded, color: Color(0xFFFA2D48)),
              title: const Text('Both (Reading & Audiobook)'),
              subtitle: const Text('Acquire paired editions for reading & listening'),
              onTap: () => Navigator.of(ctx).pop('paired'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: const Text('E-Book Only'),
              subtitle: const Text('Acquire EPUB edition for reading'),
              onTap: () => Navigator.of(ctx).pop('epub'),
            ),
            ListTile(
              leading: const Icon(Icons.headphones_rounded),
              title: const Text('Audiobook Only'),
              subtitle: const Text('Acquire audiobook edition for listening'),
              onTap: () => Navigator.of(ctx).pop('audiobook'),
            ),
          ],
        ),
      ),
    ).then((selected) {
      if (selected != null) {
        _handleBookRequest(selected);
      }
    });
  }

  Widget _buildFormatTag(String label, IconData icon, bool isDark, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent
            ? const Color(0xFFFA2D48).withValues(alpha: 0.15)
            : (isDark ? const Color(0xFF26262A) : const Color(0xFFE9E9EB)),
        borderRadius: BorderRadius.circular(6),
        border: accent
            ? Border.all(color: const Color(0xFFFA2D48).withValues(alpha: 0.3), width: 0.8)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: accent ? const Color(0xFFFA2D48) : (isDark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent ? const Color(0xFFFA2D48) : (isDark ? Colors.white70 : Colors.black87),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChaptersSection(ThemeData theme, bool isDark) {
    final audioEd = _book!.audioEdition;
    final chapters = audioEd?.chapters ?? [];
    if (chapters.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Chapters (${chapters.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: chapters.take(15).length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          itemBuilder: (context, index) {
            final ch = chapters[index];
            final durationStr = ch.endSeconds != null && ch.endSeconds! > 0
                ? '${(ch.endSeconds! ~/ 60)}:${(ch.endSeconds! % 60).toInt().toString().padLeft(2, '0')}'
                : '';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(
                '${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              title: Text(
                ch.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              trailing: Text(
                durationStr,
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
              ),
              onTap: () => _openAudioPlayer(context),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetadataDetails(ThemeData theme, bool isDark) {
    final epubEd = _book?.epubEdition;
    final audioEd = _book?.audioEdition;
    final publisher = epubEd?.publisher ?? audioEd?.publisher;
    final year = epubEd?.publishedYear ?? audioEd?.publishedYear ?? _worldwideItem?.publishedYear;
    final isbn = epubEd?.isbn ?? audioEd?.isbn ?? (_worldwideItem?.isbns.isNotEmpty == true ? _worldwideItem!.isbns.first : null);
    final language = epubEd?.language ?? audioEd?.language ?? (_worldwideItem?.languages.isNotEmpty == true ? _worldwideItem!.languages.first : 'en');
    final genres = _book?.genres ?? _worldwideItem?.genres ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B1E) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (publisher != null) _buildMetaRow('Publisher', publisher, isDark),
          if (year != null) _buildMetaRow('Release Year', '$year', isDark),
          if (isbn != null) _buildMetaRow('ISBN', isbn, isDark),
          _buildMetaRow('Language', language.toUpperCase(), isDark),
          if (_worldwideItem != null && _worldwideItem!.editionCount > 1)
            _buildMetaRow('Editions', '${_worldwideItem!.editionCount} editions worldwide', isDark),
          if (genres.isNotEmpty)
            _buildMetaRow('Genres', genres.join(', '), isDark),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton(BuildContext context, bool isDark) {
    if (_downloadService == null || (!_book!.hasEpub && !_book!.hasAudiobook)) return const SizedBox.shrink();

    return ValueListenableBuilder<Set<String>>(
      valueListenable: _downloadService!.downloadedWorkIds,
      builder: (context, downloadedIds, _) {
        final isDownloaded = downloadedIds.contains(widget.workId);

        return ValueListenableBuilder<Map<String, double>>(
          valueListenable: _downloadService!.downloadProgress,
          builder: (context, progressMap, _) {
            final isDownloading = progressMap.containsKey(widget.workId);

            if (isDownloading) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1B1B1E) : const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFA2D48)),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Downloading for offline reading...',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }

            if (isDownloaded) {
              return OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remove Download'),
                      content: const Text('Do you want to delete this downloaded book from your device?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  final targetId = widget.workId ?? _book?.id;
                  if (confirmed == true && targetId != null) {
                    await _downloadService!.deleteWork(targetId);
                  }
                },
                icon: const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF34C759)),
                label: const Text('Downloaded • Remove'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : Colors.black87,
                  side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              );
            }

            return OutlinedButton.icon(
              onPressed: () async {
                try {
                  BookDownloadMode mode = BookDownloadMode.both;
                  if (_book!.hasEpub && _book!.hasAudiobook) {
                    final selected = await showModalBottomSheet<BookDownloadMode>(
                      context: context,
                      backgroundColor: isDark ? const Color(0xFF1B1B1E) : Colors.white,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 12),
                            const Text('Download Options', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 8),
                            ListTile(
                              leading: const Icon(Icons.cloud_download_rounded, color: Color(0xFFFA2D48)),
                              title: const Text('Download Both (Reading & Audiobook)'),
                              subtitle: const Text('Recommended for offline reading & listening'),
                              onTap: () => Navigator.of(ctx).pop(BookDownloadMode.both),
                            ),
                            ListTile(
                              leading: const Icon(Icons.menu_book_rounded),
                              title: const Text('EPUB Only'),
                              onTap: () => Navigator.of(ctx).pop(BookDownloadMode.epubOnly),
                            ),
                            ListTile(
                              leading: const Icon(Icons.headphones_rounded),
                              title: const Text('Audiobook Only'),
                              onTap: () => Navigator.of(ctx).pop(BookDownloadMode.audioOnly),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (selected == null) return;
                    mode = selected;
                  } else if (_book!.hasEpub) {
                    mode = BookDownloadMode.epubOnly;
                  } else {
                    mode = BookDownloadMode.audioOnly;
                  }

                  final targetId = widget.workId ?? _book?.id;
                  if (targetId != null) {
                    await _downloadService!.downloadWork(targetId, mode: mode, bookDetail: _book);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Book downloaded for offline use')),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Download failed: $e')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.arrow_downward_rounded, size: 18),
              label: Text(_book!.hasEpub && _book!.hasAudiobook
                  ? 'Download for Offline Use'
                  : (_book!.hasEpub ? 'Download for Offline Reading' : 'Download for Offline Listening')),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white70 : Colors.black87,
                side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.book, size: 48, color: Colors.white38),
            const SizedBox(height: 8),
            Text(
              _book?.title ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
