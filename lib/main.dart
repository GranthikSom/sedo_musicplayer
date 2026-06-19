import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sedo_music_bridge/media_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Force portrait orientation — this is a compact controller, not a landscape app.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Use full-black edge-to-edge for an OLED-friendly look.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF000000),
    ),
  );
  runApp(const SedoMusicBridgeApp());
}

class SedoMusicBridgeApp extends StatelessWidget {
  const SedoMusicBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sedo Music Bridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFFFFF),
          surface: Color(0xFF0A0A0A),
        ),
      ),
      home: const NowPlayingScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  final MediaController _controller = MediaController();

  String _title = '—';
  String _artist = '—';
  bool _isPlaying = false;
  bool _loading = true;

  Timer? _pollTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the play/pause indicator ring.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initial fetch, then poll every 2.5 seconds.
    _fetchNowPlaying();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => _fetchNowPlaying(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchNowPlaying() async {
    final info = await _controller.nowPlaying();
    if (!mounted) return;
    setState(() {
      _title = info['title'] ?? '—';
      _artist = info['artist'] ?? '—';
      _loading = false;
      // Heuristic: if title changed from unknown we likely have an active session.
      _isPlaying = _title != 'Unknown' && _title != '—';
    });
  }

  Future<void> _handlePlayPause() async {
    HapticFeedback.mediumImpact();
    await _controller.playPause(isCurrentlyPlaying: _isPlaying);
    setState(() => _isPlaying = !_isPlaying);
    await Future.delayed(const Duration(milliseconds: 300));
    await _fetchNowPlaying();
  }

  Future<void> _handleNext() async {
    HapticFeedback.lightImpact();
    await _controller.next();
    await Future.delayed(const Duration(milliseconds: 400));
    await _fetchNowPlaying();
  }

  Future<void> _handlePrevious() async {
    HapticFeedback.lightImpact();
    await _controller.previous();
    await Future.delayed(const Duration(milliseconds: 400));
    await _fetchNowPlaying();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: _loading ? _buildLoadingState() : _buildContent(size),
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          // App wordmark — typographic logo approach
          const Text(
            'SEDO',
            style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF444444)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'BRIDGE',
              style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
          ),
          const Spacer(),
          // Live indicator dot
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 8 * _pulseAnimation.value,
                height: 8 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  color: _isPlaying
                      ? const Color(
                          0xFF1DB954,
                        ) // Spotify green — universally understood as "playing"
                      : const Color(0xFF555555),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Text(
            _isPlaying ? 'NOW PLAYING' : 'IDLE',
            style: TextStyle(
              color: _isPlaying
                  ? const Color(0xFF1DB954)
                  : const Color(0xFF555555),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF444444),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Connecting to system audio…',
          style: TextStyle(
            color: Color(0xFF555555),
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(Size size) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 20),
          _AlbumArtPlaceholder(isPlaying: _isPlaying, size: size.width * 0.58),
          const SizedBox(height: 32),
          _TrackMetadata(title: _title, artist: _artist),
          const SizedBox(height: 40),
          _PlaybackControls(
            isPlaying: _isPlaying,
            onPrevious: _handlePrevious,
            onPlayPause: _handlePlayPause,
            onNext: _handleNext,
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Text(
        'Controls system-wide media · No audio playback',
        style: TextStyle(
          color: Colors.white.withOpacity(0.18),
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Album Art Placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _AlbumArtPlaceholder extends StatelessWidget {
  final bool isPlaying;
  final double size;

  const _AlbumArtPlaceholder({required this.isPlaying, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      width: isPlaying ? size : size * 0.82,
      height: isPlaying ? size : size * 0.82,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF111111),
        border: Border.all(
          color: isPlaying ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A1A),
          width: 1,
        ),
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: Colors.white.withOpacity(0.04),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ]
            : [],
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: isPlaying ? const Color(0xFF333333) : const Color(0xFF222222),
          size: size * 0.3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Track Metadata Display
// ─────────────────────────────────────────────────────────────────────────────

class _TrackMetadata extends StatelessWidget {
  final String title;
  final String artist;

  const _TrackMetadata({required this.title, required this.artist});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            title,
            key: ValueKey(title),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            artist,
            key: ValueKey(artist),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 15,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Playback Controls Row
// ─────────────────────────────────────────────────────────────────────────────

class _PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  const _PlaybackControls({
    required this.isPlaying,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ⏮ Previous
        _ControlButton(
          icon: Icons.skip_previous_rounded,
          size: 38,
          onTap: onPrevious,
          color: const Color(0xFFCCCCCC),
        ),

        const SizedBox(width: 28),

        // ⏯ Play / Pause — the focal point, larger with a ring
        _PlayPauseButton(isPlaying: isPlaying, onTap: onPlayPause),

        const SizedBox(width: 28),

        // ⏭ Next
        _ControlButton(
          icon: Icons.skip_next_rounded,
          size: 38,
          onTap: onNext,
          color: const Color(0xFFCCCCCC),
        ),
      ],
    );
  }
}

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final Color color;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onTap,
    required this.color,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Icon(
          widget.icon,
          size: widget.size,
          color: _pressed ? widget.color.withOpacity(0.5) : widget.color,
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            shape: BoxShape.circle,
            boxShadow: widget.isPlaying
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.12),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ]
                : [],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey('play_${widget.isPlaying}'),
              size: 38,
              color: const Color(0xFF000000),
            ),
          ),
        ),
      ),
    );
  }
}
