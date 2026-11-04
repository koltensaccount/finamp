import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';

import '../models/book_models.dart';
import '../services/books_api_client.dart';
import 'epub_reader_screen.dart';

class AudiobookPlayerScreen extends StatefulWidget {
  const AudiobookPlayerScreen({
    super.key,
    required this.book,
    required this.audioEdition,
  });

  final BookDetail book;
  final BookEdition audioEdition;

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
    _posSub = _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
      _saveProgress(pos);
    });
    _durSub = _player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _duration = dur);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });

    final chapters = widget.audioEdition.chapters;
    if (chapters.isNotEmpty) {
      _currentChapterIndex = 0;
      final ch = chapters[0];
      if (ch.endSeconds != null && ch.endSeconds! > 0) {
        _duration = Duration(seconds: ch.endSeconds!.toInt());
      }
    }

    // Set initial position if saved progress exists
    if (widget.book.progress.listeningSeconds > 0) {
      _position = Duration(seconds: widget.book.progress.listeningSeconds.toInt());
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

  void _togglePlayPause() {
    setState(() => _isPlaying = !_isPlaying);
  }

  void _skip(int seconds) {
    final newPos = _position + Duration(seconds: seconds);
    final clamped = newPos < Duration.zero
        ? Duration.zero
        : (newPos > _duration ? _duration : newPos);
    setState(() => _position = clamped);
    _saveProgress(clamped);
  }

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    _player.setSpeed(speed);
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

  void _openReaderHandoff(BuildContext context) {
    if (!widget.book.hasEpub) return;
    String? targetCfi = widget.book.progress.readingCfi;

    final align = widget.book.alignment;
    if (align != null && align['mapping_data'] is List) {
      final list = align['mapping_data'] as List;
      final currentSec = _position.inSeconds.toDouble();
      Map<String, dynamic>? bestMatch;
      for (final item in list) {
        if (item is Map<String, dynamic>) {
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
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, size: 22),
            onPressed: () {},
          ),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFA2D48),
                ),
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
                  value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0),
                  max: _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0,
                  onChanged: (val) {
                    setState(() => _position = Duration(seconds: val.toInt()));
                    _saveProgress(_position);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(_position), style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                    Text('-${_formatDuration(_duration - _position)}', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                  ],
                ),
              ),
              const Spacer(flex: 1),
              // Main playback controls (15s back, Play/Pause, 30s fwd)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.replay_10_rounded),
                    onPressed: () => _skip(-15),
                  ),
                  const SizedBox(width: 24),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFA2D48),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 38,
                      color: Colors.white,
                      icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      onPressed: _togglePlayPause,
                    ),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.forward_10_rounded),
                    onPressed: () => _skip(30),
                  ),
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
                  IconButton(
                    icon: const Icon(Icons.list_rounded, size: 24),
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: const Center(child: Icon(Icons.headphones_rounded, size: 64, color: Colors.white38)),
    );
  }
}
