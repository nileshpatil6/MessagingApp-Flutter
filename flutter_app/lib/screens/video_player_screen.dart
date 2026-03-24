import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerScreen({super.key, required this.videoUrl});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _showControls = true;

  bool get _isNetwork =>
      widget.videoUrl.startsWith('http://') ||
      widget.videoUrl.startsWith('https://');

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      if (_isNetwork) {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
      } else {
        _controller = VideoPlayerController.file(
          File(widget.videoUrl),
        );
      }

      await _controller.initialize();
      _controller.addListener(_onControllerUpdate);

      if (mounted) {
        setState(() => _initialized = true);
        _controller.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _controller.value.isPlaying) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Video'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download started')),
              );
            },
          ),
        ],
      ),
      body: _hasError
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.white54),
                  SizedBox(height: 16),
                  Text(
                    'Failed to load video',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          : !_initialized
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : GestureDetector(
                  onTap: _toggleControls,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Video
                      Center(
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                      ),

                      // Controls overlay
                      AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: Container(
                            color: Colors.black38,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Play / pause center button
                                Expanded(
                                  child: Center(
                                    child: IconButton(
                                      iconSize: 64,
                                      icon: Icon(
                                        _controller.value.isPlaying
                                            ? Icons.pause_circle_filled
                                            : Icons.play_circle_filled,
                                        color: Colors.white,
                                      ),
                                      onPressed: _togglePlayPause,
                                    ),
                                  ),
                                ),
                                // Progress bar + time
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Row(
                                    children: [
                                      Text(
                                        _formatDuration(
                                            _controller.value.position),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: _controller
                                              .value.position.inMilliseconds
                                              .toDouble()
                                              .clamp(
                                                  0,
                                                  _controller.value.duration
                                                      .inMilliseconds
                                                      .toDouble()),
                                          min: 0,
                                          max: _controller.value.duration
                                              .inMilliseconds
                                              .toDouble(),
                                          onChanged: (val) {
                                            _controller.seekTo(
                                              Duration(
                                                  milliseconds: val.toInt()),
                                            );
                                          },
                                          activeColor: Colors.white,
                                          inactiveColor: Colors.white38,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(
                                            _controller.value.duration),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                // Extra controls
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                          Icons.replay_10,
                                          color: Colors.white),
                                      onPressed: () {
                                        final newPos =
                                            _controller.value.position -
                                                const Duration(seconds: 10);
                                        _controller.seekTo(newPos >
                                                Duration.zero
                                            ? newPos
                                            : Duration.zero);
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _controller.value.isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 36,
                                      ),
                                      onPressed: _togglePlayPause,
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.forward_10,
                                          color: Colors.white),
                                      onPressed: () {
                                        final newPos =
                                            _controller.value.position +
                                                const Duration(seconds: 10);
                                        _controller.seekTo(
                                          newPos <
                                                  _controller.value.duration
                                              ? newPos
                                              : _controller.value.duration,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _controller.value.volume > 0
                                            ? Icons.volume_up
                                            : Icons.volume_off,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        _controller.setVolume(
                                          _controller.value.volume > 0
                                              ? 0
                                              : 1,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
