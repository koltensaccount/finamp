import 'dart:async';
import 'dart:math';
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
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
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
    final progressBackgroundColor = getProgressBackgroundColor(ref).withOpacity(0.5);
    var context = ref.context;

    return SimpleGestureDetector(
      onVerticalSwipe: (direction) {
        if (direction == SwipeDirection.up && retryCallback != null) {
          retryCallback();
        }
      },
      onTap: retryCallback,
      child: Padding(
        padding: const EdgeInsets.only(left: 12.0, bottom: 12.0, right: 12.0),
        child: Container(
          decoration: getShadow(ref.context),
          child: Material(
            shadowColor: ColorScheme.of(
              context,
            ).primary.withOpacity(Theme.brightnessOf(context) == Brightness.light ? 0.75 : 0.3),
            borderRadius: BorderRadius.circular(18.0),
            clipBehavior: Clip.antiAlias,
            color: Theme.brightnessOf(context) == Brightness.dark
                ? IconTheme.of(context).color!.withOpacity(0.1)
                : Theme.of(context).cardColor,
            elevation: 8.0,
            child: Container(
              width: MediaQuery.widthOf(context),
              height: albumImageSize,
              padding: EdgeInsets.zero,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: progressBackgroundColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: albumImageSize,
                      height: albumImageSize,
                      decoration: const ShapeDecoration(shape: Border(), color: Color.fromRGBO(0, 0, 0, 0.3)),
                      child: (retryCallback != null)
                          ? const Icon(Icons.refresh, size: albumImageSize)
                          : const Center(child: CircularProgressIndicator.adaptive()),
                    ),
                    Expanded(
                      child: Container(
                        height: albumImageSize,
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          (retryCallback != null)
                              ? AppLocalizations.of(context)!.queueRetryMessage
                              : AppLocalizations.of(context)!.queueLoadingMessage,
                        ),
                      ),
                    ),
                  ],
                ),
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

    Duration? playbackPosition;
    var context = ref.context;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final elapsedPartBackgroundColor = getProgressForegroundColor(ref);

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
                  borderRadius: BorderRadius.circular(18.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Container(
                      width: MediaQuery.widthOf(context),
                      height: albumImageSize,
                      padding: EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xB31C1C1E)
                            : const Color(0xCCFFFFFF),
                        borderRadius: BorderRadius.circular(18.0),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                      ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 5.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: SizedBox(
                              width: albumImageSize - 10.0,
                              height: albumImageSize - 10.0,
                              child: AlbumImage(
                                placeholderBuilder: (_) => const SizedBox.shrink(),
                                imageListenable: currentAlbumImageProvider,
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              if (ref.watch(finampSettingsProvider.showProgressOnNowPlayingBar))
                                Positioned.fill(
                                  child: StreamBuilder<Duration>(
                                    stream: AudioService.position,
                                    initialData: audioHandler.playbackState.value.position,
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        playbackPosition = snapshot.data;
                                        var itemLength = currentTrack.item.duration;
                                        return FractionallySizedBox(
                                          alignment: AlignmentDirectional.centerStart,
                                          widthFactor: itemLength == null
                                              ? 0
                                              : max(0, playbackPosition!.inMilliseconds / itemLength.inMilliseconds),
                                          child: DecoratedBox(
                                            decoration: ShapeDecoration(
                                              color: elapsedPartBackgroundColor,
                                              shape: const RoundedRectangleBorder(
                                                borderRadius: BorderRadius.only(
                                                  topRight: Radius.circular(12),
                                                  bottomRight: Radius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      } else {
                                        return SizedBox.shrink();
                                      }
                                    },
                                  ),
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: albumImageSize,
                                      padding: const EdgeInsets.only(left: 12, right: 4),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          OneLineMarqueeHelper(
                                            key: ValueKey(currentTrack.item.id),
                                            text: currentTrack.item.title,
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              height: 26 / 20,
                                              color: primaryTextColor,
                                              fontWeight: Theme.brightnessOf(context) == Brightness.light
                                                  ? FontWeight.w500
                                                  : FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            processArtist(currentTrack.item.artist, context),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: primaryTextColor.withValues(alpha: 0.8),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
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
                                            showPauseButton ? TablerIcons.player_pause : TablerIcons.player_play,
                                            size: 28,
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
                                            TablerIcons.player_track_next,
                                            size: 24,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
