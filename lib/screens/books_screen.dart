import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../models/book_models.dart';
import '../services/books_api_client.dart';
import '../services/books_download_service.dart';
import 'book_detail_screen.dart';
import 'catalog_settings_screen.dart';

class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  static const routeName = '/books';

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  late final BooksApiClient _apiClient;
  BooksDownloadService? _downloadService;
  final TextEditingController _searchController = TextEditingController();

  List<BookSummary> _allBooks = [];
  bool _isLoading = true;
  bool _isOffline = false;
  String? _errorMessage;
  String _activeFilter = 'all'; // 'all', 'epub', 'audiobook'

  // Worldwide discovery search state
  bool _isSearching = false;
  bool _isSearchLoading = false;
  List<WorldwideBookResult> _searchResults = [];
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _apiClient = GetIt.instance<BooksApiClient>();
    if (GetIt.instance.isRegistered<BooksDownloadService>()) {
      _downloadService = GetIt.instance<BooksDownloadService>();
    }
    const initQuery = String.fromEnvironment('INITIAL_BOOK_QUERY', defaultValue: '');
    if (initQuery.isNotEmpty) {
      _searchController.text = initQuery;
      _performWorldwideSearch(initQuery);
    } else {
      _loadBooks();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final books = await _apiClient.getBooks(
        query: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        formatFilter: _activeFilter == 'all' ? null : _activeFilter,
      );
      if (mounted) {
        setState(() {
          _allBooks = books;
          _isLoading = false;
          _isOffline = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (_downloadService != null) {
          final offlineBooks = await _downloadService!.listDownloadedBooks();
          if (offlineBooks.isNotEmpty) {
            setState(() {
              _allBooks = offlineBooks;
              _isLoading = false;
              _isOffline = true;
              _errorMessage = null;
            });
            return;
          }
        }
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  bool _isCredentialsMissingError(String msg) {
    return msg.contains('not configured or disabled') ||
        msg.contains('BooksNotConfiguredException');
  }

  Future<void> _performWorldwideSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _searchError = null;
      });
      _loadBooks();
      return;
    }

    setState(() {
      _isSearching = true;
      _isSearchLoading = true;
      _searchError = null;
    });

    try {
      final results = await _apiClient.searchWorldwideBooks(
        query: trimmed,
        formatFilter: _activeFilter == 'all' ? null : _activeFilter,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearchLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = e.toString();
          _isSearchLoading = false;
        });
      }
    }
  }

  List<BookSummary> get _continueBooks {
    return _allBooks.where((b) => b.progress.hasProgress && !b.progress.isFinished).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadBooks,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Books',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              fontSize: 34,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            tooltip: 'Catalog & Books Connection',
                            onPressed: () => Navigator.of(context)
                                .pushNamed(CatalogSettingsScreen.routeName)
                                .then((_) => _loadBooks()),
                          ),
                        ],
                      ),
                      if (_isOffline) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_rounded, size: 14, color: Colors.amber),
                              SizedBox(width: 6),
                              Text(
                                'Offline Library',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Search bar
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFE9E9EB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onSubmitted: (query) => _performWorldwideSearch(query),
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(fontSize: 15),
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty || _isSearching
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _isSearching = false;
                                        _searchResults = [];
                                        _searchError = null;
                                      });
                                      _loadBooks();
                                    },
                                  )
                                : null,
                            hintText: 'Search library & worldwide books',
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', 'all'),
                            const SizedBox(width: 8),
                            _buildFilterChip('E-Books', 'epub'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Audiobooks', 'audiobook'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_isSearching) ...[
                if (_isSearchLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2),
                          SizedBox(height: 14),
                          Text('Searching worldwide catalog...', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  )
                else if (_searchError != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                            const SizedBox(height: 12),
                            Text(
                              'Search error',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _searchError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: () => _performWorldwideSearch(_searchController.text),
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (_searchResults.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.travel_explore_rounded,
                            size: 56,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No Worldwide Books Found',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try searching by title, author, or ISBN',
                            style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Row(
                        children: [
                          Text(
                            'Worldwide Results (${_searchResults.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _isSearching = false;
                                _searchResults = [];
                              });
                              _loadBooks();
                            },
                            child: const Text('Clear', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (MediaQuery.of(context).size.width / 180).clamp(2, 6).toInt(),
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 20,
                        childAspectRatio: 0.58,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = _searchResults[index];
                          return _buildWorldwideGridTile(context, item, isDark);
                        },
                        childCount: _searchResults.length,
                      ),
                    ),
                  ),
                ],
              ] else if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _isCredentialsMissingError(_errorMessage!)
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.auto_stories_rounded,
                                    size: 48,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Connect Books & Catalog',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 320),
                                  child: Text(
                                    'Connect your personal library server to browse, read, and listen to books.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: theme.textTheme.bodySmall?.color,
                                      fontSize: 14,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  icon: const Icon(Icons.settings_ethernet_rounded, size: 18),
                                  label: const Text('Configure Connection'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () => Navigator.of(context)
                                      .pushNamed(CatalogSettingsScreen.routeName)
                                      .then((_) => _loadBooks()),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                                const SizedBox(height: 12),
                                Text(
                                  'Unable to load books',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 13),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: _loadBooks,
                                      child: const Text('Try Again'),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton(
                                      onPressed: () => Navigator.of(context)
                                          .pushNamed(CatalogSettingsScreen.routeName)
                                          .then((_) => _loadBooks()),
                                      child: const Text('Settings'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ),
                )
              else if (_allBooks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: 56,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No Books Found',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your synced books and audiobooks will appear here.',
                          style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                // Continue Section
                if (_continueBooks.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            'Continue',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 156,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _continueBooks.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final book = _continueBooks[index];
                          return _buildContinueCard(context, book, isDark);
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],

                // My Books Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      'My Books',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: (MediaQuery.of(context).size.width / 180).clamp(2, 6).toInt(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 20,
                      childAspectRatio: 0.58,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final book = _allBooks[index];
                        return _buildBookGridTile(context, book, isDark);
                      },
                      childCount: _allBooks.length,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _activeFilter == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        setState(() => _activeFilter = value);
        if (_isSearching && _searchController.text.trim().isNotEmpty) {
          _performWorldwideSearch(_searchController.text.trim());
        } else {
          _loadBooks();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? const Color(0xFF1E1E22) : const Color(0xFFEFEFF1)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.black : Colors.white)
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueCard(BuildContext context, BookSummary book, bool isDark) {
    final prog = book.progress;
    final percent = prog.lastActiveFormat == 'listening'
        ? prog.listeningPercentage
        : prog.readingPercentage;
    final formatLabel = prog.lastActiveFormat == 'listening' ? 'Listening' : 'Reading';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookDetailScreen(workId: book.id)),
      ),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1B1E) : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 76,
                height: 110,
                child: book.coverUrl != null
                    ? Image.network(
                        book.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildCoverPlaceholder(book),
                      )
                    : _buildCoverPlaceholder(book),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(
                        prog.lastActiveFormat == 'listening'
                            ? Icons.headphones_rounded
                            : Icons.auto_stories_rounded,
                        size: 13,
                        color: const Color(0xFFFA2D48),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatLabel.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFA2D48),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                  const Spacer(),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: percent.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFA2D48)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(percent * 100).toInt()}% completed',
                    style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookGridTile(BuildContext context, BookSummary book, bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookDetailScreen(workId: book.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: book.coverUrl != null
                      ? Image.network(
                          book.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildCoverPlaceholder(book),
                        )
                      : _buildCoverPlaceholder(book),
                ),
                // Badges for formats
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (book.hasEpub)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'EPUB',
                            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      if (book.hasAudiobook)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFA2D48).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'AUDIO',
                            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_downloadService != null)
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: _downloadService!.downloadedWorkIds,
                    builder: (context, downloadedIds, _) {
                      if (!downloadedIds.contains(book.id)) return const SizedBox.shrink();
                      return Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_downward_rounded,
                            color: Color(0xFFFA2D48),
                            size: 11,
                          ),
                        ),
                      );
                    },
                  ),
                if (book.progress.hasProgress)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                      child: LinearProgressIndicator(
                        value: (book.progress.lastActiveFormat == 'listening'
                                ? book.progress.listeningPercentage
                                : book.progress.readingPercentage)
                            .clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: Colors.black26,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFA2D48)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverPlaceholder(BookSummary book) {
    return Container(
      color: const Color(0xFF2C2C2E),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.book, size: 28, color: Colors.white38),
            const SizedBox(height: 6),
            Text(
              book.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorldwideGridTile(BuildContext context, WorldwideBookResult item, bool isDark) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookDetailScreen(
              workId: item.localWorkId,
              worldwideItem: item,
            ),
          ),
        );
        if (mounted && _searchController.text.trim().isNotEmpty) {
          _performWorldwideSearch(_searchController.text.trim());
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: item.coverUrl != null
                      ? Image.network(
                          item.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildWorldwidePlaceholder(item),
                        )
                      : _buildWorldwidePlaceholder(item),
                ),
                // Status Badge (Top-Left)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _buildStatusBadge(item),
                ),
                // Owned format tags
                if (item.isLocal && item.ownedFormats.isNotEmpty)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.ownedFormats.contains('epub'))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            margin: const EdgeInsets.only(left: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('EPUB', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        if (item.ownedFormats.contains('audiobook'))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            margin: const EdgeInsets.only(left: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFA2D48).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('AUDIO', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            item.publishedYear != null ? '${item.author} • ${item.publishedYear}' : item.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(WorldwideBookResult item) {
    if (item.isLocal) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF34C759).withValues(alpha: 0.92), // Apple Green
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Text(
          'IN LIBRARY',
          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      );
    }

    if (item.requestId != null && item.requestState != null && item.requestState != 'available') {
      final state = item.requestState!;
      String label = 'REQUESTED';
      Color bgColor = Colors.blueAccent;

      if (state == 'acquiring') {
        label = 'ACQUIRING ${(item.acquisitionProgress * 100).toInt()}%';
        bgColor = Colors.amber.shade700;
      } else if (state == 'staging' || state == 'verifying' || state == 'importing') {
        label = state.toUpperCase();
        bgColor = Colors.deepPurpleAccent;
      } else if (state == 'failed') {
        label = 'FAILED';
        bgColor = Colors.redAccent;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        'WORLDWIDE',
        style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.3),
      ),
    );
  }

  Widget _buildWorldwidePlaceholder(WorldwideBookResult item) {
    return Container(
      color: const Color(0xFF2C2C2E),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.travel_explore_rounded, size: 28, color: Colors.white38),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
