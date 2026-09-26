import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_spacing.dart';
import '../widgets/branding.dart';

/// Short branded beat after a successful login. Plays once per sign-in.
class WelcomeTransitionPage extends StatefulWidget {
  const WelcomeTransitionPage({
    super.key,
    required this.session,
    required this.onFinished,
  });

  final UserSession session;
  final VoidCallback onFinished;

  static const Duration playDuration = Duration(milliseconds: 1600);

  /// Tests override this so [pumpAndSettle] does not wait a full 1.6s.
  @visibleForTesting
  static Duration? debugDurationOverride;

  static Duration durationOf(BuildContext context) {
    final override = debugDurationOverride;
    if (override != null) return override;
    if (MediaQuery.disableAnimationsOf(context)) return Duration.zero;
    return playDuration;
  }

  @override
  State<WelcomeTransitionPage> createState() => _WelcomeTransitionPageState();
}

class _WelcomeTransitionPageState extends State<WelcomeTransitionPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;
  bool _finished = false;

  late final Animation<double> _logoOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
  );
  late final Animation<double> _logoScale =
      Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.38, curve: Curves.easeOutCubic),
        ),
      );
  late final Animation<double> _textOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.28, 0.55, curve: Curves.easeOut),
  );
  late final Animation<Offset> _textSlide =
      Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.28, 0.55, curve: Curves.easeOutCubic),
        ),
      );
  late final Animation<double> _exitOpacity =
      Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.78, 1.0, curve: Curves.easeIn),
        ),
      );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _complete();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final duration = WelcomeTransitionPage.durationOf(context);
    if (duration == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _complete();
      });
      return;
    }
    _controller.duration = duration;
    _controller.forward();
  }

  void _complete() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final name = widget.session.displayName;
    return Scaffold(
      backgroundColor: AppColors.verySoftGreen,
      body: SafeArea(
        child: FadeTransition(
          opacity: _exitOpacity,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppLayout.formMaxWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  FadeTransition(
                    opacity: _logoOpacity,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: const BayyinLogo(width: 120),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FadeTransition(
                    opacity: _textOpacity,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(
                        children: [
                          Text(
                            strings.welcomeHello(name),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            strings.loginTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: AppColors.mutedText),
                          ),
                        ],
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
}
