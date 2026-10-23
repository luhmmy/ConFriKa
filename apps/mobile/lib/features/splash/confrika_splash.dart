import 'package:flutter/material.dart';

import '../../core/theme/confrika_theme.dart';
import '../../core/widgets/confrika_brand_widgets.dart';

/// Animated launch splash: the emblem springs in, then the ConFriKa name
/// slides/fades up, then the tagline. Calls [onDone] when it finishes.
class ConFriKaSplash extends StatefulWidget {
  final VoidCallback onDone;
  const ConFriKaSplash({super.key, required this.onDone});

  @override
  State<ConFriKaSplash> createState() => _ConFriKaSplashState();
}

class _ConFriKaSplashState extends State<ConFriKaSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
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
    // Hold briefly on the finished frame, then hand off to the app.
    Future.delayed(const Duration(milliseconds: 2700), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
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
              FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: const ConFriKaAppLogo(size: 132),
                ),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: _nameFade,
                child: SlideTransition(
                  position: _nameSlide,
                  child: const ConFriKaWordmark(fontSize: 46),
                ),
              ),
              const SizedBox(height: 14),
              FadeTransition(
                opacity: _taglineFade,
                child: const Text(
                  'Many languages. One connection. One Africa.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: _taglineFade,
                child: const SizedBox(
                  width: 120,
                  child: ConFriKaTriColorBar(height: 4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
