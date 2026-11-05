import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';

import '../models/book_models.dart';
import '../services/books_api_client.dart';
import '../services/books_download_service.dart';
import '../services/catalog_credential_store.dart';
import '../services/music_player_background_task.dart';
import 'epub_reader_screen.dart';

class AudiobookPlayerScreen extends StatefulWidget {
  const AudiobookPlayerScreen({
    super.key,
    required this.book,
    required this.audioEdition,
    this.initialTrack,
    this.initialPosition,
  });

  static const routeName = '/audiobook_player';

  final BookDetail book;
  final BookEdition audioEdition;
  final int? initialTrack;
  final Duration? initialPosition;

  @override
  State<AudiobookPlayerScreen> createState() => _AudiobookPlayerScreenState();
}

class _AudiobookPlayerScreenState extends State<AudiobookPlayerScreen> {
  late final BooksApiClient _apiClient;
  late final AudioPlayer _player;

  int _currentChapterIndex = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _initialSeekDone = false;
  double _speed = 1.0;
  Timer? _sleepTimer;
  int? _sleepTimerMinutes;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _apiClient = GetIt.instance<BooksApiClient>();
    _player = AudioPlayer();

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // Pause background music player if active to prevent dual audio collision
    if (GetIt.instance.isRegistered<MusicPlayerBackgroundTask>()) {
      try {
        final musicHandler = GetIt.instance<MusicPlayerBackgroundTask>();
        if (musicHandler.playbackState.value.playing) {
          unawaited(musicHandler.pause());
        }
      } catch (_) {}
    }

    _posSub = _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
      _saveProgress(pos);
    });
    _durSub = _player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _duration = dur);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        _nextChapterOrTrack();
      }
    });

    final chapters = widget.audioEdition.chapters;
    if (widget.initialTrack != null && widget.initialTrack! > 0) {
      _currentChapterIndex = (widget.initialTrack! - 1).clamp(0, chapters.isNotEmpty ? chapters.length - 1 : 0);
    } else if (chapters.isNotEmpty) {
      _currentChapterIndex = 0;
    }

    if (chapters.isNotEmpty && _currentChapterIndex < chapters.length) {
      final ch = chapters[_currentChapterIndex];
      if (ch.endSeconds != null && ch.endSeconds! > 0) {
        _duration = Duration(seconds: ch.endSeconds!.toInt());
      }
    }

    // Set initial position if provided or saved progress exists
    if (widget.initialPosition != null) {
      _position = widget.initialPosition!;
    } else if (widget.book.progress.listeningSeconds > 0) {
      _position = Duration(seconds: widget.book.progress.listeningSeconds.toInt());
    }

    await _loadTrack(_currentChapterIndex);
  }

  Future<void> _loadTrack(int chapterIndex) async {
    final trackNum = chapterIndex + 1;
    final downloadService = GetIt.instance.isRegistered<BooksDownloadService>()
        ? GetIt.instance<BooksDownloadService>()
        : null;

    try {
      final offlineFile = await downloadService?.getLocalAudioFile(widget.book.id, trackNum);
      if (offlineFile != null && await offlineFile.exists()) {
        await _player.setFilePath(offlineFile.path);
      } else {
        final credStore = GetIt.instance.isRegistered<CatalogCredentialStore>()
            ? GetIt.instance<CatalogCredentialStore>()
            : null;
        final creds = await credStore?.read();
        final endpoint = creds?.endpoint.toString() ?? 'http://127.0.0.1:8765';
        final uri = Uri.parse('$endpoint/v1/books/${widget.book.id}/audio/$trackNum');
        await _player.setAudioSource(
          AudioSource.uri(uri, headers: creds != null ? {'Authorization': 'Bearer ${creds.token}'} : null),
        );
      }

      if (!_initialSeekDone) {
        if (widget.initialPosition != null) {
          await _player.seek(widget.initialPosition!);
          _initialSeekDone = true;
        } else if (widget.book.progress.listeningSeconds > 0) {
          await _player.seek(Duration(seconds: widget.book.progress.listeningSeconds.toInt()));
          _initialSeekDone = true;
        }
      }
    } catch (e) {
      debugPrint('Audio track load error: $e');
    }
  }

  Future<void> _nextChapterOrTrack() async {
    final chapters = widget.audioEdition.chapters;
    if (_currentChapterIndex < chapters.length - 1) {
      setState(() => _currentChapterIndex++);
      await _loadTrack(_currentChapterIndex);
      await _player.play();
    }
  }

  Future<void> _prevChapterOrTrack() async {
    if (_currentChapterIndex > 0) {
      setState(() => _currentChapterIndex--);
      await _loadTrack(_currentChapterIndex);
      await _player.play();
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _sleepTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _saveProgress(Duration pos) {
    if (_duration.inSeconds <= 0) return;
    final pct = (pos.inSeconds / _duration.inSeconds).clamp(0.0, 1.0);
    _apiClient.updateProgress(
      widget.book.id,
      listeningSeconds: pos.inSeconds.toDouble(),
      listeningPercentage: pct,
      activeFormat: 'listening',
    );
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _skip(int seconds) async {
    final newPos = _position + Duration(seconds: seconds);
    final clamped = newPos < Duration.zero ? Duration.zero : (newPos > _duration ? _duration : newPos);
    await _player.seek(clamped);
    _saveProgress(clamped);
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _player.setSpeed(speed);
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepTimerMinutes = minutes);
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _sleepTimerMinutes = null;
        });
        _player.pause();
      }
    });
  }

  Future<void> _openReaderHandoff(BuildContext context) async {
    if (!widget.book.hasEpub) return;
    unawaited(_player.pause());

    String? targetCfi = widget.book.progress.readingCfi;
    final trackNum = _currentChapterIndex + 1;
    final currentSec = _position.inSeconds.toDouble();

    // 1. Try server forced alignment mapping
    try {
      final loc = await _apiClient.mapAudioToReadingLocation(widget.book.id, track: trackNum, seconds: currentSec);
      if (loc != null && loc['epub_cfi'] != null) {
        targetCfi = loc['epub_cfi'] as String;
      }
    } catch (_) {}

    // 2. Fall back to local alignment if server call failed or returned null
    if (targetCfi == null || targetCfi == widget.book.progress.readingCfi) {
      final align = widget.book.alignment;
      if (align != null && align['mapping_data'] is List) {
        final list = align['mapping_data'] as List;
        Map<String, dynamic>? bestMatch;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final t = (item['audio_track'] as num?)?.toInt() ?? 1;
            if (t != trackNum) continue;
            final startSec = (item['audio_start_sec'] as num?)?.toDouble() ?? 0.0;
            if (startSec <= currentSec) {
              bestMatch = item;
            } else {
              break;
            }
          }
        }
        if (bestMatch != null && bestMatch['epub_cfi'] != null) {
          targetCfi = bestMatch['epub_cfi'] as String;
        }
      }
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EpubReaderScreen(
          workId: widget.book.id,
          title: widget.book.title,
          author: widget.book.author,
          initialCfi: targetCfi,
          hasPairedAudio: true,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chapters = widget.audioEdition.chapters;
    final currentChapter = chapters.isNotEmpty && _currentChapterIndex < chapters.length
        ? chapters[_currentChapterIndex]
        : null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (widget.book.hasEpub)
            TextButton.icon(
              icon: const Icon(Icons.auto_stories_rounded, size: 16),
              label: const Text('Read From Here', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFFA2D48)),
              onPressed: () => _openReaderHandoff(context),
            ),
          IconButton(icon: const Icon(Icons.more_horiz_rounded, size: 22), onPressed: () {}),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Column(
            children: [
              const Spacer(flex: 1),
              // Large Cover Art
              Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.25),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: widget.book.coverUrl != null
                        ? Image.network(
                            widget.book.coverUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                ),
              ),
              const Spacer(flex: 1),
              // Title & Author & Chapter
              Text(
                widget.book.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
              const SizedBox(height: 4),
              Text(
                widget.book.author,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                currentChapter?.title ?? 'Chapter ${_currentChapterIndex + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFFA2D48)),
              ),
              const Spacer(flex: 1),
              // Scrubber
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: const Color(0xFFFA2D48),
                  inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                  thumbColor: const Color(0xFFFA2D48),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: _position.inSeconds.toDouble().clamp(
                    0.0,
                    _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0,
                  ),
                  max: _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0,
                  onChanged: (val) {
                    setState(() => _position = Duration(seconds: val.toInt()));
                  },
                  onChangeEnd: (val) async {
                    final target = Duration(seconds: val.toInt());
                    await _player.seek(target);
                    _saveProgress(target);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                    ),
                    Text(
                      '-${_formatDuration(_duration - _position)}',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 1),
              // Main playback controls (15s back, Play/Pause, 30s fwd)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(iconSize: 36, icon: const Icon(Icons.replay_10_rounded), onPressed: () => _skip(-15)),
                  const SizedBox(width: 24),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(color: Color(0xFFFA2D48), shape: BoxShape.circle),
                    child: IconButton(
                      iconSize: 38,
                      color: Colors.white,
                      icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      onPressed: _togglePlayPause,
                    ),
                  ),
                  const SizedBox(width: 24),
                  IconButton(iconSize: 36, icon: const Icon(Icons.forward_10_rounded), onPressed: () => _skip(30)),
                ],
              ),
              const Spacer(flex: 1),
              // Secondary controls: Speed & Sleep Timer & Chapters
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      final speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
                      final nextIdx = (speeds.indexOf(_speed) + 1) % speeds.length;
                      _setSpeed(speeds[nextIdx]);
                    },
                    child: Text('${_speed}x', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.bedtime_rounded,
                      color: _sleepTimerMinutes != null ? const Color(0xFFFA2D48) : null,
                    ),
                    onPressed: () => _setSleepTimer(_sleepTimerMinutes == null ? 30 : 0),
                  ),
                  IconButton(icon: const Icon(Icons.list_rounded, size: 24), onPressed: _showChaptersSheet),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showChaptersSheet() {
    final chapters = widget.audioEdition.chapters;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1B1B1E) : Colors.white,
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
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        'Chapters (${chapters.length})',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: chapters.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
                    itemBuilder: (context, idx) {
                      final ch = chapters[idx];
                      final isSelected = idx == _currentChapterIndex;
                      final durSec = (ch.endSeconds ?? 0) - (ch.startSeconds ?? 0);
                      final durStr = durSec > 0
                          ? '${(durSec ~/ 60)}:${(durSec % 60).toInt().toString().padLeft(2, '0')}'
                          : '';

                      return ListTile(
                        leading: Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? const Color(0xFFFA2D48) : (isDark ? Colors.white38 : Colors.black38),
                          ),
                        ),
                        title: Text(
                          ch.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFFFA2D48) : null,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (durStr.isNotEmpty)
                              Text(
                                durStr,
                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                              ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.volume_up_rounded, color: Color(0xFFFA2D48), size: 18),
                            ],
                          ],
                        ),
                        onTap: () async {
                          Navigator.of(context).pop();
                          setState(() => _currentChapterIndex = idx);
                          await _loadTrack(idx);
                          await _player.play();
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

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: const Center(child: Icon(Icons.headphones_rounded, size: 64, color: Colors.white38)),
    );
  }
}
