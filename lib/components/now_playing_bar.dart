import 'dart:async';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/components/one_line_marquee_helper.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/services/current_track_metadata_provider.dart';
import 'package:finamp/services/feedback_helper.dart';
import 'package:finamp/services/queue_service.dart';
import 'package:finamp/services/theme_provider.dart';
import 'package:finamp/services/widget_bindings_observer_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:simple_gesture_detector/simple_gesture_detector.dart';

import '../screens/player_screen.dart';
import '../services/current_album_image_provider.dart';
import '../services/finamp_settings_helper.dart';
import '../services/media_state_stream.dart';
import '../services/music_player_background_task.dart';
import '../services/process_artist.dart';
import 'PlayerScreen/player_split_screen_scaffold.dart';
import 'album_image.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key});

  static const horizontalPadding = 8.0;
  static const albumImageSize = 58.0;
  static const showPlayButtonAtEnd = true;

  BoxDecoration? getShadow(BuildContext context) => BoxDecoration(
    borderRadius: const BorderRadius.all(Radius.circular(18.0)),
    boxShadow: [
      BoxShadow(
        blurRadius: 16.0,
        spreadRadius: 2.0,
        color: Colors.black.withOpacity(Theme.brightnessOf(context) == Brightness.light ? 0.12 : 0.45),
        offset: const Offset(0, 4),
      ),
    ],
  );

  Color getProgressForegroundColor(WidgetRef ref) {
    return ColorScheme.of(ref.context).primary;
  }

  Color getProgressBackgroundColor(WidgetRef ref) {
    return Color.alphaBlend(
      getProgressForegroundColor(ref).withOpacity(0.75),
      // this is an approximation, the actual background has the blurred cover image
      ref.watch(brightnessProvider) == Brightness.dark ? Colors.black : Colors.white,
    );
  }

  Widget buildLoadingQueueBar(WidgetRef ref, void Function()? retryCallback) {
    final context = ref.context;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;

    return SimpleGestureDetector(
      onVerticalSwipe: (direction) {
        if (direction == SwipeDirection.up && retryCallback != null) {
          retryCallback();
        }
      },
      onTap: retryCallback,
      child: Padding(
        padding: const EdgeInsets.only(left: 16.0, bottom: 6.0, right: 16.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14.0),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0x73141416)
                    : const Color(0x99FFFFFF),
                borderRadius: BorderRadius.circular(14.0),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: (retryCallback != null)
                        ? Icon(Icons.refresh_rounded, size: 22, color: primaryTextColor)
                        : CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(primaryTextColor),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      (retryCallback != null)
                          ? AppLocalizations.of(context)!.queueRetryMessage
                          : AppLocalizations.of(context)!.queueLoadingMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: primaryTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> openPlayerScreen() async {
    minimizeSplitScreen.value = false;
    await GlobalSnackbar.navigatorState?.push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) {
            return child;
          }
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOutQuad));
          var offsetAnimation = animation.drive(tween);

          if (animation.status == AnimationStatus.reverse) {
            // dismiss animation
            return FadeTransition(opacity: animation, child: child);
          } else {
            return SlideTransition(position: offsetAnimation, child: child);
          }
        },
        settings: const RouteSettings(name: PlayerScreen.routeName),
      ),
    );
  }

  Widget buildNowPlayingBar(WidgetRef ref, FinampQueueItem currentTrack) {
    final audioHandler = GetIt.instance<MusicPlayerBackgroundTask>();
    final queueService = GetIt.instance<QueueService>();
    final context = ref.context;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;

    final showPauseButton = ref.watch(
      mediaStateProvider.select((x) => x.playbackState.playing && x.fadeDirection != FadeDirection.fadeOut),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, bottom: 6.0, right: 16.0),
      child: Semantics.fromProperties(
        properties: SemanticsProperties(label: AppLocalizations.of(context)!.nowPlayingBarTooltip, button: true),
        child: SimpleGestureDetector(
          onTap: () async => await openPlayerScreen(),
          child: Dismissible(
            key: const Key("NowPlayingBarDismiss"),
            direction: ref.watch(finampSettingsProvider.disableGesture)
                ? DismissDirection.none
                : DismissDirection.vertical,
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.down) {
                FeedbackHelper.feedback(FeedbackType.success);
                await queueService.stopAndClearQueue();
              } else {
                await openPlayerScreen();
              }
              return false;
            },
            dismissThresholds: const {DismissDirection.up: 0.15, DismissDirection.down: 0.7},
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: getShadow(context),
              child: Dismissible(
                key: const Key("NowPlayingBar"),
                direction: ref.watch(finampSettingsProvider.disableGesture)
                    ? DismissDirection.none
                    : DismissDirection.horizontal,
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    FeedbackHelper.feedback(FeedbackType.light);
                    await audioHandler.skipToNext();
                  } else {
                    FeedbackHelper.feedback(FeedbackType.light);
                    await audioHandler.skipToPrevious(forceSkip: true);
                  }
                  return false;
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      width: MediaQuery.widthOf(context),
                      height: 48,
                      padding: EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0x73141416)
                            : const Color(0x99FFFFFF),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 7.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5.0),
                                  child: SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: AlbumImage(
                                      placeholderBuilder: (_) => const SizedBox.shrink(),
                                      imageListenable: currentAlbumImageProvider,
                                      borderRadius: BorderRadius.circular(5.0),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.only(left: 4, right: 4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      OneLineMarqueeHelper(
                                        key: ValueKey(currentTrack.item.id),
                                        text: currentTrack.item.title,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: primaryTextColor,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        processArtist(currentTrack.item.artist, context),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isDark ? Colors.white70 : Colors.black54,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 6.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: AppLocalizations.of(context)!.togglePlaybackButtonTooltip,
                                      onPressed: () {
                                        FeedbackHelper.feedback(FeedbackType.light);
                                        unawaited(audioHandler.togglePlayback());
                                      },
                                      color: primaryTextColor,
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        showPauseButton ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        size: 24,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Next',
                                      onPressed: () {
                                        FeedbackHelper.feedback(FeedbackType.light);
                                        unawaited(audioHandler.skipToNext());
                                      },
                                      color: primaryTextColor,
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.fast_forward_rounded,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Subtle Apple-style 1.5px hairline progress at bottom
                          if (ref.watch(finampSettingsProvider.showProgressOnNowPlayingBar))
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 1.5,
                              child: StreamBuilder<Duration>(
                                stream: AudioService.position,
                                initialData: audioHandler.playbackState.value.position,
                                builder: (context, snapshot) {
                                  if (snapshot.hasData) {
                                    final position = snapshot.data!;
                                    final itemLength = currentTrack.item.duration;
                                    return FractionallySizedBox(
                                      alignment: AlignmentDirectional.centerStart,
                                      widthFactor: itemLength == null
                                          ? 0
                                          : (position.inMilliseconds / itemLength.inMilliseconds).clamp(0.0, 1.0),
                                      child: Container(
                                        color: Colors.white.withValues(alpha: 0.5),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueService = GetIt.instance<QueueService>();

    return Hero(
      tag: "nowplaying",
      createRectTween: (from, to) => RectTween(begin: from, end: from),
      child: PlayerScreenTheme(
        // The now playing bar must be enclosed in a SafeArea at all times so that the enclosing scaffold properly adds
        // bottom padding, even if the now playing bar itself is empty.
        child: SafeArea(
          bottom: false,
          // use consumer to obtain ref of correct (player screen theme) ProviderContainer
          child: Consumer(
            builder: (context, ref, child) {
              ref.listen(currentTrackMetadataProvider, (metadataOrNull, metadata) {}); // keep provider alive
              return StreamBuilder<FinampQueueInfo?>(
                stream: queueService.getQueueStream(),
                initialData: queueService.getQueue(),
                builder: (context, snapshot) {
                  if (snapshot.hasData &&
                      snapshot.data!.saveState == SavedQueueState.loading &&
                      !usingPlayerSplitScreen) {
                    return buildLoadingQueueBar(ref, null);
                  } else if (snapshot.hasData &&
                      snapshot.data!.saveState == SavedQueueState.failed &&
                      !usingPlayerSplitScreen) {
                    return buildLoadingQueueBar(ref, queueService.retryQueueLoad);
                  } else if (snapshot.hasData && snapshot.data!.currentTrack != null && !usingPlayerSplitScreen) {
                    return buildNowPlayingBar(ref, snapshot.data!.currentTrack!);
                  } else {
                    return const SizedBox.shrink();
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
