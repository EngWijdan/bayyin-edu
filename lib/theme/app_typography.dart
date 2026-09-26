import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static TextTheme textTheme(TextTheme base) {
    return base
        .apply(bodyColor: AppColors.darkText, displayColor: AppColors.darkText)
        .copyWith(
          headlineSmall: base.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.darkText,
            height: 1.25,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.darkText,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.darkText,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.darkText,
          ),
          bodyLarge: base.bodyLarge?.copyWith(
            color: AppColors.darkText,
            height: 1.4,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            color: AppColors.darkText,
            height: 1.4,
          ),
          bodySmall: base.bodySmall?.copyWith(
            color: AppColors.mutedText,
            height: 1.35,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.darkText,
          ),
          labelSmall: base.labelSmall?.copyWith(color: AppColors.mutedText),
        );
  }
}
