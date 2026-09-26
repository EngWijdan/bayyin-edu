import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// Official Bayyin lockup. The Arabic wordmark stays even in English.
abstract final class BayyinAssets {
  static const logo = 'assets/branding/bayyin_logo.png';
}

class BayyinLogo extends StatelessWidget {
  const BayyinLogo({
    super.key,
    this.width = 108,
    this.semanticLabel = 'بيّن',
  });

  final double width;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      BayyinAssets.logo,
      width: width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel,
    );
  }
}

/// Compact header branding for root dashboards. Not used on nested screens.
class BayyinBrandLockup extends StatelessWidget {
  const BayyinBrandLockup({super.key, this.subtitle});

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final caption = subtitle ?? strings.appTagline;
    return Row(
      children: [
        const BayyinLogo(width: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.appName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Subtle AI cue that stays inside the Bayyin green identity.
class AiGeneratedBadge extends StatelessWidget {
  const AiGeneratedBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.auto_awesome_rounded,
          size: 16,
          color: AppColors.primarySoft,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class BrandIconBox extends StatelessWidget {
  const BrandIconBox({
    super.key,
    required this.icon,
    this.size = 36,
    this.iconSize = 18,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.softMint,
        borderRadius: AppRadius.chip,
      ),
      child: Icon(icon, size: iconSize, color: AppColors.primary),
    );
  }
}
