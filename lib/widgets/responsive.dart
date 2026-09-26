import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_layout.dart';

/// Centers [child] and caps its width so web/desktop pages do not stretch.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.dashboardMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Scrollable page body with adaptive padding and a max-width column.
class ResponsivePage extends StatelessWidget {
  const ResponsivePage({
    super.key,
    required this.children,
    this.maxWidth = AppLayout.dashboardMaxWidth,
    this.physics,
    this.padding,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final List<Widget> children;
  final double maxWidth;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return ListView(
      physics: physics,
      padding: padding ?? AppLayout.pagePaddingOf(width),
      keyboardDismissBehavior: keyboardDismissBehavior,
      children: [
        ResponsiveContent(
          maxWidth: maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// [SingleChildScrollView] variant used by screens that already own a Column.
class ResponsiveScroll extends StatelessWidget {
  const ResponsiveScroll({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.dashboardMaxWidth,
    this.physics,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SingleChildScrollView(
      physics: physics,
      padding: padding ?? AppLayout.pagePaddingOf(width),
      child: ResponsiveContent(maxWidth: maxWidth, child: child),
    );
  }
}

/// Sticky footer that stays aligned with the page's max-width column.
class ResponsiveBar extends StatelessWidget {
  const ResponsiveBar({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.formMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: AppLayout.barPaddingOf(width),
      child: ResponsiveContent(maxWidth: maxWidth, child: child),
    );
  }
}

/// Full-width CTA on phones; intrinsic on tablet/desktop.
class AdaptiveCta extends StatelessWidget {
  const AdaptiveCta({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppLayout.isCompact(context)) {
      return SizedBox(width: double.infinity, child: child);
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 360),
        child: child,
      ),
    );
  }
}

/// Title + action that stacks on narrow widths instead of overflowing.
class SectionToolbar extends StatelessWidget {
  const SectionToolbar({super.key, required this.title, required this.action});

  final Widget title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: action,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            action,
          ],
        );
      },
    );
  }
}

/// Variable-height cards in 1 or 2+ columns without a fixed aspect ratio.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.spacing = 10,
    this.minTileWidth = 400,
    this.maxColumns = 2,
  });

  final List<Widget> children;
  final double spacing;
  final double minTileWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        var columns = (width / minTileWidth).floor();
        columns = math.max(1, math.min(maxColumns, columns));
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        final rows = <List<Widget>>[];
        for (var i = 0; i < children.length; i += columns) {
          rows.add(
            children.sublist(i, math.min(i + columns, children.length)),
          );
        }
        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) SizedBox(height: spacing),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) SizedBox(width: spacing),
                    Expanded(
                      child: c < rows[r].length
                          ? rows[r][c]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

IconData trailingChevronOf(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? Icons.chevron_left
    : Icons.chevron_right;
