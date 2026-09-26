import 'package:bayyin_teacher/theme/app_layout.dart';
import 'package:bayyin_teacher/widgets/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('breakpoints match the documented mobile / tablet / desktop bands', () {
    expect(AppLayout.isMobile(599), isTrue);
    expect(AppLayout.isTablet(600), isTrue);
    expect(AppLayout.isTablet(1023), isTrue);
    expect(AppLayout.isDesktop(1024), isTrue);
    expect(AppLayout.columnsFor(390), 1);
    expect(AppLayout.columnsFor(800), 2);
    expect(AppLayout.columnsFor(1280), 2);
  });

  testWidgets('ResponsiveContent never exceeds the dashboard max width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsivePage(
            children: [
              ColoredBox(
                key: Key('page-body'),
                color: Color(0xFF00AA00),
                child: SizedBox(height: 24),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('page-body'))).width, 1120);
  });

  testWidgets('ResponsiveGrid stays one column on a phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsivePage(
            children: [
              ResponsiveGrid(
                children: [
                  SizedBox(key: Key('a'), height: 40, child: Text('A')),
                  SizedBox(key: Key('b'), height: 40, child: Text('B')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final a = tester.getTopLeft(find.byKey(const Key('a')));
    final b = tester.getTopLeft(find.byKey(const Key('b')));
    expect(b.dy, greaterThan(a.dy));
  });
}
