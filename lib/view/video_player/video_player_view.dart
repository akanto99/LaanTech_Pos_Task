import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/utils/formatters/formatters.dart';
import 'package:laantech_pos_task/configs/widgets/state_views.dart';
import 'package:laantech_pos_task/data/response/status.dart';
import 'package:laantech_pos_task/model/video/video_player_args.dart';
import 'package:laantech_pos_task/view_model/video_player_view_model/video_player_view_model.dart';
import 'package:laantech_pos_task/configs/res/sizedbox_spaccing.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerView extends StatelessWidget {
  const VideoPlayerView({super.key, required this.video});

  final VideoPlayerArgs video;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VideoPlayerViewModel(video: video)..load(),
      child: const _VideoPlayerScreen(),
    );
  }
}

class _VideoPlayerScreen extends StatefulWidget {
  const _VideoPlayerScreen();

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  bool _fullscreen = false;

  Future<void> _setFullscreen(bool fullscreen, {double aspectRatio = 16 / 9}) async {
    setState(() => _fullscreen = fullscreen);
    if (fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // Portrait videos stay portrait; wide videos rotate to landscape.
      await SystemChrome.setPreferredOrientations(
        aspectRatio >= 1 ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : const [DeviceOrientation.portraitUp],
      );
    } else {
      await _restoreSystemUi();
    }
  }

  static Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(AppConfig.orientations);
  }

  @override
  void dispose() {
    if (_fullscreen) unawaited(_restoreSystemUi());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VideoPlayerViewModel>();
    final player = vm.player;

    final Widget body = switch (player.status) {
      Status.loading => _LoadingView(downloading: vm.downloading, progress: vm.downloadProgress),
      Status.error => ErrorStateView(message: player.message!, onRetry: vm.load),
      Status.completed => _PlayerSurface(
        controller: player.data!,
        fullscreen: _fullscreen,
        onToggleFullscreen: () => _setFullscreen(!_fullscreen, aspectRatio: player.data!.value.aspectRatio),
        onRetry: vm.load,
      ),
    };

    return PopScope(
      // Back leaves fullscreen first instead of closing the player.
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setFullscreen(false);
      },
      child: Scaffold(
        backgroundColor: _fullscreen ? Colors.black : null,
        appBar: _fullscreen ? null : AppBar(title: Text(vm.video.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: body,
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.downloading, required this.progress});

  final bool downloading;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: ResPonsiveUi.padding(context, horizontal: 0.08, vertical: 0.0375),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (downloading) ...[
              LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(4)),
              SizedboxSpaccing.height015(context),
              Text(
                progress == null ? 'Streaming is unavailable. Downloading the video to play it…' : 'Streaming is unavailable. Downloading the video to play it… ${(progress! * 100).floor()}%',
                textAlign: TextAlign.center,
                style: AppTextStyles.textSize14(context, color: AppColors.subtitle(context)),
              ),
            ] else ...[
              const CircularProgressIndicator(),
              SizedboxSpaccing.height015(context),
              Text('Loading video…', style: AppTextStyles.textSize14(context, color: AppColors.subtitle(context))),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayerSurface extends StatefulWidget {
  const _PlayerSurface({required this.controller, required this.fullscreen, required this.onToggleFullscreen, required this.onRetry});

  final VideoPlayerController controller;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onRetry;

  @override
  State<_PlayerSurface> createState() => _PlayerSurfaceState();
}

class _PlayerSurfaceState extends State<_PlayerSurface> {
  static const _controlsTimeout = Duration(seconds: 3);

  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// Slider position while the user drags, so the thumb does not jump back.
  double? _dragMs;

  VideoPlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_controlsTimeout, () {
      if (mounted && _controller.value.isPlaying) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    final value = _controller.value;
    if (value.isPlaying) {
      await _controller.pause();
    } else {
      if (value.isCompleted) await _controller.seekTo(Duration.zero);
      await _controller.play();
    }
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        if (value.hasError) {
          return ErrorStateView(message: 'Playback stopped. Check your connection and try again.', onRetry: widget.onRetry);
        }
        final showControls = _controlsVisible || !value.isPlaying;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(_controller)),
                ),
                if (value.isBuffering) const Center(child: CircularProgressIndicator(color: Colors.white)),
                AnimatedOpacity(
                  opacity: showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(ignoring: !showControls, child: _controls(context, value)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _controls(BuildContext context, VideoPlayerValue value) {
    final durationMs = value.duration.inMilliseconds.toDouble();
    final positionMs = (_dragMs ?? value.position.inMilliseconds.toDouble()).clamp(0.0, durationMs > 0 ? durationMs : 0.0);
    const textStyle = TextStyle(color: Colors.white, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54], stops: [0.6, 1]),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: IconButton.filled(
                iconSize: 40,
                style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
                tooltip: value.isPlaying ? 'Pause' : 'Play',
                onPressed: _togglePlay,
                icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
            ),
            Positioned(
              left: 12,
              right: 4,
              bottom: 4,
              child: Row(
                children: [
                  Text(Formatters.duration(Duration(milliseconds: positionMs.round())), style: textStyle),
                  Expanded(
                    child: Slider(
                      value: positionMs,
                      max: durationMs > 0 ? durationMs : 1,
                      activeColor: AppColors.primary,
                      inactiveColor: Colors.white30,
                      secondaryActiveColor: Colors.white54,
                      secondaryTrackValue: value.buffered.isEmpty ? null : value.buffered.last.end.inMilliseconds.toDouble().clamp(0.0, durationMs > 0 ? durationMs : 1),
                      onChangeStart: (_) => _hideTimer?.cancel(),
                      onChanged: durationMs > 0 ? (ms) => setState(() => _dragMs = ms) : null,
                      onChangeEnd: (ms) async {
                        await _controller.seekTo(Duration(milliseconds: ms.round()));
                        if (mounted) setState(() => _dragMs = null);
                        _scheduleHide();
                      },
                    ),
                  ),
                  Text(Formatters.duration(value.duration), style: textStyle),
                  IconButton(
                    color: Colors.white,
                    tooltip: widget.fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                    onPressed: widget.onToggleFullscreen,
                    icon: Icon(widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
