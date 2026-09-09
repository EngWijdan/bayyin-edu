import 'package:flutter/material.dart';

import '../l10n/app_language.dart';

/// Language picker used on Login, Manager Dashboard and Teacher Dashboard.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({
    super.key,
    required this.onLocaleChanged,
    this.showLabel = false,
  });

  final ValueChanged<AppLocale> onLocaleChanged;

  /// Shows the active language next to the globe icon (used on Login, where
  /// there is room for it).
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final current = AppLocale.fromLocale(Localizations.localeOf(context));
    return PopupMenuButton<AppLocale>(
      tooltip: strings.language,
      initialValue: current,
      onSelected: onLocaleChanged,
      itemBuilder: (context) => [
        for (final option in AppLocale.values)
          PopupMenuItem<AppLocale>(
            value: option,
            child: Row(
              children: [
                Icon(
                  option == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(option.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language),
            if (showLabel) ...[
              const SizedBox(width: 8),
              Text(current.label),
            ],
          ],
        ),
      ),
    );
  }
}
