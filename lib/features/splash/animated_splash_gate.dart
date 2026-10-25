// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Menampilkan identitas VoltStride sebentar sebelum membuka halaman utama.
/// Gambar ini hanya digunakan untuk layar pembuka; launcher icon tidak berubah.
class AnimatedSplashGate extends StatefulWidget {
  const AnimatedSplashGate({
    super.key,
    required this.child,
    this.waitForChildReady = false,
  });

  final Widget child;
  final bool waitForChildReady;

  @override
  AnimatedSplashGateState createState() => AnimatedSplashGateState();
}

class AnimatedSplashGateState extends State<AnimatedSplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _sloganOpacity;
  late final Animation<Offset> _sloganOffset;
  late final Animation<double> _lineWidth;
  Timer? _finishTimer;
  bool _showSplash = true;
  bool _minimumElapsed = false;
  late bool _childReady;

  @override
  void initState() {
    super.initState();
    _childReady = !widget.waitForChildReady;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _logoScale = Tween<double>(begin: 0.78, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.72, curve: Curves.easeOutBack),
      ),
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.42, curve: Curves.easeOut),
    );
    _sloganOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.38, 0.82, curve: Curves.easeOut),
    );
    _sloganOffset = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.38, 0.88, curve: Curves.easeOutCubic),
      ),
    );
    _lineWidth = Tween<double>(begin: 0, end: 76).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.62, 1, curve: Curves.easeOutCubic),
      ),
    );
    _controller.forward();
    _finishTimer = Timer(const Duration(milliseconds: 2550), () {
      if (!mounted) return;
      setState(() {
        _minimumElapsed = true;
        if (_childReady) _showSplash = false;
      });
    });
  }

  /// Dipanggil setelah AccountGate selesai memeriksa sesi Firebase.
  void markChildReady() {
    if (!mounted || _childReady) return;
    setState(() {
      _childReady = true;
      if (_minimumElapsed) _showSplash = false;
    });
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: _showSplash
            ? Colors.white
            : Theme.of(context).scaffoldBackgroundColor,
        statusBarIconBrightness: _showSplash
            ? Brightness.dark
            : (brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark),
        systemNavigationBarColor: _showSplash
            ? Colors.white
            : Theme.of(context).scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: _showSplash
            ? Brightness.dark
            : (brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // AccountGate berjalan di belakang splash supaya sesi akun selesai
          // diperiksa selama animasi, bukan setelah logo menghilang.
          Offstage(
            offstage: _showSplash,
            child: TickerMode(
              enabled: !_showSplash,
              child: _buildApp(),
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.99, end: 1).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _showSplash
                  ? _buildSplash()
                  : const SizedBox.shrink(
                      key: ValueKey<String>('voltstride-splash-hidden'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplash() {
    return Scaffold(
      key: const ValueKey<String>('voltstride-splash'),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FadeTransition(
                    opacity: _logoOpacity,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Image.asset(
                        'assets/branding/voltstride_splash.png',
                        width: 268,
                        height: 268,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SlideTransition(
                    position: _sloganOffset,
                    child: FadeTransition(
                      opacity: _sloganOpacity,
                      child: Column(
                        children: <Widget>[
                          const Text(
                            'Set Your Pace,',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF5C5C5C),
                              fontSize: 21,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Spark Your Best',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF161616),
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.45,
                            ),
                          ),
                          const SizedBox(height: 17),
                          Container(
                            width: _lineWidth.value,
                            height: 3,
                            color: const Color(0xFF252525),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildApp() => KeyedSubtree(
        key: const ValueKey<String>('voltstride-main-app'),
        child: widget.child,
      );
}
