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
      duration: const Duration(milliseconds: 850),
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
    _controller.forward();
    _finishTimer = Timer(const Duration(milliseconds: 1450), () {
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
          if (_showSplash) Positioned.fill(child: _buildSplash()),
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
              return FadeTransition(
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
