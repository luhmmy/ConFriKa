import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/confrika_theme.dart';
import '../../core/widgets/confrika_brand_widgets.dart';

/// Animated launch splash: a pulsing halo breathes behind the emblem as it
/// springs in, the ConFriKa name slides up, the tagline fades, and a tri-colour
/// loading bar sweeps underneath. Calls [onDone] when it finishes.
class ConFriKaSplash extends StatefulWidget {
  final VoidCallback onDone;
  const ConFriKaSplash({super.key, required this.onDone});

  @override
  State<ConFriKaSplash> createState() => _ConFriKaSplashState();
}

class _ConFriKaSplashState extends State<ConFriKaSplash>
    with TickerProviderStateMixin {
  late final AnimationController _c; // entrance (one-shot)
  late final AnimationController _loop; // breathing halo + sweep (repeating)
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _nameFade;
  late final Animation<Offset> _nameSlide;
  late final Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _logoFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
      ),
    );
    _nameFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.38, 0.68, curve: Curves.easeOut),
    );
    _nameSlide = Tween<Offset>(begin: const Offset(0, 0.45), end: Offset.zero)
        .animate(CurvedAnimation(
      parent: _c,
      curve: const Interval(0.38, 0.72, curve: Curves.easeOutCubic),
    ));
    _taglineFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.68, 0.95, curve: Curves.easeOut),
    );

    _c.forward();
    Future.delayed(const Duration(milliseconds: 2700), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0E1621), const Color(0xFF0A0F16)]
                : [
                    ConFriKaColors.oceanBlue.withValues(alpha: 0.06),
                    ConFriKaColors.savannaGreen.withValues(alpha: 0.06),
                  ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emblem with a breathing halo behind it.
              SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _loop,
                      builder: (_, __) {
                        final t = _loop.value;
                        final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
                        return Container(
                          width: 150 + pulse * 34,
                          height: 150 + pulse * 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              ConFriKaColors.oceanBlue
                                  .withValues(alpha: 0.18 * (1 - pulse)),
                              ConFriKaColors.savannaGreen
                                  .withValues(alpha: 0.10 * (1 - pulse)),
                              Colors.transparent,
                            ]),
                          ),
                        );
                      },
                    ),
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: const ConFriKaAppLogo(size: 132),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FadeTransition(
                opacity: _nameFade,
                child: SlideTransition(
                  position: _nameSlide,
                  child: const ConFriKaWordmark(fontSize: 46),
                ),
              ),
              const SizedBox(height: 8),
              FadeTransition(
                opacity: _nameFade,
                child: const Text(
                  'Connect Africa',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                    color: ConFriKaColors.sunsetOrange,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FadeTransition(
                opacity: _taglineFade,
                child: const Text(
                  'Many languages. One continent.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 30),
              // Indeterminate tri-colour sweep.
              FadeTransition(
                opacity: _taglineFade,
                child: SizedBox(
                  width: 150,
                  height: 4,
                  child: AnimatedBuilder(
                    animation: _loop,
                    builder: (_, __) => CustomPaint(
                      painter: _SweepBarPainter(_loop.value),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tri-colour (blue/orange/green) highlight that sweeps left→right on a track.
class _SweepBarPainter extends CustomPainter {
  final double t;
  _SweepBarPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.height));
    canvas.drawRRect(
        r, Paint()..color = Colors.grey.withValues(alpha: 0.18));

    final w = size.width * 0.42;
    final x = (t * (size.width + w)) - w;
    canvas.save();
    canvas.clipRRect(r);
    final rect = Rect.fromLTWH(x, 0, w, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: [
          ConFriKaColors.oceanBlue,
          ConFriKaColors.sunsetOrange,
          ConFriKaColors.savannaGreen,
        ]).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweepBarPainter old) => old.t != t;
}
