import 'dart:async';
import 'dart:typed_data';

import 'package:bayyin_teacher/l10n/app_language.dart';
import 'package:bayyin_teacher/main.dart';
import 'package:bayyin_teacher/screens/welcome_transition.dart';
import 'package:bayyin_teacher/services/attachment_picker.dart';
import 'package:bayyin_teacher/services/bayyin_api.dart';
import 'package:bayyin_teacher/widgets/branding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    WelcomeTransitionPage.debugDurationOverride = const Duration(
      milliseconds: 1,
    );
  });
  tearDown(() {
    WelcomeTransitionPage.debugDurationOverride = null;
  });

  group('العربية', () {
    testWidgets('يعرض شاشة تسجيل الدخول أولًا', (tester) async {
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'TEACHER')));
      expect(find.text('مرحبًا بك في بيّن'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(
        find.image(const AssetImage(BayyinAssets.logo)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    testWidgets('يستخدم اتجاه RTL', (tester) async {
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'TEACHER')));
      expect(
        Directionality.of(tester.element(find.byType(Form))),
        TextDirection.rtl,
      );
    });

    testWidgets('يوجه المدير إلى لوحة إدارة المعلمين', (tester) async {
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'MANAGER')));
      await _signIn(tester, 'تسجيل الدخول');
      expect(find.text('لوحة المدير'), findsOneWidget);
      expect(find.text('إضافة معلم'), findsOneWidget);
      expect(find.text('لا يوجد معلمون بعد'), findsOneWidget);
    });

    testWidgets('تتيح للمدير عرض طلاب الصف من البطاقة', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'MANAGER',
            teachers: [_teacherNoah],
            classrooms: [_managedClassroom],
            students: const [
              StudentRecord(
                id: 's-1',
                internalCode: 'S-001',
                displayName: 'طالب أ',
              ),
            ],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await tester.tap(find.text('n • e • رياضيات'));
      await tester.pumpAndSettle();
      expect(find.text('الطلاب'), findsOneWidget);
      expect(find.text('S-001'), findsOneWidget);
    });

    testWidgets('تتيح للمدير تعديل الصف وتغيير معلمه', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'MANAGER',
            teachers: [_teacherNoah, _teacherWijdan],
            classrooms: [_managedClassroom],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');

      await tester.tap(find.byTooltip('إجراءات الصف'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تعديل الصف'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'سادس ج');
      await tester.tap(find.text('حفظ التعديلات'));
      await tester.pumpAndSettle();
      expect(find.text('تم تحديث الصف.'), findsOneWidget);
      expect(find.text('سادس ج • رياضيات'), findsOneWidget);
      await _settleSnackBars(tester);

      await tester.tap(find.byTooltip('إجراءات الصف'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تغيير المعلم'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('wijdan alqarni').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(find.text('تم تغيير معلم الصف.'), findsOneWidget);
      expect(find.textContaining('wijdan alqarni'), findsWidgets);
    });

    testWidgets('تتيح للمدير حذف الصف بعد التأكيد', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'MANAGER',
            teachers: [_teacherNoah],
            classrooms: [_managedClassroom],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await tester.tap(find.byTooltip('إجراءات الصف'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف الصف'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('سيُحذف الصف "n • e"'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'حذف الصف'));
      await tester.pumpAndSettle();
      expect(find.text('تم حذف الصف.'), findsOneWidget);
      expect(find.text('n • e • رياضيات'), findsNothing);
    });

    testWidgets('يوجه المعلم إلى صفوفه', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      expect(find.text('صفوفي'), findsOneWidget);
      expect(find.text('سادس أ'), findsOneWidget);
    });
  });

  group('English', () {
    testWidgets('shows the login screen first', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER'),
          initialLocale: AppLocale.english,
        ),
      );
      expect(find.text('Welcome to Bayyin'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(
        find.image(const AssetImage(BayyinAssets.logo)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    testWidgets('uses LTR direction', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER'),
          initialLocale: AppLocale.english,
        ),
      );
      expect(
        Directionality.of(tester.element(find.byType(Form))),
        TextDirection.ltr,
      );
    });

    testWidgets('routes a manager to the manager dashboard', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'MANAGER'),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      expect(find.text('Manager dashboard'), findsOneWidget);
      expect(find.text('Add teacher'), findsOneWidget);
      expect(find.text('No teachers yet'), findsOneWidget);
    });

    testWidgets('routes a teacher to their classes', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      expect(find.text('My classes'), findsOneWidget);
      expect(find.text('سادس أ'), findsOneWidget);
    });
  });

  group('ترحيب بعد الدخول', () {
    testWidgets('successful login opens welcome then teacher dashboard', (
      tester,
    ) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            serverDisplayName: 'أحمد الغامدي',
            fullName: 'أحمد الغامدي',
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول', settle: false, skipWelcome: false);

      expect(find.text('أهلًا، أحمد الغامدي'), findsOneWidget);
      expect(find.text('مرحبًا بك في بيّن'), findsOneWidget);
      expect(
        find.image(const AssetImage(BayyinAssets.logo)),
        findsOneWidget,
      );
      expect(find.text('صفوفي'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('صفوفي'), findsOneWidget);
      expect(find.text('أهلًا، أحمد الغامدي'), findsNothing);
      expect(find.text('مرحبًا، أحمد الغامدي'), findsOneWidget);
    });

    testWidgets('welcome transitions to manager dashboard', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'MANAGER',
            serverDisplayName: 'سارة المطيري',
            fullName: 'سارة المطيري',
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول', settle: false, skipWelcome: false);
      expect(find.text('أهلًا، سارة المطيري'), findsOneWidget);
      expect(find.text('لوحة المدير'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('لوحة المدير'), findsOneWidget);
      expect(find.text('أهلًا، سارة المطيري'), findsNothing);
      expect(find.text('مرحبًا، سارة المطيري'), findsOneWidget);
    });

    testWidgets('English welcome keeps the Arabic logo and LTR copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            serverDisplayName: 'Ahmed Alghamdi',
            fullName: 'Ahmed Alghamdi',
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in', settle: false, skipWelcome: false);
      expect(find.text('Welcome, Ahmed Alghamdi'), findsOneWidget);
      expect(find.text('Welcome to Bayyin'), findsOneWidget);
      expect(
        find.image(const AssetImage(BayyinAssets.logo)),
        findsOneWidget,
      );
      expect(
        Directionality.of(
          tester.element(find.image(const AssetImage(BayyinAssets.logo))),
        ),
        TextDirection.ltr,
      );
      expect(find.text('My classes'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('My classes'), findsOneWidget);
      expect(find.text('Welcome to Bayyin'), findsNothing);
    });

    testWidgets('welcome animation does not loop after language change', (
      tester,
    ) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            serverDisplayName: 'أحمد الغامدي',
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      expect(find.text('صفوفي'), findsOneWidget);
      expect(find.text('أهلًا، أحمد الغامدي'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('أهلًا، أحمد الغامدي'), findsNothing);
      expect(find.text('صفوفي'), findsOneWidget);

      await _pickLanguage(tester, 'English');
      expect(find.text('My classes'), findsOneWidget);
      expect(find.text('أهلًا، أحمد الغامدي'), findsNothing);
      expect(find.text('Welcome to Bayyin'), findsNothing);
    });
  });

  group('لوحة المعلم', () {
    testWidgets('تعرض حالة التحميل قبل وصول البيانات', (tester) async {
      final pending = Completer<List<ClassroomRecord>>();
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classroomsFuture: pending.future,
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول', settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('جارٍ التحميل...'), findsOneWidget);
      expect(find.text('صفوفي'), findsNothing);

      pending.complete([_classroom6a]);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('صفوفي'), findsOneWidget);
    });

    testWidgets('تعرض بيانات الصف الحقيقية', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a, _classroom6b],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');

      expect(find.text('سادس أ'), findsOneWidget);
      expect(find.text('سادس ب'), findsOneWidget);
      // grade • subject on the first line, academic year • student count below.
      expect(find.textContaining('الصف السادس • الرياضيات'), findsOneWidget);
      expect(find.textContaining('1448 • 3 طلاب'), findsOneWidget);
    });

    testWidgets('لا تعرض أي بيانات تحليل وهمية', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');

      for (final mockText in [
        'تحليل جديد',
        'تحليل قيد التنفيذ',
        'مجموعات الاحتياج',
        'آخر تحليل مكتمل',
        '72٪',
        'التأسيس',
      ]) {
        expect(find.text(mockText), findsNothing, reason: 'mock: $mockText');
      }
    });

    testWidgets('تعرض حالة فارغة عندما لا توجد صفوف', (tester) async {
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'TEACHER')));
      await _signIn(tester, 'تسجيل الدخول');

      expect(
        find.text('لم يُسند إليك أي صف بعد. تواصل مع مدير المدرسة.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the empty state in English too', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER'),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');

      expect(
        find.text(
          'No classes are assigned to you yet. '
          'Please contact your school manager.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('تعرض حالة خطأ مع إمكانية إعادة المحاولة', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classroomsError: const ApiException(
              'تعذر إكمال الطلب. حاول مرة أخرى.',
            ),
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');

      expect(find.text('تعذر إكمال الطلب. حاول مرة أخرى.'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  });

  group('ترحيب المعلم', () {
    testWidgets('يعرض اسم المعلم القادم من الخادم', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            username: 'teacher-42',
            serverDisplayName: 'أحمد الغامدي',
            fullName: 'أحمد الغامدي',
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');

      expect(find.text('مرحبًا، أحمد الغامدي'), findsOneWidget);
      expect(find.text('مرحبًا، teacher-42'), findsNothing);
    });

    testWidgets('greets in English with the same backend name', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            username: 'teacher-42',
            serverDisplayName: 'Ahmed Alghamdi',
            fullName: 'Ahmed Alghamdi',
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');

      expect(find.text('Welcome, Ahmed Alghamdi'), findsOneWidget);
      expect(find.text('Welcome, teacher-42'), findsNothing);
    });

    testWidgets('يفضّل display_name على full_name', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            username: 'teacher-42',
            serverDisplayName: 'أحمد الغامدي',
            fullName: 'ignored full name',
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');

      expect(find.text('مرحبًا، أحمد الغامدي'), findsOneWidget);
    });

    testWidgets('يرجع إلى full_name عند غياب display_name', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            username: 'teacher-42',
            fullName: 'أحمد الغامدي',
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');

      expect(find.text('مرحبًا، أحمد الغامدي'), findsOneWidget);
    });

    testWidgets('يستخدم اسم المستخدم كملاذ أخير فقط', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', username: 'teacher-42'),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');

      expect(find.text('مرحبًا، teacher-42'), findsOneWidget);
    });

    testWidgets('لوحة المدير تستخدم نفس المصدر', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'MANAGER',
            username: 'manager-1',
            serverDisplayName: 'سارة المطيري',
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');

      expect(find.text('مرحبًا، سارة المطيري'), findsOneWidget);
      expect(find.text('مرحبًا، manager-1'), findsNothing);
    });

    test(
      'UserSession يطبق ترتيب الأولوية display_name ثم full_name ثم username',
      () {
        UserSession session({String display = '', String full = ''}) =>
            UserSession(
              token: 't',
              username: 'fallback-user',
              fullName: full,
              serverDisplayName: display,
              role: 'TEACHER',
            );

        expect(
          session(display: 'د. نورة', full: 'نورة').displayName,
          'د. نورة',
        );
        expect(session(full: 'نورة').displayName, 'نورة');
        expect(session().displayName, 'fallback-user');
        expect(
          session(display: '   ', full: '  ').displayName,
          'fallback-user',
        );
      },
    );
  });

  group('طلاب الصف', () {
    testWidgets('تفتح قائمة الطلاب عند الضغط على الصف', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            students: const [
              StudentRecord(
                id: 's1',
                internalCode: 'S-001',
                displayName: 'طالب أ',
              ),
              StudentRecord(id: 's2', internalCode: 'S-002', displayName: ''),
            ],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await tester.tap(find.text('سادس أ'));
      await tester.pumpAndSettle();

      expect(find.text('الطلاب'), findsOneWidget);
      expect(find.text('S-001'), findsOneWidget);
      expect(find.text('طالب أ'), findsOneWidget);
      expect(find.text('S-002'), findsOneWidget);
      expect(find.text('بدون اسم'), findsOneWidget);
    });

    testWidgets('shows an empty roster message', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      await tester.tap(find.text('سادس أ'));
      await tester.pumpAndSettle();

      expect(find.text('Students'), findsOneWidget);
      expect(
        find.text('There are no students in this class yet.'),
        findsOneWidget,
      );
      expect(find.text('Add student'), findsWidgets);
    });

    testWidgets('تتيح للمعلم إضافة طالب إلى صفه', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await tester.tap(find.text('سادس أ'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('إضافة طالب'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'S-010');
      await tester.enterText(find.byType(TextFormField).at(1), 'نورة');
      await tester.tap(find.widgetWithText(FilledButton, 'إضافة طالب').last);
      await tester.pumpAndSettle();

      expect(find.text('تمت إضافة الطالب.'), findsOneWidget);
      expect(find.text('S-010'), findsOneWidget);
      expect(find.text('نورة'), findsOneWidget);
    });
  });

  group('اختبارات المعلم', () {
    testWidgets('تعرض حالة التحميل قبل وصول الاختبارات', (tester) async {
      final pending = Completer<List<AssessmentRecord>>();
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessmentsFuture: pending.future,
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات', settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('جارٍ التحميل...'), findsOneWidget);

      pending.complete([_fractionsAssessment]);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('اختبار الكسور الأول'), findsOneWidget);
    });

    testWidgets('تعرض الاختبارات الحقيقية بأعدادها ودرجاتها', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');

      expect(find.text('اختبار الكسور الأول'), findsOneWidget);
      expect(find.textContaining('سادس أ • الرياضيات'), findsOneWidget);
      expect(find.textContaining('سؤالان'), findsOneWidget);
      expect(find.textContaining('مجموع الدرجات: 5'), findsOneWidget);
    });

    testWidgets('تعرض حالة فارغة عندما لا توجد اختبارات', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');

      expect(find.text('لا توجد اختبارات بعد'), findsOneWidget);
    });

    testWidgets('shows the assessments list in English', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      await _openAssessments(tester, 'Assessments');

      expect(find.text('Create assessment'), findsOneWidget);
      expect(find.textContaining('2 questions'), findsOneWidget);
      expect(find.textContaining('Total score: 5'), findsOneWidget);
    });

    testWidgets('shows the empty assessments state in English', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      await _openAssessments(tester, 'Assessments');

      expect(find.text('No assessments yet'), findsOneWidget);
    });

    testWidgets('تؤرشف الاختبار بالسحب وتظهره في الأرشيف', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');

      expect(find.text('الاختبارات المؤرشفة'), findsOneWidget);
      await _swipeAssessment(tester, archive: true);

      expect(find.text('اختبار الكسور الأول'), findsNothing);
      expect(find.text('لا توجد اختبارات بعد'), findsOneWidget);
      await _settleSnackBars(tester);

      await tester.tap(find.text('الاختبارات المؤرشفة'));
      await tester.pumpAndSettle();

      expect(find.text('اختبار الكسور الأول'), findsOneWidget);
      expect(find.text('الأحدث'), findsOneWidget);
      expect(find.text('الأقدم'), findsOneWidget);
    });

    testWidgets('تحذف الاختبار بعد التأكيد', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await _swipeAssessment(tester, archive: false);

      expect(find.text('حذف الاختبار'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'حذف الاختبار'));
      await tester.pumpAndSettle();

      expect(find.text('اختبار الكسور الأول'), findsNothing);
      await _settleSnackBars(tester);
    });

    testWidgets('ترتب الأرشيف من الأحدث إلى الأقدم', (tester) async {
      final older = AssessmentRecord(
        id: 'assessment-old',
        title: 'اختبار قديم',
        classroomId: 'class-6a',
        classroomName: 'سادس أ',
        grade: 'الصف السادس',
        subject: 'الرياضيات',
        questionsCount: 1,
        totalScore: 2,
        createdAt: DateTime.utc(2024, 1, 15),
        archivedAt: DateTime.utc(2025, 6, 1),
      );
      final newer = AssessmentRecord(
        id: 'assessment-new',
        title: 'اختبار جديد',
        classroomId: 'class-6a',
        classroomName: 'سادس أ',
        grade: 'الصف السادس',
        subject: 'الرياضيات',
        questionsCount: 1,
        totalScore: 2,
        createdAt: DateTime.utc(2025, 8, 20),
        archivedAt: DateTime.utc(2025, 9, 1),
      );
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [older, newer],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('الاختبارات المؤرشفة'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('اختبار جديد')).dy,
        lessThan(tester.getTopLeft(find.text('اختبار قديم')).dy),
      );

      await tester.tap(find.text('الأقدم'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('اختبار قديم')).dy,
        lessThan(tester.getTopLeft(find.text('اختبار جديد')).dy),
      );
    });

    testWidgets('تستعيد اختبارًا من الأرشيف', (tester) async {
      final archived = _fractionsAssessment.copyWith(
        archivedAt: DateTime.utc(2026, 1, 1),
      );
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [archived],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      expect(find.text('اختبار الكسور الأول'), findsNothing);

      await tester.tap(find.text('الاختبارات المؤرشفة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('استعادة'));
      await tester.pumpAndSettle();
      expect(find.text('تمت استعادة الاختبار.'), findsOneWidget);
      await _settleSnackBars(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('اختبار الكسور الأول'), findsOneWidget);
    });

    testWidgets('archives and sorts assessments in English', (tester) async {
      final archived = AssessmentRecord(
        id: 'assessment-old',
        title: 'Older fractions test',
        classroomId: 'class-6a',
        classroomName: 'Class 6A',
        grade: 'Grade 6',
        subject: 'Math',
        questionsCount: 1,
        totalScore: 2,
        createdAt: DateTime.utc(2024, 1, 15),
        archivedAt: DateTime.utc(2025, 6, 1),
      );
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [archived, _fractionsAssessment],
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      await _openAssessments(tester, 'Assessments');

      expect(find.text('Archived assessments'), findsOneWidget);
      expect(
        find.text('Swipe a card to archive or delete it.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Archived assessments'));
      await tester.pumpAndSettle();

      expect(find.text('Older fractions test'), findsOneWidget);
      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Oldest'), findsOneWidget);
      expect(
        find.text('Saved so you can reuse them in later years.'),
        findsOneWidget,
      );
    });
  });

  group('إنشاء اختبار', () {
    testWidgets('ترفض الحفظ بدون اسم اختبار', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('إنشاء اختبار'));
      await tester.pumpAndSettle();

      expect(find.text('اسم الاختبار'), findsOneWidget);
      expect(find.text('الصف'), findsOneWidget);
      expect(find.text('اختياري'), findsOneWidget);
      expect(find.text('اختيار ملف'), findsOneWidget);

      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('مطلوب'), findsOneWidget);
      expect(find.text('الأسئلة'), findsNothing);
    });

    testWidgets('تنشئ الاختبار وتفتح تفاصيله', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('إنشاء اختبار'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'اختبار الكسور الأول');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('اختبار الكسور الأول'), findsOneWidget);
      expect(find.text('الأسئلة'), findsOneWidget);
      expect(find.text('لا توجد أسئلة بعد'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('creates an assessment in English too', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      await _openAssessments(tester, 'Assessments');
      await tester.tap(find.text('Create assessment'));
      await tester.pumpAndSettle();

      expect(find.text('Assessment details'), findsOneWidget);
      expect(find.text('Optional'), findsOneWidget);
      expect(find.text('Choose file'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField),
        'First fractions test',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Questions'), findsOneWidget);
      expect(find.text('No questions yet'), findsOneWidget);
      await _settleSnackBars(tester);
    });
  });

  group('أسئلة الاختبار', () {
    testWidgets('تعرض أسئلة الاختبار بدرجاتها وإجاباتها', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();

      expect(find.text('ما ناتج 1/2 + 1/4؟'), findsOneWidget);
      expect(find.textContaining('الدرجة القصوى: 2'), findsOneWidget);
      expect(find.textContaining('الإجابة النموذجية: 3/4'), findsOneWidget);
      expect(find.text('بسّط الكسر 4/8'), findsOneWidget);
      expect(find.textContaining('الدرجة القصوى: 3'), findsOneWidget);
    });

    testWidgets('تختصر الإجابة النموذجية الطويلة حتى التوسيع', (tester) async {
      const longAnswer =
          'لأننا ضربنا البسط والمقام في هذه نسخة اختبار تجريبية تحتوي على نموذج الإجابة لاختبار الاستخراج والمراجعة فقط.';
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [
              AssessmentRecord(
                id: 'assessment-1',
                title: 'اختبار الكسور الأول',
                classroomId: 'class-6a',
                classroomName: 'سادس أ',
                grade: 'الصف السادس',
                subject: 'الرياضيات',
                questionsCount: 1,
                totalScore: 2,
                questions: const [
                  QuestionRecord(
                    id: 'question-1',
                    order: 1,
                    text: 'اشرح لماذا',
                    maxScore: 2,
                    modelAnswer: longAnswer,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();

      expect(find.text('عرض المزيد'), findsOneWidget);
      expect(find.text('عرض أقل'), findsNothing);

      await tester.ensureVisible(find.text('عرض المزيد'));
      await tester.tap(find.text('عرض المزيد'));
      await tester.pumpAndSettle();

      expect(find.text('عرض أقل'), findsOneWidget);
      expect(find.textContaining(longAnswer), findsOneWidget);
    });

    testWidgets('ترفض درجة قصوى غير موجبة', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_emptyAssessment],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة سؤال'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'سؤال بلا درجة');
      await tester.enterText(find.byType(TextFormField).at(1), '0');
      await tester.enterText(find.byType(TextFormField).at(2), 'إجابة');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('أدخل رقمًا أكبر من صفر'), findsOneWidget);
      // The dialog stayed open and nothing reached the questions list.
      expect(find.text('لا توجد أسئلة بعد'), findsOneWidget);
      expect(find.textContaining('الدرجة القصوى: '), findsNothing);
    });

    testWidgets('تضيف سؤالًا وتعرضه في القائمة', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_emptyAssessment],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();

      expect(find.text('لا توجد أسئلة بعد'), findsOneWidget);

      await tester.tap(find.text('إضافة سؤال'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'ما ناتج 1/2 + 1/4؟',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '2');
      await tester.enterText(find.byType(TextFormField).at(2), '3/4');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('لا توجد أسئلة بعد'), findsNothing);
      expect(find.text('ما ناتج 1/2 + 1/4؟'), findsOneWidget);
      expect(find.textContaining('الدرجة القصوى: 2'), findsOneWidget);
      expect(find.textContaining('الإجابة النموذجية: 3/4'), findsOneWidget);
      expect(find.textContaining('سؤال واحد'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('تحذف سؤالًا محفوظًا بعد التأكيد', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('حذف السؤال').first);
      await tester.pumpAndSettle();
      expect(find.text('هل تريد حذف هذا السؤال؟'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'حذف السؤال'));
      await tester.pumpAndSettle();

      expect(find.text('ما ناتج 1/2 + 1/4؟'), findsNothing);
      expect(find.text('بسّط الكسر 4/8'), findsOneWidget);
      expect(find.text('تم حذف السؤال.'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('تحذف كل الأسئلة السابقة', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('خيارات الأسئلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف جميع الأسئلة'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('هل تريد حذف كل الأسئلة الحالية'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'حذف الأسئلة'));
      await tester.pumpAndSettle();

      expect(find.text('لا توجد أسئلة بعد'), findsOneWidget);
      expect(find.text('ما ناتج 1/2 + 1/4؟'), findsNothing);
      expect(find.text('تم حذف الأسئلة.'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('adds a question in English too', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_emptyAssessment],
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      await _openAssessments(tester, 'Assessments');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();

      expect(find.text('How it works'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('How it works'))),
        TextDirection.ltr,
      );
      expect(find.text('Exam setup'), findsOneWidget);
      expect(find.text('Student work'), findsOneWidget);
      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Upload exam paper'), findsOneWidget);
      expect(find.text('Student submissions'), findsOneWidget);
      expect(find.text('Class insights'), findsOneWidget);
      expect(find.text('No questions yet'), findsOneWidget);
      expect(
        find.text('Upload the exam paper or add a question manually.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Add question'));
      await tester.pumpAndSettle();

      expect(find.text('Question text'), findsOneWidget);
      expect(find.text('Maximum score'), findsOneWidget);
      expect(find.text('Model answer'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'What is 1/2 + 1/4?',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '2.5');
      await tester.enterText(find.byType(TextFormField).at(2), '3/4');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('What is 1/2 + 1/4?'), findsOneWidget);
      expect(find.textContaining('Max score: 2.5'), findsOneWidget);
      expect(find.textContaining('1 question'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('deletes saved questions in English', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      await _openAssessments(tester, 'Assessments');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Question options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all questions'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete questions'));
      await tester.pumpAndSettle();

      expect(find.text('No questions yet'), findsOneWidget);
      expect(find.text('Questions deleted.'), findsOneWidget);
      await _settleSnackBars(tester);
    });
  });

  group('رفع ورقة الاختبار واستخراج الأسئلة', () {
    const extracted = [
      QuestionCandidateRecord(
        id: 'cand-1',
        order: 1,
        extractedText: 'ما ناتج 1/2 + 1/4؟',
        proposedMaxScore: 2,
        proposedModelAnswer: '3/4',
      ),
      QuestionCandidateRecord(
        id: 'cand-2',
        order: 2,
        extractedText: 'بسّط الكسر 4/8',
        proposedMaxScore: 3,
        proposedModelAnswer: '1/2',
      ),
    ];

    FakeGateway gatewayWith({
      Completer<void>? examUploadGate,
      Completer<void>? extractGate,
      Object? extractError,
      List<QuestionCandidateRecord> questionCandidates = extracted,
    }) => FakeGateway(
      role: 'TEACHER',
      classrooms: [_classroom6a],
      assessments: [_emptyAssessment],
      questionCandidates: questionCandidates,
      examUploadGate: examUploadGate,
      extractGate: extractGate,
      extractError: extractError,
    );

    Future<void> openDetails(WidgetTester tester, FakeGateway gateway) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gateway,
          picker: FakeAttachmentPicker(filename: 'ورقة.jpg'),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();
    }

    testWidgets('تعرض مدخل رفع ورقة الاختبار', (tester) async {
      await openDetails(tester, gatewayWith());

      expect(find.text('طريقة العمل'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('طريقة العمل'))),
        TextDirection.rtl,
      );
      expect(find.text('إعداد الاختبار'), findsOneWidget);
      expect(find.text('عمل الطلاب'), findsOneWidget);
      expect(find.text('رفع ورقة الاختبار'), findsOneWidget);
      expect(find.text('إضافة سؤال'), findsOneWidget);
      expect(find.text('تسليمات الطلاب'), findsOneWidget);
      expect(find.text('تحليل الصف'), findsOneWidget);
      expect(find.text('لا توجد أسئلة بعد'), findsOneWidget);
      expect(
        find.text('ارفع ورقة الاختبار أو أضف سؤالًا يدويًا.'),
        findsOneWidget,
      );
    });

    testWidgets('تعرض حالة رفع ورقة الاختبار', (tester) async {
      final gate = Completer<void>();
      await openDetails(tester, gatewayWith(examUploadGate: gate));
      await tester.tap(find.text('رفع ورقة الاختبار'));
      await tester.pump();
      await tester.pump();

      expect(find.text('جاري رفع ورقة الاختبار'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('تعرض حالة استخراج الأسئلة', (tester) async {
      final gate = Completer<void>();
      await openDetails(tester, gatewayWith(extractGate: gate));
      await tester.tap(find.text('رفع ورقة الاختبار'));
      await tester.pump();
      await tester.pump();

      expect(find.text('جاري استخراج الأسئلة'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('تعرض الأسئلة المستخرجة', (tester) async {
      await openDetails(tester, gatewayWith());
      await tester.tap(find.text('رفع ورقة الاختبار'));
      await tester.pumpAndSettle();

      expect(find.text('مراجعة الأسئلة'), findsOneWidget);
      expect(find.text('راجع الأسئلة المستخرجة قبل اعتمادها.'), findsOneWidget);
      expect(find.text('سؤالان مستخرجان'), findsOneWidget);
      expect(find.text('ما ناتج 1/2 + 1/4؟'), findsOneWidget);
      expect(find.text('بسّط الكسر 4/8'), findsOneWidget);
      expect(find.text('السؤال المستخرج'), findsWidgets);
      expect(find.text('الدرجة المقترحة'), findsWidgets);
      expect(find.text('تأكيد الأسئلة'), findsOneWidget);
      expect(find.text('إضافة سؤال يدويًا'), findsOneWidget);
    });

    testWidgets('تعدّل نص السؤال والدرجة والإجابة النموذجية', (tester) async {
      final gateway = gatewayWith();
      await openDetails(tester, gateway);
      await tester.tap(find.text('رفع ورقة الاختبار'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'ما ناتج نصف زائد ربع؟',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '4');
      await tester.enterText(find.byType(TextFormField).at(2), 'ثلاثة أرباع');
      await tester.tap(find.text('تأكيد الأسئلة'));
      await tester.pumpAndSettle();

      expect(gateway.confirmQuestionsCalls, 1);
      expect(find.text('ما ناتج نصف زائد ربع؟'), findsOneWidget);
      expect(find.textContaining('الدرجة القصوى: 4'), findsOneWidget);
      expect(
        find.textContaining('الإجابة النموذجية: ثلاثة أرباع'),
        findsOneWidget,
      );
      await _settleSnackBars(tester);
    });

    testWidgets('تحذف سؤالًا مستخرجًا وتضيف سؤالًا يدويًا', (tester) async {
      final gateway = gatewayWith();
      await openDetails(tester, gateway);
      await tester.tap(find.text('رفع ورقة الاختبار'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('حذف السؤال').at(1));
      await tester.pumpAndSettle();
      expect(find.text('بسّط الكسر 4/8'), findsNothing);
      expect(find.text('سؤال واحد مستخرج'), findsOneWidget);

      await tester.tap(find.text('إضافة سؤال يدويًا'));
      await tester.pumpAndSettle();
      expect(find.text('سؤالان مستخرجان'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(3), 'ما هو الكسر؟');
      await tester.enterText(find.byType(TextFormField).at(4), '1');
      await tester.enterText(find.byType(TextFormField).at(5), 'جزء من كل');
      await tester.tap(find.text('تأكيد الأسئلة'));
      await tester.pumpAndSettle();

      expect(find.text('ما هو الكسر؟'), findsOneWidget);
      expect(find.text('بسّط الكسر 4/8'), findsNothing);
      await _settleSnackBars(tester);
    });

    testWidgets('تعرض أخطاء التحقق بجانب حقول السؤال والدرجة', (tester) async {
      final gateway = gatewayWith();
      await openDetails(tester, gateway);
      await tester.tap(find.text('رفع ورقة الاختبار'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '');
      await tester.tap(find.text('تأكيد الأسئلة'));
      await tester.pumpAndSettle();

      expect(find.text('مطلوب'), findsOneWidget);
      expect(gateway.confirmQuestionsCalls, 0);

      await tester.enterText(find.byType(TextFormField).at(0), 'ما ناتج نصف؟');
      await tester.enterText(find.byType(TextFormField).at(1), '0');
      await tester.tap(find.text('تأكيد الأسئلة'));
      await tester.pumpAndSettle();

      expect(find.text('أدخل رقمًا أكبر من صفر'), findsOneWidget);
      expect(gateway.confirmQuestionsCalls, 0);
    });

    testWidgets('تعرض أنه لم يتم العثور على أسئلة', (tester) async {
      await openDetails(tester, gatewayWith(questionCandidates: const []));
      await tester.tap(find.text('رفع ورقة الاختبار'));
      await tester.pumpAndSettle();

      expect(find.text('لم يتم العثور على أسئلة'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });

    testWidgets('تعرض خطأ الاستخراج دون تفاصيل المزود', (tester) async {
      await openDetails(
        tester,
        gatewayWith(extractError: const ApiException('Tesseract failed')),
      );
      await tester.tap(find.text('رفع ورقة الاختبار'));
      await tester.pumpAndSettle();

      expect(find.text('تعذر استخراج الأسئلة'), findsOneWidget);
      expect(find.text('Tesseract failed'), findsNothing);
    });

    testWidgets('reviews extracted questions in English too', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(),
          picker: FakeAttachmentPicker(filename: 'paper.jpg'),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      await _openAssessments(tester, 'Assessments');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();

      expect(find.text('Upload exam paper'), findsOneWidget);
      await tester.tap(find.text('Upload exam paper'));
      await tester.pumpAndSettle();

      expect(find.text('Review questions'), findsOneWidget);
      expect(
        find.text('Review extracted questions before confirming.'),
        findsOneWidget,
      );
      expect(find.text('2 questions found'), findsOneWidget);
      expect(find.text('Extracted question'), findsWidgets);
      expect(find.text('Suggested score'), findsWidgets);
      expect(find.text('Add question manually'), findsOneWidget);
      expect(find.text('Confirm questions'), findsOneWidget);
    });
  });

  group('تسليمات الطلاب', () {
    testWidgets('تعرض طلاب الصف مع حالة كل واحد', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
            students: _roster,
            submissions: [_existingSubmission],
          ),
        ),
      );
      await _reachSubmissions(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );

      expect(find.text('طالب أ'), findsOneWidget);
      expect(find.text('S-001'), findsOneWidget);
      expect(find.text('بدون اسم'), findsOneWidget);
      expect(find.text('S-002'), findsOneWidget);
      expect(find.text('تم الإدخال'), findsOneWidget);
      expect(find.text('لم يُدخل'), findsOneWidget);
      expect(find.text('تم إدخال 1 من 2'), findsOneWidget);
      expect(
        find.text(
          'اختر اسم الطالب لرفع ورقته ومطابقتها مع ورقة الاختبار الأصلية.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('تعرض حالة عدم وجود تسليمات', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
            students: _roster,
          ),
        ),
      );
      await _reachSubmissions(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );

      expect(find.text('لا توجد تسليمات بعد'), findsOneWidget);
      expect(find.text('لم يُدخل'), findsNWidgets(2));
      expect(find.text('تم الإدخال'), findsNothing);
    });

    testWidgets('تعرض حالة صف بلا طلاب', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
          ),
        ),
      );
      await _reachSubmissions(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );

      expect(find.text('لا يوجد طلاب في هذا الصف بعد.'), findsOneWidget);
    });

    testWidgets('shows the roster in English', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
            students: _roster,
            submissions: [_existingSubmission],
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _reachSubmissions(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );

      expect(find.text('Entered'), findsOneWidget);
      expect(find.text('Not entered'), findsOneWidget);
      expect(find.text('1 of 2 entered'), findsOneWidget);
      expect(find.text('Unnamed'), findsOneWidget);
    });
  });

  group('إدخال إجابات التسليم', () {
    testWidgets('تنشئ تسليمًا عند اختيار طالب بلا تسليم', (tester) async {
      final gateway = FakeGateway(
        role: 'TEACHER',
        classrooms: [_classroom6a],
        assessments: [_fractionsAssessment],
        students: _roster,
      );
      _useTallViewport(tester);
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _reachSubmissions(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();

      expect(gateway.createSubmissionCalls, 1);
      expect(find.text('إجابة الطالب'), findsNWidgets(2));
      expect(find.text('ما ناتج 1/2 + 1/4؟'), findsOneWidget);
      expect(find.text('حفظ الإجابات'), findsOneWidget);
    });

    testWidgets('تفتح التسليم الموجود بدل إنشاء تسليم مكرر', (tester) async {
      final gateway = FakeGateway(
        role: 'TEACHER',
        classrooms: [_classroom6a],
        assessments: [_fractionsAssessment],
        students: _roster,
        submissions: [_existingSubmission],
      );
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _reachSubmissions(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();

      expect(gateway.createSubmissionCalls, 0);
      // The answer already stored on the server shows up in the field.
      expect(find.text('3/4'), findsOneWidget);
    });

    testWidgets('تعرض الأسئلة بترتيبها ودرجاتها', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
            students: _roster,
            submissions: [_existingSubmission],
          ),
        ),
      );
      await _reachSubmissions(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();

      expect(find.text('السؤال 1'), findsOneWidget);
      expect(find.text('السؤال 2'), findsOneWidget);
      expect(find.text('الدرجة القصوى: 2'), findsOneWidget);
      expect(find.text('الدرجة القصوى: 3'), findsOneWidget);
      expect(find.text('S-001'), findsOneWidget);
    });

    testWidgets('تتبع اتجاه الواجهة في مساحة المراجعة', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
            students: _roster,
            submissions: [_existingSubmission],
          ),
        ),
      );
      await _reachSubmissions(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.text('ورقة الطالب'))),
        TextDirection.rtl,
      );
      expect(find.text('حفظ الإجابات'), findsOneWidget);
      expect(find.text('نتيجة الاختبار'), findsOneWidget);
      expect(find.text('ورقة الاختبار'), findsWidgets);
    });

    testWidgets('keeps the review workspace in LTR English', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
            students: _roster,
            submissions: [_existingSubmission],
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _reachSubmissions(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.text('Student paper'))),
        TextDirection.ltr,
      );
      expect(find.text('Save answers'), findsOneWidget);
      expect(find.text('Add file'), findsOneWidget);
      expect(find.text('Analyze'), findsWidgets);
      expect(find.text('Assessment result'), findsOneWidget);
    });

    testWidgets('تحفظ الإجابات المعدلة وتؤكد الحفظ', (tester) async {
      final gateway = FakeGateway(
        role: 'TEACHER',
        classrooms: [_classroom6a],
        assessments: [_fractionsAssessment],
        students: _roster,
        submissions: [_existingSubmission],
      );
      _useTallViewport(tester);
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _reachSubmissions(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'ثلاثة أرباع');
      await tester.enterText(find.byType(TextField).at(1), '1/2');
      await _scrollAndTap(tester, 'حفظ الإجابات');

      expect(find.text('تم الحفظ'), findsOneWidget);
      await _settleSnackBars(tester);

      // Reopening the submission shows what the gateway stored. The back
      // button is found by type because its tooltip follows the app locale.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();

      expect(find.text('ثلاثة أرباع'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('تعرض حالة اختبار بلا أسئلة', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_emptyAssessment],
            students: _roster,
          ),
        ),
      );
      await _reachSubmissions(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();

      expect(find.text('لا توجد أسئلة في هذا الاختبار'), findsOneWidget);
      expect(find.text('حفظ الإجابات'), findsNothing);
      expect(find.text('الاختبار غير قابل للتقييم'), findsOneWidget);
    });

    testWidgets('enters and saves answers in English', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
            students: _roster,
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _reachSubmissions(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();

      expect(find.text('Student answer'), findsNWidgets(2));
      expect(find.text('Question 1'), findsOneWidget);
      expect(find.text('Max score: 2'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), '3/4');
      await _scrollAndTap(tester, 'Save answers');

      expect(find.text('Saved'), findsOneWidget);
      await _settleSnackBars(tester);
    });
  });

  group('مرفقات ورقة الطالب', () {
    FakeGateway gatewayWith({
      List<AttachmentRecord> attachments = const [],
      Object? uploadError,
      Completer<void>? uploadGate,
    }) => FakeGateway(
      role: 'TEACHER',
      classrooms: [_classroom6a],
      assessments: [_fractionsAssessment],
      students: _roster,
      submissions: [_existingSubmission],
      attachments: attachments,
      uploadError: uploadError,
      uploadGate: uploadGate,
    );

    Future<void> openArabicEntry(WidgetTester tester) => _reachEntry(
      tester,
      signIn: 'تسجيل الدخول',
      assessments: 'الاختبارات',
      submissions: 'تسليمات الطلاب',
    );

    testWidgets('تعرض حالة عدم وجود ملفات', (tester) async {
      await tester.pumpWidget(
        BayyinApp(gateway: gatewayWith(), picker: FakeAttachmentPicker()),
      );
      await openArabicEntry(tester);

      expect(find.text('ورقة الطالب'), findsOneWidget);
      expect(find.text('لا توجد ملفات مرفوعة'), findsOneWidget);
      expect(find.text('إضافة ملف'), findsOneWidget);
      expect(find.text('تحليل'), findsOneWidget);
    });

    testWidgets('تطلب ورقة الطالب قبل التحليل', (tester) async {
      await tester.pumpWidget(
        BayyinApp(gateway: gatewayWith(), picker: FakeAttachmentPicker()),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('تحليل'));
      await tester.pumpAndSettle();

      expect(
        find.text('ارفع ورقة الطالب أولًا ثم اضغط تحليل.'),
        findsOneWidget,
      );
      await _settleSnackBars(tester);
    });

    testWidgets('تعرض الملفات المرفوعة باسمها ونوعها وحجمها', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(attachments: [_existingAttachment]),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);

      expect(find.text('ورقة-الطالب.jpg'), findsOneWidget);
      expect(find.text('JPEG · 2 كيلوبايت'), findsOneWidget);
      expect(find.text('لا توجد ملفات مرفوعة'), findsNothing);
    });

    testWidgets('تعرض حالة الرفع حتى يرد الخادم', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(uploadGate: gate),
          picker: FakeAttachmentPicker(filename: 'page.png'),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('إضافة ملف'));
      await tester.pump();
      await tester.pump();

      expect(find.text('جاري الرفع…'), findsOneWidget);
      expect(find.text('إضافة ملف'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('page.png'), findsOneWidget);
      expect(find.text('إضافة ملف'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('ترفع ملفًا وتضيفه إلى القائمة', (tester) async {
      final gateway = gatewayWith();
      await tester.pumpWidget(
        BayyinApp(
          gateway: gateway,
          picker: FakeAttachmentPicker(filename: 'صفحة-2.pdf'),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('إضافة ملف'));
      await tester.pumpAndSettle();

      expect(find.text('صفحة-2.pdf'), findsOneWidget);
      expect(find.text('PDF · 2 كيلوبايت'), findsOneWidget);
      expect(find.text('تم رفع الملف'), findsOneWidget);
      expect(gateway.uploadCalls, 1);
      await _settleSnackBars(tester);
    });

    testWidgets('تعرض رسالة الخادم عند فشل الرفع', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            uploadError: const ApiException('نوع الملف غير مدعوم.'),
          ),
          picker: FakeAttachmentPicker(filename: 'page.jpg'),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('إضافة ملف'));
      await tester.pumpAndSettle();

      expect(find.text('نوع الملف غير مدعوم.'), findsOneWidget);
      expect(find.text('لا توجد ملفات مرفوعة'), findsOneWidget);
    });

    testWidgets('ترفض نوعًا غير مدعوم قبل مغادرة الجهاز', (tester) async {
      final gateway = gatewayWith();
      await tester.pumpWidget(
        BayyinApp(
          gateway: gateway,
          picker: FakeAttachmentPicker(filename: 'ملاحظات.txt'),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('إضافة ملف'));
      await tester.pumpAndSettle();

      expect(find.text('نوع الملف غير مدعوم'), findsOneWidget);
      expect(gateway.uploadCalls, 0);
    });

    testWidgets('ترفض ملفًا أكبر من الحد قبل مغادرة الجهاز', (tester) async {
      final gateway = gatewayWith();
      await tester.pumpWidget(
        BayyinApp(
          gateway: gateway,
          picker: FakeAttachmentPicker(
            filename: 'كبير.jpg',
            byteCount: maxAttachmentBytes + 1,
          ),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('إضافة ملف'));
      await tester.pumpAndSettle();

      expect(find.text('حجم الملف كبير جدًا'), findsOneWidget);
      expect(gateway.uploadCalls, 0);
    });

    testWidgets('لا ترفع شيئًا عند إغلاق نافذة الاختيار', (tester) async {
      final gateway = gatewayWith();
      await tester.pumpWidget(
        BayyinApp(gateway: gateway, picker: FakeAttachmentPicker()),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('إضافة ملف'));
      await tester.pumpAndSettle();

      expect(gateway.uploadCalls, 0);
      expect(find.text('لا توجد ملفات مرفوعة'), findsOneWidget);
    });

    testWidgets('تحتفظ بالملف عند إلغاء تأكيد الحذف', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(attachments: [_existingAttachment]),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('هل تريد حذف هذا الملف؟'), findsOneWidget);

      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      expect(find.text('ورقة-الطالب.jpg'), findsOneWidget);
    });

    testWidgets('تحذف الملف بعد التأكيد', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(attachments: [_existingAttachment]),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'حذف الملف'));
      await tester.pumpAndSettle();

      expect(find.text('ورقة-الطالب.jpg'), findsNothing);
      expect(find.text('لا توجد ملفات مرفوعة'), findsOneWidget);
      expect(find.text('تم حذف الملف'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('uploads and deletes a file in English', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(),
          picker: FakeAttachmentPicker(filename: 'page-1.png'),
          initialLocale: AppLocale.english,
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );

      expect(find.text('Student paper'), findsOneWidget);
      expect(find.text('No files attached'), findsOneWidget);

      await tester.tap(find.text('Add file'));
      await tester.pumpAndSettle();

      expect(find.text('page-1.png'), findsOneWidget);
      expect(find.text('PNG · 2 KB'), findsOneWidget);
      expect(find.text('File uploaded'), findsOneWidget);
      await _settleSnackBars(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete this file?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete file'));
      await tester.pumpAndSettle();

      expect(find.text('File deleted'), findsOneWidget);
      expect(find.text('No files attached'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('reports an unsupported type in English', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(),
          picker: FakeAttachmentPicker(filename: 'notes.txt'),
          initialLocale: AppLocale.english,
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );
      await tester.tap(find.text('Add file'));
      await tester.pumpAndSettle();

      expect(find.text('Unsupported file type'), findsOneWidget);
    });
  });

  group('التعرف الضوئي على ورقة الطالب', () {
    FakeGateway gatewayWith({
      List<AttachmentRecord> attachments = const [_existingAttachment],
      Map<String, OcrRecord> ocrResults = const {},
      Object? ocrError,
      Completer<void>? ocrGate,
      String ocrText = 'ثلاثة أرباع',
    }) => FakeGateway(
      role: 'TEACHER',
      classrooms: [_classroom6a],
      assessments: [_fractionsAssessment],
      students: _roster,
      submissions: [_existingSubmission],
      attachments: attachments,
      ocrResults: ocrResults,
      ocrError: ocrError,
      ocrGate: ocrGate,
      ocrText: ocrText,
    );

    Future<void> openArabicEntry(WidgetTester tester) async {
      _useTallViewport(tester);
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
    }

    testWidgets('تعرض أن النص لم يُستخرج بعد', (tester) async {
      await tester.pumpWidget(
        BayyinApp(gateway: gatewayWith(), picker: FakeAttachmentPicker()),
      );
      await openArabicEntry(tester);

      expect(find.text('لم يتم استخراج النص بعد'), findsOneWidget);
      expect(find.text('استخراج النص'), findsOneWidget);
    });

    testWidgets('تعرض حالة الاستخراج حتى يرد الخادم', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(ocrGate: gate),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('استخراج النص'));
      await tester.pump();
      await tester.pump();

      expect(find.text('جاري استخراج النص…'), findsOneWidget);
      expect(find.text('استخراج النص'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('ثلاثة أرباع'), findsOneWidget);
      expect(find.text('عرض النص'), findsOneWidget);
    });

    testWidgets('تعرض النص بعد نجاح الاستخراج', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(ocrResults: {'attachment-1': _completedOcr}),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);

      expect(find.text('الإجابة هي ثلاثة أرباع'), findsOneWidget);
      expect(find.text('عرض النص'), findsOneWidget);
      expect(find.text('استخراج النص'), findsNothing);
    });

    testWidgets('تفتح شاشة النص المستخرج', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(ocrResults: {'attachment-1': _completedOcr}),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('عرض النص'));
      await tester.pumpAndSettle();

      expect(find.text('النص المستخرج'), findsWidgets);
      expect(find.text('ورقة-الطالب.jpg'), findsWidgets);
      expect(find.text('الإجابة هي ثلاثة أرباع'), findsOneWidget);
    });

    testWidgets('تعرض الفشل مع إعادة المحاولة', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(ocrResults: {'attachment-1': _failedOcr}),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);

      expect(find.text('تعذر استخراج النص'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });

    testWidgets('تعيد المحاولة بعد الفشل', (tester) async {
      final gateway = gatewayWith(ocrResults: {'attachment-1': _failedOcr});
      await tester.pumpWidget(
        BayyinApp(gateway: gateway, picker: FakeAttachmentPicker()),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();

      expect(find.text('ثلاثة أرباع'), findsOneWidget);
      expect(find.text('تعذر استخراج النص'), findsNothing);
      expect(gateway.runOcrCalls, 1);
    });

    testWidgets('كل مرفق له حالة استخراج مستقلة', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            attachments: [_existingAttachment, _secondAttachment],
            ocrResults: {'attachment-1': _completedOcr},
          ),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);

      expect(find.text('الإجابة هي ثلاثة أرباع'), findsOneWidget);
      expect(find.text('لم يتم استخراج النص بعد'), findsOneWidget);
      expect(find.text('استخراج النص'), findsOneWidget);
      expect(find.text('عرض النص'), findsOneWidget);
    });

    testWidgets('extracts and shows text in English', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(ocrText: 'three quarters'),
          picker: FakeAttachmentPicker(),
          initialLocale: AppLocale.english,
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );

      expect(find.text('Text has not been extracted yet'), findsOneWidget);
      await tester.tap(find.text('Extract text'));
      await tester.pumpAndSettle();

      expect(find.text('three quarters'), findsOneWidget);
      expect(find.text('View text'), findsOneWidget);
    });

    testWidgets('shows a failed OCR state in English', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(ocrResults: {'attachment-1': _failedOcr}),
          picker: FakeAttachmentPicker(),
          initialLocale: AppLocale.english,
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );

      expect(find.text('Could not extract text'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('مراجعة الإجابات المستخرجة', () {
    const mapped = OcrMappingRecord(
      candidates: [
        OcrCandidateRecord(
          id: 'cand-1',
          questionId: 'question-1',
          order: 1,
          questionText: 'ما ناتج 1/2 + 1/4؟',
          maxScore: 2,
          extractedText: '3/4',
          status: 'suggested',
          currentAnswer: '',
        ),
        OcrCandidateRecord(
          id: 'cand-2',
          questionId: 'question-2',
          order: 2,
          questionText: 'بسّط الكسر 4/8',
          maxScore: 3,
          extractedText: '',
          status: 'suggested',
          currentAnswer: '',
        ),
      ],
      incompleteOcr: false,
    );

    const mappedWithManual = OcrMappingRecord(
      candidates: [
        OcrCandidateRecord(
          id: 'cand-1',
          questionId: 'question-1',
          order: 1,
          questionText: 'ما ناتج 1/2 + 1/4؟',
          maxScore: 2,
          extractedText: 'من الورقة',
          status: 'suggested',
          currentAnswer: 'يدوي',
        ),
        OcrCandidateRecord(
          id: 'cand-2',
          questionId: 'question-2',
          order: 2,
          questionText: 'بسّط الكسر 4/8',
          maxScore: 3,
          extractedText: '1/2',
          status: 'suggested',
          currentAnswer: '',
        ),
      ],
      incompleteOcr: false,
    );

    FakeGateway gatewayWith({
      Map<String, OcrRecord> ocrResults = const {},
      OcrMappingRecord? ocrMapping,
      Object? mappingError,
      Completer<void>? mappingGate,
      List<SubmissionRecord>? submissions,
    }) => FakeGateway(
      role: 'TEACHER',
      classrooms: [_classroom6a],
      assessments: [_fractionsAssessment],
      students: _roster,
      submissions: submissions ?? [_existingSubmission],
      attachments: [_existingAttachment],
      ocrResults: ocrResults,
      ocrMapping: ocrMapping,
      mappingError: mappingError,
      mappingGate: mappingGate,
    );

    Future<void> openArabicEntry(WidgetTester tester) async {
      _useTallViewport(tester);
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
    }

    testWidgets('لا تعرض المراجعة قبل اكتمال الاستخراج', (tester) async {
      await tester.pumpWidget(
        BayyinApp(gateway: gatewayWith(), picker: FakeAttachmentPicker()),
      );
      await openArabicEntry(tester);

      expect(find.text('مراجعة الإجابات المستخرجة'), findsNothing);
    });

    testWidgets('تعرض حالة التحميل أثناء استخراج الإجابات', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            ocrResults: {'attachment-1': _completedOcr},
            ocrMapping: mapped,
            mappingGate: gate,
          ),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('مراجعة الإجابات المستخرجة'));
      await tester.pump();
      await tester.pump();

      expect(find.text('استخراج الإجابات'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('الإجابة المستخرجة'), findsOneWidget);
    });

    testWidgets('تعرض الاقتراحات والحقل الفارغ', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            ocrResults: {'attachment-1': _completedOcr},
            ocrMapping: mapped,
          ),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('مراجعة الإجابات المستخرجة'));
      await tester.pumpAndSettle();

      expect(find.text('ما ناتج 1/2 + 1/4؟'), findsOneWidget);
      expect(find.text('لم يتم التعرف على إجابة'), findsOneWidget);
      expect(find.text('تأكيد الإجابات'), findsOneWidget);
      expect(find.text('3/4'), findsWidgets);
    });

    testWidgets('تُبقي الإجابة اليدوية فوق اقتراح OCR', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            ocrResults: {'attachment-1': _completedOcr},
            ocrMapping: mappedWithManual,
          ),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('مراجعة الإجابات المستخرجة'));
      await tester.pumpAndSettle();

      expect(find.text('يدوي'), findsOneWidget);
      expect(find.text('الإجابة المستخرجة: من الورقة'), findsOneWidget);
    });

    testWidgets('تسمح بتعديل الاقتراح ثم تأكيد الإجابات', (tester) async {
      final gateway = gatewayWith(
        ocrResults: {'attachment-1': _completedOcr},
        ocrMapping: mapped,
      );
      await tester.pumpWidget(
        BayyinApp(gateway: gateway, picker: FakeAttachmentPicker()),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('مراجعة الإجابات المستخرجة'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'ثلاثة أرباع');
      await tester.enterText(find.byType(TextField).at(1), '1/2');
      await _scrollAndTap(tester, 'تأكيد الإجابات');

      expect(find.text('تم تأكيد الإجابات'), findsOneWidget);
      expect(gateway.confirmMappingCalls, 1);
      expect(find.text('مراجعة الإجابات المستخرجة'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('تعرض خطأ الخادم عند فشل الاستخراج', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            ocrResults: {'attachment-1': _completedOcr},
            mappingError: const ApiException(
              'لا يوجد نص مستخرج يمكن استخدامه بعد.',
            ),
          ),
          picker: FakeAttachmentPicker(),
        ),
      );
      await openArabicEntry(tester);
      await tester.tap(find.text('مراجعة الإجابات المستخرجة'));
      await tester.pumpAndSettle();

      expect(find.text('لا يوجد نص مستخرج يمكن استخدامه بعد.'), findsOneWidget);
      expect(find.text('تأكيد الإجابات'), findsNothing);
    });

    testWidgets('reviews and confirms answers in English', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            ocrResults: {'attachment-1': _completedOcr},
            ocrMapping: mapped,
          ),
          picker: FakeAttachmentPicker(),
          initialLocale: AppLocale.english,
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );
      await tester.tap(find.text('Review extracted answers'));
      await tester.pumpAndSettle();

      expect(find.text('Extracted answer'), findsOneWidget);
      expect(find.text('No answer detected'), findsOneWidget);
      await _scrollAndTap(tester, 'Confirm answers');

      expect(find.text('Answers confirmed'), findsOneWidget);
      await _settleSnackBars(tester);
    });

    testWidgets('confirm then save keeps OCR answers and grades them', (
      tester,
    ) async {
      final gateway = FakeGateway(
        role: 'TEACHER',
        classrooms: [_classroom6a],
        assessments: [_sixQuestionAssessment],
        students: _roster,
        submissions: [_emptySixSubmission],
        attachments: [_existingAttachment],
        ocrResults: {'attachment-1': _completedOcr},
        ocrMapping: _sixOcrMapping,
      );
      _useTallViewport(tester);
      tester.view.physicalSize = const Size(800, 3600);
      await tester.pumpWidget(
        BayyinApp(gateway: gateway, picker: FakeAttachmentPicker()),
      );
      await openArabicEntry(tester);

      await tester.tap(find.text('مراجعة الإجابات المستخرجة'));
      await tester.pumpAndSettle();
      await _scrollAndTap(tester, 'تأكيد الإجابات');
      expect(find.text('تم تأكيد الإجابات'), findsOneWidget);
      await _settleSnackBars(tester);

      expect(find.text('3/4'), findsWidgets);
      expect(find.text('1/5'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('18 سم'), findsOneWidget);
      expect(find.text('لأننا ضربنا 1 في 2'), findsOneWidget);

      await _scrollAndTap(tester, 'حفظ الإجابات');
      expect(find.text('تم الحفظ'), findsOneWidget);
      expect(gateway.savedAnswerPayloads, isNotEmpty);
      final savePayload = gateway.savedAnswerPayloads.last;
      expect(savePayload['six-q1'], '3/4');
      expect(savePayload['six-q2'], '1/5');
      expect(savePayload['six-q3'], '1/2');
      expect(savePayload['six-q4'], '3/4');
      expect(savePayload['six-q5'], '18 سم');
      expect(savePayload['six-q6'], 'لأننا ضربنا 1 في 2');
      expect(savePayload.values, everyElement(isNot(isEmpty)));
      await _settleSnackBars(tester);

      await _scrollAndTap(tester, 'تقييم الإجابات');
      expect(gateway.evaluateCalls, 1);
      expect(find.text('لم يُدخل الطالب إجابة.'), findsNothing);
      await _expandEvaluationDetails(tester);
      expect(find.text('الإجابة صحيحة.'), findsWidgets);
      expect(find.text('الدرجة: 2 / 2', skipOffstage: false), findsWidgets);
      final result = await gateway.fetchSubmissionResult(
        token: 'test-token',
        assessmentId: 'assessment-six',
        submissionId: 'submission-six',
      );
      expect(result.awardedScoreTotal, 12);
      expect(result.maxScoreTotal, 12);
      expect(result.unevaluatedCount, 0);
      expect(result.isComplete, isTrue);
    });
  });

  group('تقييم الإجابات', () {
    const correctEval = EvaluationRecord(
      status: 'correct',
      awardedScore: 2,
      feedback: 'الإجابة صحيحة.',
    );
    const partialEval = EvaluationRecord(
      status: 'partial',
      awardedScore: 1.5,
      feedback: 'الخطوات ناقصة.',
      misconception: 'خلط المقام بالمقدار',
    );
    const incorrectEval = EvaluationRecord(
      status: 'incorrect',
      awardedScore: 0,
      feedback: 'الإجابة لا تحقق المطلوب.',
    );

    FakeGateway gatewayWith({
      Map<String, EvaluationRecord> evaluations = const {},
      Object? evaluateError,
      Completer<void>? evaluateGate,
      int evaluateFailedCount = 0,
      List<SubmissionRecord>? submissions,
    }) => FakeGateway(
      role: 'TEACHER',
      classrooms: [_classroom6a],
      assessments: [_fractionsAssessment],
      students: _roster,
      submissions: submissions ?? [_existingSubmission],
      evaluateError: evaluateError,
      evaluateGate: evaluateGate,
      evaluateFailedCount: evaluateFailedCount,
      evaluationsByQuestionId: evaluations,
    );

    Future<void> openArabicEntry(WidgetTester tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(BayyinApp(gateway: gatewayWith()));
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
    }

    testWidgets('تعرض زر التقييم بعد وجود إجابات مؤكدة', (tester) async {
      await openArabicEntry(tester);
      expect(find.text('تقييم الإجابات'), findsOneWidget);
      expect(find.text('تقييم آلي'), findsNothing);
      expect(find.text('صحيح'), findsNothing);
    });

    testWidgets('ترسل ar عندما تكون الواجهة عربية', (tester) async {
      final gateway = gatewayWith(evaluations: {'question-1': correctEval});
      _useTallViewport(tester);
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await _scrollAndTap(tester, 'تقييم الإجابات');
      expect(gateway.evaluateLocales, ['ar']);
    });

    testWidgets('تخفي الزر قبل حفظ أي إجابة', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a],
            assessments: [_fractionsAssessment],
            students: _roster,
          ),
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      expect(find.text('تقييم الإجابات'), findsNothing);
    });

    testWidgets('تعرض حالة التحميل أثناء التقييم', (tester) async {
      final gate = Completer<void>();
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(gateway: gatewayWith(evaluateGate: gate)),
      );
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await tester.tap(find.text('تقييم الإجابات'));
      await tester.pump();

      expect(find.text('جاري التقييم'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      gate.complete();
      await tester.pumpAndSettle();
      await _expandEvaluationDetails(tester);
      expect(find.text('تقييم آلي'), findsWidgets);
    });

    testWidgets('تعرض نتيجة صحيحة ودرجة وملاحظات', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(evaluations: {'question-1': correctEval}),
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await _scrollAndTap(tester, 'تقييم الإجابات');

      expect(find.text('صحيح'), findsOneWidget);
      expect(find.text('الدرجة: 2 / 2'), findsOneWidget);
      expect(find.text('عرض تفاصيل التقييم'), findsWidgets);
      expect(find.text('تقييم آلي'), findsNothing);
      expect(find.text('الملاحظات'), findsNothing);
      expect(find.text('الإجابة صحيحة.'), findsNothing);

      await _expandEvaluationDetails(tester);
      expect(find.text('تقييم آلي'), findsWidgets);
      expect(find.text('الملاحظات'), findsWidgets);
      expect(find.text('الإجابة صحيحة.'), findsOneWidget);
      expect(find.text('الفهم الخاطئ'), findsNothing);
    });

    testWidgets('تعرض نتيجة جزئية مع الفهم الخاطئ', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(evaluations: {'question-1': partialEval}),
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await _scrollAndTap(tester, 'تقييم الإجابات');

      expect(find.text('صحيح جزئيًا'), findsWidgets);
      expect(find.text('الدرجة: 1.5 / 2'), findsWidgets);
      expect(find.text('الخطوات ناقصة.'), findsNothing);

      await _expandEvaluationDetails(tester);
      expect(find.text('الخطوات ناقصة.'), findsWidgets);
      expect(find.text('الفهم الخاطئ'), findsOneWidget);
      expect(find.text('خلط المقام بالمقدار'), findsWidgets);
    });

    testWidgets('تعرض نتيجة غير صحيحة', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(evaluations: {'question-1': incorrectEval}),
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await _scrollAndTap(tester, 'تقييم الإجابات');

      expect(find.text('غير صحيح'), findsWidgets);
      expect(find.text('الدرجة: 0 / 2'), findsWidgets);
      expect(find.text('الإجابة لا تحقق المطلوب.'), findsNothing);

      await _expandEvaluationDetails(tester);
      expect(find.text('الإجابة لا تحقق المطلوب.'), findsWidgets);
    });

    testWidgets('تعرض خطأً آمنًا عند فشل التقييم', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            evaluateError: const ApiException('تعذر تقييم الإجابة.'),
          ),
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await _scrollAndTap(tester, 'تقييم الإجابات');

      expect(find.text('تعذر تقييم الإجابة.'), findsWidgets);
      expect(find.text('صحيح'), findsNothing);
      expect(find.text('تقييم آلي'), findsNothing);
      await _settleSnackBars(tester);
    });

    testWidgets('تحدّث النتيجة وتصفّر غير المقيم بعد نجاح التقييم', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            evaluations: {
              'question-1': correctEval,
              'question-2': incorrectEval,
            },
          ),
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      expect(find.text('غير مقيم: 2', skipOffstage: false), findsOneWidget);
      await _scrollAndTap(tester, 'تقييم الإجابات');
      expect(find.text('النتيجة مكتملة', skipOffstage: false), findsOneWidget);
      expect(find.text('غير مقيم: 0', skipOffstage: false), findsOneWidget);
    });

    testWidgets('تعرض خطأً آمنًا عند الفشل الجزئي بعد تحديث النتيجة', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            evaluations: {'question-1': correctEval},
            evaluateFailedCount: 1,
          ),
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await _scrollAndTap(tester, 'تقييم الإجابات');
      expect(find.text('تعذر تقييم الإجابة.'), findsWidgets);
      await _expandEvaluationDetails(tester);
      expect(find.text('تقييم آلي'), findsWidgets);
      await _settleSnackBars(tester);
    });

    test('reads failed_count from the bulk evaluate payload', () {
      final record = SubmissionRecord.fromJson({
        'id': 's1',
        'student_id': 'st1',
        'student_name': '',
        'student_code': '',
        'failed_count': 2,
        'answers': const [],
      });
      expect(record.failedCount, 2);
    });

    testWidgets('تعيد التقييم على نفس الإجابات', (tester) async {
      final gateway = gatewayWith(evaluations: {'question-1': correctEval});
      _useTallViewport(tester);
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
      await _scrollAndTap(tester, 'تقييم الإجابات');
      expect(find.text('إعادة التقييم'), findsOneWidget);
      await _scrollAndTap(tester, 'إعادة التقييم');
      expect(gateway.evaluateCalls, 2);
      expect(find.text('صحيح'), findsOneWidget);
    });

    testWidgets('evaluates answers in English', (tester) async {
      _useTallViewport(tester);
      final gateway = gatewayWith(
        evaluations: {'question-1': partialEval, 'question-2': incorrectEval},
      );
      await tester.pumpWidget(
        BayyinApp(gateway: gateway, initialLocale: AppLocale.english),
      );
      await _reachEntry(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );
      expect(find.text('Evaluate answers'), findsOneWidget);
      await _scrollAndTap(tester, 'Evaluate answers');

      expect(gateway.evaluateLocales, ['en']);
      expect(find.text('Partially correct'), findsWidgets);
      expect(find.text('Incorrect'), findsWidgets);
      expect(find.text('Score: 1.5 / 2'), findsWidgets);
      expect(find.text('View evaluation details'), findsWidgets);
      expect(find.text('AI evaluation'), findsNothing);
      expect(find.text('Feedback'), findsNothing);

      await _expandEvaluationDetails(tester);
      expect(find.text('AI evaluation'), findsWidgets);
      expect(find.text('Feedback'), findsWidgets);
      expect(find.text('Misconception'), findsOneWidget);
      expect(find.text('Re-evaluate'), findsOneWidget);
    });

    testWidgets('تستخدم اللغة الجديدة إذا تبدلت قبل التقييم', (tester) async {
      final gateway = gatewayWith(evaluations: {'question-1': correctEval});
      _useTallViewport(tester);
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _signIn(tester, 'تسجيل الدخول');
      await _pickLanguage(tester, 'English');
      await _openAssessments(tester, 'Assessments');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student submissions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('طالب أ'));
      await tester.pumpAndSettle();
      await _scrollAndTap(tester, 'Evaluate answers');
      expect(gateway.evaluateLocales, ['en']);
    });

    testWidgets('تظهر أزرار الحفظ والتقييم ثابتة في شريط الإجراءات', (
      tester,
    ) async {
      await openArabicEntry(tester);
      expect(find.text('حفظ الإجابات'), findsOneWidget);
      expect(find.text('تقييم الإجابات'), findsOneWidget);
      expect(find.text('ورقة الاختبار'), findsWidgets);
      expect(find.text('التحليل'), findsWidgets);
    });
  });

  group('نتيجة الاختبار والفجوات', () {
    const correctEval = EvaluationRecord(
      status: 'correct',
      awardedScore: 2,
      feedback: 'الإجابة صحيحة.',
    );
    const partialEval = EvaluationRecord(
      status: 'partial',
      awardedScore: 1.5,
      feedback: 'الخطوات ناقصة.',
      misconception: 'خلط المقام بالمقدار',
    );
    const incorrectEval = EvaluationRecord(
      status: 'incorrect',
      awardedScore: 0,
      feedback: 'الإجابة لا تحقق المطلوب.',
      misconception: 'خلط المقام بالمقدار',
    );

    SubmissionRecord submissionWith({
      EvaluationRecord? first,
      EvaluationRecord? second,
    }) => SubmissionRecord(
      id: 'submission-1',
      studentId: 'student-1',
      studentName: 'طالب أ',
      studentCode: 'S-001',
      assessmentTitle: 'اختبار الكسور الأول',
      answers: [
        AnswerRecord(
          id: 'answer-question-1',
          questionId: 'question-1',
          order: 1,
          text: 'ما ناتج 1/2 + 1/4؟',
          maxScore: 2,
          answerText: '3/4',
          evaluation: first,
        ),
        AnswerRecord(
          id: 'answer-question-2',
          questionId: 'question-2',
          order: 2,
          text: 'بسّط الكسر 4/8',
          maxScore: 3,
          answerText: '1/2',
          evaluation: second,
        ),
      ],
    );

    FakeGateway gatewayWith({
      required SubmissionRecord submission,
      Object? resultError,
    }) => FakeGateway(
      role: 'TEACHER',
      classrooms: [_classroom6a],
      assessments: [_fractionsAssessment],
      students: _roster,
      submissions: [submission],
      resultError: resultError,
    );

    Future<void> openArabic(WidgetTester tester, FakeGateway gateway) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _reachEntry(
        tester,
        signIn: 'تسجيل الدخول',
        assessments: 'الاختبارات',
        submissions: 'تسليمات الطلاب',
      );
    }

    testWidgets('تعرض نتيجة مكتملة مع العد والدرجة والنسبة', (tester) async {
      await openArabic(
        tester,
        gatewayWith(
          submission: submissionWith(first: correctEval, second: incorrectEval),
        ),
      );

      expect(find.text('نتيجة الاختبار'), findsOneWidget);
      expect(find.text('النتيجة مكتملة'), findsOneWidget);
      expect(find.text('الدرجة: 2 / 5'), findsOneWidget);
      expect(find.text('النسبة: 40%'), findsOneWidget);
      expect(find.text('صحيح: 1'), findsOneWidget);
      expect(find.text('صحيح جزئيًا: 0'), findsOneWidget);
      expect(find.text('غير صحيح: 1'), findsOneWidget);
      expect(find.text('غير مقيم: 0'), findsOneWidget);
      expect(find.text('عرض تفاصيل النتيجة'), findsOneWidget);
    });

    testWidgets('تعرض نتيجة غير مكتملة وتحذيرًا واضحًا', (tester) async {
      await openArabic(
        tester,
        gatewayWith(submission: submissionWith(first: correctEval)),
      );

      expect(find.text('النتيجة غير مكتملة'), findsOneWidget);
      expect(
        find.text('النتيجة غير مكتملة لأن بعض الأسئلة لم يتم تقييمها بعد.'),
        findsOneWidget,
      );
      expect(find.text('النسبة: 100%'), findsOneWidget);
      expect(find.text('غير مقيم: 1'), findsOneWidget);
    });

    testWidgets('تعرض الفجوات وتخفي المفاهيم الخاطئة إن لم توجد', (
      tester,
    ) async {
      await openArabic(
        tester,
        gatewayWith(
          submission: submissionWith(
            first: correctEval,
            second: const EvaluationRecord(
              status: 'incorrect',
              awardedScore: 0,
              feedback: 'الإجابة لا تحقق المطلوب.',
            ),
          ),
        ),
      );
      await _scrollAndTap(tester, 'عرض تفاصيل النتيجة');

      expect(find.text('الفجوات'), findsOneWidget);
      expect(find.text('السؤال 2'), findsWidgets);
      expect(find.text('غير صحيح'), findsWidgets);
      expect(find.text('الإجابة لا تحقق المطلوب.'), findsWidgets);
      expect(find.text('المفاهيم الخاطئة'), findsNothing);
    });

    testWidgets('تعرض المفاهيم الخاطئة دون تكرار', (tester) async {
      await openArabic(
        tester,
        gatewayWith(
          submission: submissionWith(first: partialEval, second: incorrectEval),
        ),
      );
      await _scrollAndTap(tester, 'عرض تفاصيل النتيجة');

      expect(find.text('المفاهيم الخاطئة'), findsOneWidget);
      expect(find.text('• خلط المقام بالمقدار'), findsOneWidget);
      expect(find.text('الفجوات'), findsOneWidget);
      expect(find.text('صحيح جزئيًا'), findsWidgets);
    });

    testWidgets('تعرض خطأ الخادم عند فشل جلب النتيجة', (tester) async {
      await openArabic(
        tester,
        gatewayWith(
          submission: submissionWith(),
          resultError: const ApiException('تعذر إكمال الطلب. حاول مرة أخرى.'),
        ),
      );

      expect(find.text('نتيجة الاختبار'), findsOneWidget);
      expect(find.text('تعذر إكمال الطلب. حاول مرة أخرى.'), findsOneWidget);
      expect(find.text('النتيجة مكتملة'), findsNothing);
    });

    testWidgets('shows the result in English', (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BayyinApp(
          gateway: gatewayWith(
            submission: submissionWith(
              first: partialEval,
              second: incorrectEval,
            ),
          ),
          initialLocale: AppLocale.english,
        ),
      );
      await _reachEntry(
        tester,
        signIn: 'Sign in',
        assessments: 'Assessments',
        submissions: 'Student submissions',
      );

      expect(find.text('Assessment result'), findsOneWidget);
      expect(find.text('Result complete'), findsOneWidget);
      expect(find.text('Score: 1.5 / 5'), findsOneWidget);
      expect(find.text('Percentage: 30%'), findsOneWidget);
      expect(find.text('Partially correct: 1'), findsOneWidget);
      expect(find.text('Incorrect: 1'), findsOneWidget);
      expect(find.text('View result details'), findsOneWidget);
      await _scrollAndTap(tester, 'View result details');
      expect(find.text('Gaps'), findsOneWidget);
      expect(find.text('Misconceptions'), findsOneWidget);
    });

    testWidgets('تفتح صفحة تفاصيل مرتبة لكل سؤال', (tester) async {
      await openArabic(
        tester,
        gatewayWith(
          submission: submissionWith(first: correctEval, second: incorrectEval),
        ),
      );
      await _scrollAndTap(tester, 'عرض تفاصيل النتيجة');

      expect(find.text('طالب أ'), findsWidgets);
      expect(find.text('اختبار الكسور الأول'), findsWidgets);
      expect(find.text('تفاصيل الأسئلة'), findsOneWidget);
      expect(find.text('2 من 2 أسئلة مقيّمة'), findsOneWidget);
      expect(find.text('السؤال 1'), findsWidgets);
      expect(find.text('ما ناتج 1/2 + 1/4؟'), findsWidgets);
      expect(find.text('إجابة الطالب'), findsWidgets);
      expect(find.text('3/4'), findsWidgets);
      expect(find.text('صحيح'), findsWidgets);
      expect(find.text('غير صحيح'), findsWidgets);
    });
  });

  group('تحليل الصف', () {
    const insights = ClassInsightsRecord(
      summary: ClassInsightsSummary(
        totalStudentsInClass: 5,
        studentsWithSubmission: 4,
        studentsWithoutSubmission: 1,
        completeResults: 3,
        incompleteResults: 1,
        averagePercentage: 73.33,
      ),
      questionGaps: [
        ClassQuestionGapRecord(
          questionId: 'question-2',
          questionOrder: 2,
          questionText: 'بسّط الكسر 4/8',
          maxScore: 10,
          evaluatedStudents: 3,
          correctCount: 1,
          partialCount: 1,
          incorrectCount: 1,
          gapCount: 2,
          gapPercentage: 66.67,
        ),
        ClassQuestionGapRecord(
          questionId: 'question-1',
          questionOrder: 1,
          questionText: 'ما ناتج 1/2 + 1/4؟',
          maxScore: 10,
          evaluatedStudents: 4,
          correctCount: 3,
          partialCount: 0,
          incorrectCount: 1,
          gapCount: 1,
          gapPercentage: 25,
        ),
      ],
      misconceptions: [
        MisconceptionCountRecord(text: 'خلط المقام', count: 2),
        MisconceptionCountRecord(text: 'نسي التبسيط', count: 1),
      ],
      foundation: [
        GroupedStudentRecord(
          studentId: 'student-1',
          displayName: 'طالب تأسيس',
          studentCode: 'S-001',
          percentage: 50,
          group: 'foundation',
        ),
      ],
      practice: [
        GroupedStudentRecord(
          studentId: 'student-2',
          displayName: 'طالب تدريب',
          studentCode: 'S-002',
          percentage: 70,
          group: 'practice',
        ),
      ],
      ready: [
        GroupedStudentRecord(
          studentId: 'student-3',
          displayName: 'طالب جاهز',
          studentCode: 'S-003',
          percentage: 100,
          group: 'ready',
        ),
      ],
      pendingStudents: [
        PendingStudentRecord(
          studentId: 'student-4',
          displayName: 'طالب معلق',
          studentCode: 'S-004',
          reason: 'incomplete evaluation',
        ),
      ],
    );

    const emptyAverage = ClassInsightsRecord(
      summary: ClassInsightsSummary(
        totalStudentsInClass: 4,
        studentsWithSubmission: 1,
        studentsWithoutSubmission: 3,
        completeResults: 0,
        incompleteResults: 1,
      ),
      pendingStudents: [
        PendingStudentRecord(
          studentId: 'student-4',
          displayName: 'طالب معلق',
          studentCode: 'S-004',
          reason: 'incomplete evaluation',
        ),
      ],
    );

    FakeGateway gatewayWith({
      ClassInsightsRecord record = insights,
      Object? error,
    }) {
      return FakeGateway(
        role: 'TEACHER',
        classrooms: [_classroom6a],
        assessments: [_fractionsAssessment],
        classInsights: record,
        classInsightsError: error,
      );
    }

    Future<void> openArabic(WidgetTester tester, FakeGateway gateway) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تحليل الصف'));
      await tester.pumpAndSettle();
    }

    testWidgets('تعرض ملخص الصف مع المتوسط والعد', (tester) async {
      await openArabic(tester, gatewayWith());
      expect(find.text('متوسط الصف: 73.33%'), findsOneWidget);
      expect(find.text('نتائج مكتملة: 3'), findsOneWidget);
      expect(find.text('نتائج غير مكتملة: 1'), findsOneWidget);
      expect(find.text('بدون تسليم: 1'), findsOneWidget);
    });

    testWidgets('تخفي المتوسط عند غياب النتائج المكتملة', (tester) async {
      await openArabic(tester, gatewayWith(record: emptyAverage));
      expect(find.text('لا توجد نتائج مكتملة بعد'), findsOneWidget);
      expect(find.textContaining('متوسط الصف'), findsNothing);
    });

    testWidgets('تعرض أكثر الأسئلة احتياجًا مع العد', (tester) async {
      await openArabic(tester, gatewayWith());
      expect(find.text('أكثر الأسئلة احتياجًا'), findsOneWidget);
      expect(find.text('السؤال 2 — فجوة 66.67%'), findsOneWidget);
      expect(find.text('السؤال 1 — فجوة 25%'), findsOneWidget);
      expect(find.textContaining('صحيح: 1'), findsWidgets);
      expect(find.textContaining('صحيح جزئيًا: 1'), findsWidgets);
      expect(find.textContaining('غير صحيح: 1'), findsWidgets);
    });

    testWidgets('تعرض المفاهيم الخاطئة المتكررة', (tester) async {
      await openArabic(tester, gatewayWith());
      expect(find.text('المفاهيم الخاطئة المتكررة'), findsOneWidget);
      expect(find.text('خلط المقام'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
      expect(find.text('نسي التبسيط'), findsOneWidget);
      expect(find.text('×1'), findsOneWidget);
    });

    testWidgets('تعرض مجموعة التأسيس', (tester) async {
      await openArabic(tester, gatewayWith());
      expect(find.text('تأسيس'), findsWidgets);
      expect(find.text('طالب تأسيس'), findsOneWidget);
      expect(find.text('S-001'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('تعرض مجموعة التدريب', (tester) async {
      await openArabic(tester, gatewayWith());
      expect(find.text('تدريب'), findsWidgets);
      expect(find.text('طالب تدريب'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
    });

    testWidgets('تعرض مجموعة الجاهزين', (tester) async {
      await openArabic(tester, gatewayWith());
      expect(find.text('جاهز'), findsWidgets);
      expect(find.text('طالب جاهز'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('تعرض الطلاب بانتظار اكتمال التقييم', (tester) async {
      await openArabic(tester, gatewayWith());
      expect(find.text('بانتظار اكتمال التقييم'), findsOneWidget);
      expect(find.text('طالب معلق'), findsOneWidget);
      expect(find.textContaining('تقييم غير مكتمل'), findsOneWidget);
    });

    testWidgets('تعرض خطأ الخادم عند فشل التحليل', (tester) async {
      await openArabic(
        tester,
        gatewayWith(
          error: const ApiException('تعذر إكمال الطلب. حاول مرة أخرى.'),
        ),
      );
      expect(find.text('تعذر إكمال الطلب. حاول مرة أخرى.'), findsOneWidget);
      expect(find.text('متوسط الصف: 73.33%'), findsNothing);
    });

    testWidgets('shows class insights in English', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BayyinApp(gateway: gatewayWith(), initialLocale: AppLocale.english),
      );
      await _signIn(tester, 'Sign in');
      await _openAssessments(tester, 'Assessments');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class insights'));
      await tester.pumpAndSettle();

      expect(find.text('Class average: 73.33%'), findsOneWidget);
      expect(find.text('Complete results: 3'), findsOneWidget);
      expect(find.text('Highest-gap questions'), findsOneWidget);
      expect(find.text('Question 2 — 66.67% gap'), findsOneWidget);
      expect(find.text('Common misconceptions'), findsOneWidget);
      expect(find.text('Foundation'), findsWidgets);
      expect(find.text('Practice'), findsWidgets);
      expect(find.text('Ready'), findsWidgets);
      expect(find.text('Pending evaluation'), findsOneWidget);
    });
  });

  group('الخطة العلاجية', () {
    const insights = ClassInsightsRecord(
      summary: ClassInsightsSummary(
        totalStudentsInClass: 3,
        studentsWithSubmission: 3,
        studentsWithoutSubmission: 0,
        completeResults: 3,
        incompleteResults: 0,
        averagePercentage: 73.33,
      ),
      foundation: [
        GroupedStudentRecord(
          studentId: 'student-1',
          displayName: 'طالب تأسيس',
          studentCode: 'S-001',
          percentage: 50,
          group: 'foundation',
        ),
      ],
      practice: [
        GroupedStudentRecord(
          studentId: 'student-2',
          displayName: 'طالب تدريب',
          studentCode: 'S-002',
          percentage: 70,
          group: 'practice',
        ),
      ],
      ready: [
        GroupedStudentRecord(
          studentId: 'student-3',
          displayName: 'طالب جاهز',
          studentCode: 'S-003',
          percentage: 100,
          group: 'ready',
        ),
      ],
    );

    const emptyFoundationInsights = ClassInsightsRecord(
      summary: ClassInsightsSummary(
        totalStudentsInClass: 2,
        studentsWithSubmission: 1,
        studentsWithoutSubmission: 1,
        completeResults: 1,
        incompleteResults: 0,
        averagePercentage: 70,
      ),
      practice: [
        GroupedStudentRecord(
          studentId: 'student-2',
          displayName: 'طالب تدريب',
          studentCode: 'S-002',
          percentage: 70,
          group: 'practice',
        ),
      ],
    );

    const existingPlan = RemediationPlanRecord(
      id: 'plan-1',
      group: 'foundation',
      status: 'completed',
      title: 'خطة تأسيس الكسور',
      summary: 'بناء مفهوم الكسر من المحسوس إلى الرمز.',
      teacherGuidance: 'ابدأ بالمحسوس ثم انتقل إلى الرمز.',
      objectives: ['يفهم معنى المقام'],
      activities: [
        RemediationActivityRecord(
          title: 'أمثلة موجهة',
          description: 'حل مثالين مع المعلم.',
          durationMinutes: 15,
        ),
      ],
    );

    FakeGateway gatewayWith({
      ClassInsightsRecord record = insights,
      List<RemediationPlanRecord> plans = const [],
      Object? generateError,
      Completer<void>? gate,
    }) {
      return FakeGateway(
        role: 'TEACHER',
        classrooms: [_classroom6a],
        assessments: [_fractionsAssessment],
        classInsights: record,
        remediationPlans: plans,
        generatePlanError: generateError,
        remediationGate: gate,
        generatedPlan: existingPlan,
      );
    }

    Future<void> openArabic(WidgetTester tester, FakeGateway gateway) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _signIn(tester, 'تسجيل الدخول');
      await _openAssessments(tester, 'الاختبارات');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تحليل الصف'));
      await tester.pumpAndSettle();
    }

    testWidgets('تعرض بطاقات المجموعات الثلاث', (tester) async {
      await openArabic(tester, gatewayWith());
      expect(find.text('الخطة العلاجية'), findsOneWidget);
      expect(find.text('تأسيس'), findsWidgets);
      expect(find.text('تدريب'), findsWidgets);
      expect(find.text('جاهز'), findsWidgets);
      expect(find.text('إنشاء خطة'), findsNWidgets(3));
    });

    testWidgets('تعرض حالة المجموعة الفارغة بدون زر إنشاء', (tester) async {
      await openArabic(tester, gatewayWith(record: emptyFoundationInsights));
      expect(find.text('لا يوجد طلاب في هذه المجموعة'), findsWidgets);
      expect(find.text('إنشاء خطة'), findsOneWidget);
    });

    testWidgets('تعرض حالة التحميل أثناء إنشاء الخطة', (tester) async {
      final gate = Completer<void>();
      await openArabic(tester, gatewayWith(gate: gate));
      await tester.ensureVisible(find.text('إنشاء خطة').first);
      await tester.tap(find.text('إنشاء خطة').first);
      await tester.pump();
      expect(find.text('جاري إنشاء الخطة'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('تعرض الخطة المولدة مع الأهداف والأنشطة والإرشاد', (
      tester,
    ) async {
      await openArabic(tester, gatewayWith());
      await tester.ensureVisible(find.text('إنشاء خطة').first);
      await tester.tap(find.text('إنشاء خطة').first);
      await tester.pumpAndSettle();
      expect(find.text('خطة مولدة بالذكاء الاصطناعي'), findsOneWidget);
      expect(find.text('خطة تأسيس الكسور'), findsOneWidget);
      expect(
        find.text('بناء مفهوم الكسر من المحسوس إلى الرمز.'),
        findsOneWidget,
      );
      expect(find.text('الأهداف'), findsOneWidget);
      expect(find.text('• يفهم معنى المقام'), findsOneWidget);
      expect(find.text('الأنشطة'), findsOneWidget);
      expect(find.text('أمثلة موجهة'), findsOneWidget);
      expect(find.text('15 دقيقة'), findsOneWidget);
      expect(find.text('إرشادات المعلم'), findsOneWidget);
      expect(find.text('ابدأ بالمحسوس ثم انتقل إلى الرمز.'), findsOneWidget);
    });

    testWidgets('تعيد توليد الخطة على نفس المجموعة', (tester) async {
      await openArabic(tester, gatewayWith(plans: [existingPlan]));
      await tester.ensureVisible(find.text('عرض الخطة'));
      await tester.tap(find.text('عرض الخطة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إعادة التوليد'));
      await tester.pumpAndSettle();
      expect(find.text('خطة محدثة'), findsOneWidget);
    });

    testWidgets('تعرض خطأ الخادم عند فشل التوليد', (tester) async {
      await openArabic(
        tester,
        gatewayWith(generateError: const ApiException('تعذر إنشاء الخطة.')),
      );
      await tester.ensureVisible(find.text('إنشاء خطة').first);
      await tester.tap(find.text('إنشاء خطة').first);
      await tester.pumpAndSettle();
      expect(find.text('تعذر إنشاء الخطة.'), findsOneWidget);
      expect(find.text('خطة مولدة بالذكاء الاصطناعي'), findsNothing);
    });

    testWidgets('shows the plan in English', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gateway = gatewayWith();
      await tester.pumpWidget(
        BayyinApp(gateway: gateway, initialLocale: AppLocale.english),
      );
      await _signIn(tester, 'Sign in');
      await _openAssessments(tester, 'Assessments');
      await tester.tap(find.text('اختبار الكسور الأول'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class insights'));
      await tester.pumpAndSettle();
      expect(find.text('Remediation plan'), findsOneWidget);
      expect(find.text('Generate plan'), findsWidgets);
      expect(find.text('No students in this group'), findsNothing);
      await tester.ensureVisible(find.text('Generate plan').first);
      await tester.tap(find.text('Generate plan').first);
      await tester.pumpAndSettle();
      expect(find.text('AI-generated plan'), findsOneWidget);
      expect(find.text('Objectives'), findsOneWidget);
      expect(find.text('Activities'), findsOneWidget);
      expect(find.text('Teacher guidance'), findsOneWidget);
      expect(find.text('15 minutes'), findsOneWidget);
      expect(gateway.generatePlanLocales, ['en']);
    });
  });

  group('تحليلات المدرسة', () {
    const insights = ManagerInsightsRecord(
      summary: ManagerInsightsSummary(
        totalTeachers: 2,
        totalClassrooms: 2,
        totalStudents: 4,
        totalAssessments: 2,
        assessmentsWithCompleteResults: 1,
        assessmentsWithIncompleteResults: 1,
        overallAveragePercentage: 50,
      ),
      classrooms: [
        ManagerClassroomInsight(
          classroomId: 'class-6a',
          classroomName: 'سادس أ',
          grade: 'الصف السادس',
          subject: 'الرياضيات',
          teacherName: 'أحمد الغامدي',
          studentCount: 3,
          assessmentCount: 1,
          completedResultsCount: 1,
          incompleteResultsCount: 1,
          averagePercentage: 50,
        ),
      ],
      teachers: [
        ManagerTeacherInsight(
          teacherId: 'teacher-a',
          displayName: 'أحمد الغامدي',
          classroomsCount: 1,
          studentsCount: 3,
          assessmentsCount: 1,
          completeResultsCount: 1,
          incompleteResultsCount: 1,
          averagePercentage: 50,
        ),
      ],
      assessments: [
        ManagerAssessmentInsight(
          assessmentId: 'assessment-1',
          title: 'اختبار الكسور',
          classroom: 'سادس أ',
          teacher: 'أحمد الغامدي',
          studentsWithSubmission: 2,
          completeResults: 1,
          incompleteResults: 1,
          averagePercentage: 50,
        ),
      ],
      highestGapQuestions: [
        ManagerGapInsight(
          assessmentTitle: 'اختبار الكسور',
          classroom: 'سادس أ',
          questionOrder: 2,
          questionText: 'بسّط الكسر 4/8',
          evaluatedStudents: 1,
          gapCount: 1,
          gapPercentage: 100,
        ),
      ],
      misconceptions: [MisconceptionCountRecord(text: 'خلط المقام', count: 2)],
    );

    const emptyInsights = ManagerInsightsRecord(
      summary: ManagerInsightsSummary(
        totalTeachers: 0,
        totalClassrooms: 0,
        totalStudents: 0,
        totalAssessments: 0,
        assessmentsWithCompleteResults: 0,
        assessmentsWithIncompleteResults: 0,
      ),
    );

    Future<void> openArabic(WidgetTester tester, FakeGateway gateway) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(BayyinApp(gateway: gateway));
      await _signIn(tester, 'تسجيل الدخول');
      await tester.tap(find.text('تحليلات المدرسة'));
      await tester.pumpAndSettle();
    }

    testWidgets('تعرض مدخل التحليلات في لوحة المدير', (tester) async {
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'MANAGER')));
      await _signIn(tester, 'تسجيل الدخول');
      expect(find.text('تحليلات المدرسة'), findsOneWidget);
    });

    testWidgets('تعرض بطاقات النظرة العامة', (tester) async {
      await openArabic(
        tester,
        FakeGateway(role: 'MANAGER', managerInsights: insights),
      );
      expect(find.text('نظرة عامة'), findsOneWidget);
      expect(find.text('المعلمون'), findsWidgets);
      expect(find.text('الصفوف'), findsWidgets);
      expect(find.text('الطلاب'), findsWidgets);
      expect(find.text('الاختبارات'), findsWidgets);
      expect(find.text('متوسط الأداء: 50%'), findsOneWidget);
      expect(find.text('نتائج مكتملة: 1'), findsWidgets);
      expect(find.text('نتائج غير مكتملة: 1'), findsWidgets);
    });

    testWidgets('تعرض حالة عدم كفاية البيانات', (tester) async {
      await openArabic(
        tester,
        FakeGateway(role: 'MANAGER', managerInsights: emptyInsights),
      );
      expect(find.text('لا توجد بيانات كافية بعد'), findsWidgets);
      expect(find.textContaining('متوسط الأداء'), findsNothing);
    });

    testWidgets('تعرض قسم الصفوف', (tester) async {
      await openArabic(
        tester,
        FakeGateway(role: 'MANAGER', managerInsights: insights),
      );
      expect(find.text('سادس أ'), findsWidgets);
      expect(find.textContaining('الطلاب: 3'), findsWidgets);
    });

    testWidgets('تعرض قسم المعلمين', (tester) async {
      await openArabic(
        tester,
        FakeGateway(role: 'MANAGER', managerInsights: insights),
      );
      expect(find.text('أحمد الغامدي'), findsWidgets);
      expect(find.textContaining('الصفوف: 1'), findsOneWidget);
    });

    testWidgets('تعرض قسم الاختبارات', (tester) async {
      await openArabic(
        tester,
        FakeGateway(role: 'MANAGER', managerInsights: insights),
      );
      expect(find.text('اختبار الكسور'), findsWidgets);
    });

    testWidgets('تعرض أبرز الفجوات', (tester) async {
      await openArabic(
        tester,
        FakeGateway(role: 'MANAGER', managerInsights: insights),
      );
      expect(find.text('أبرز الفجوات'), findsOneWidget);
      expect(find.text('السؤال 2 — فجوة 100%'), findsOneWidget);
    });

    testWidgets('تعرض المفاهيم الخاطئة المتكررة', (tester) async {
      await openArabic(
        tester,
        FakeGateway(role: 'MANAGER', managerInsights: insights),
      );
      expect(find.text('المفاهيم الخاطئة المتكررة'), findsOneWidget);
      expect(find.text('خلط المقام'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
    });

    testWidgets('تعرض خطأ الخادم', (tester) async {
      await openArabic(
        tester,
        FakeGateway(
          role: 'MANAGER',
          managerInsightsError: const ApiException(
            'تعذر إكمال الطلب. حاول مرة أخرى.',
          ),
        ),
      );
      expect(find.text('تعذر إكمال الطلب. حاول مرة أخرى.'), findsOneWidget);
      expect(find.text('نظرة عامة'), findsNothing);
    });

    testWidgets('shows school insights in English', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'MANAGER', managerInsights: insights),
          initialLocale: AppLocale.english,
        ),
      );
      await _signIn(tester, 'Sign in');
      await tester.tap(find.text('School insights'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Average performance: 50%'), findsOneWidget);
      expect(find.text('Highest gaps'), findsOneWidget);
      expect(find.text('Question 2 — 100% gap'), findsOneWidget);
      expect(find.text('Common misconceptions'), findsOneWidget);
      expect(find.text('Teachers'), findsWidgets);
      expect(find.text('Classrooms'), findsWidgets);
    });
  });

  group('تبديل اللغة', () {
    testWidgets('يبدل شاشة الدخول فورًا دون إعادة تشغيل', (tester) async {
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'TEACHER')));
      expect(find.text('مرحبًا بك في بيّن'), findsOneWidget);

      await _pickLanguage(tester, 'English');
      expect(find.text('Welcome to Bayyin'), findsOneWidget);
      expect(find.text('مرحبًا بك في بيّن'), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(Form))),
        TextDirection.ltr,
      );

      await _pickLanguage(tester, 'العربية');
      expect(find.text('مرحبًا بك في بيّن'), findsOneWidget);
      expect(find.text('Welcome to Bayyin'), findsNothing);
    });

    testWidgets('يبدل لوحة المدير فورًا', (tester) async {
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'MANAGER')));
      await _signIn(tester, 'تسجيل الدخول');
      expect(find.text('لوحة المدير'), findsOneWidget);

      await _pickLanguage(tester, 'English');
      expect(find.text('Manager dashboard'), findsOneWidget);
      expect(find.text('لوحة المدير'), findsNothing);
    });

    testWidgets('يبدل لوحة المعلم فورًا', (tester) async {
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      expect(find.text('صفوفي'), findsOneWidget);

      await _pickLanguage(tester, 'English');
      expect(find.text('My classes'), findsOneWidget);
      expect(find.text('صفوفي'), findsNothing);
    });
  });

  group('رسائل الخطأ', () {
    testWidgets('تتبع لغة الواجهة بعد التبديل', (tester) async {
      await tester.pumpWidget(
        BayyinApp(gateway: FakeGateway(role: 'MANAGER', failLogin: true)),
      );
      await _signIn(tester, 'تسجيل الدخول');
      expect(
        find.text('بيانات الدخول غير صحيحة أو الحساب غير نشط.'),
        findsOneWidget,
      );

      await _pickLanguage(tester, 'English');
      expect(
        find.text('Incorrect credentials, or the account is inactive.'),
        findsOneWidget,
      );
      expect(
        find.text('بيانات الدخول غير صحيحة أو الحساب غير نشط.'),
        findsNothing,
      );
    });
  });

  group('AppStrings', () {
    test('تترجم رسائل الخادم العربية إلى الإنجليزية', () {
      const serverMessage = 'بيانات الدخول غير صحيحة أو الحساب غير نشط.';
      expect(AppStrings.arabic.apiError(serverMessage), serverMessage);
      expect(
        AppStrings.english.apiError(serverMessage),
        'Incorrect credentials, or the account is inactive.',
      );
    });

    test('لا تسرّب نصًا عربيًا في الوضع الإنجليزي', () {
      final message = AppStrings.english.apiError('رسالة غير معروفة من الخادم');
      expect(RegExp(r'[\u0600-\u06FF]').hasMatch(message), isFalse);
    });

    test('تترجم رسائل التقييم', () {
      expect(
        AppStrings.english.apiError('تعذر تقييم الإجابة.'),
        'Could not evaluate answer.',
      );
      expect(AppStrings.arabic.evaluationStatus('correct'), 'صحيح');
      expect(
        AppStrings.english.evaluationStatus('partial'),
        'Partially correct',
      );
      expect(AppStrings.english.evaluationStatus('incorrect'), 'Incorrect');
      expect(AppStrings.arabic.awardedScoreValue(1.5, 2), 'الدرجة: 1.5 / 2');
      expect(AppStrings.english.awardedScoreValue(2, 2), 'Score: 2 / 2');
      expect(
        AppStrings.english.evaluationFeedback('لم يُدخل الطالب إجابة.'),
        'The student did not enter an answer.',
      );
      expect(AppStrings.arabic.evaluationLocale, 'ar');
      expect(AppStrings.english.evaluationLocale, 'en');
      expect(AppStrings.arabic.archivedAssessments, 'الاختبارات المؤرشفة');
      expect(AppStrings.english.newestFirst, 'Newest');
      expect(AppStrings.english.oldestFirst, 'Oldest');
      expect(AppStrings.arabic.currentAssessments, 'الاختبارات الحالية');
      expect(
        AppStrings.english.examWorkflowBanner,
        contains('Upload the original exam first'),
      );
      expect(
        AppStrings.english.openAssessmentsHint,
        startsWith('Create, archive'),
      );
      expect(AppStrings.arabic.viewEvaluationDetails, 'عرض تفاصيل التقييم');
      expect(
        AppStrings.english.hideEvaluationDetails,
        'Hide evaluation details',
      );
      expect(AppStrings.arabic.assessmentResult, 'نتيجة الاختبار');
      expect(AppStrings.arabic.viewResultDetails, 'عرض تفاصيل النتيجة');
      expect(AppStrings.english.questionDetails, 'Question details');
      expect(
        AppStrings.english.resultIncompleteWarning,
        startsWith('The result is incomplete'),
      );
      expect(AppStrings.arabic.classInsights, 'تحليل الصف');
      expect(AppStrings.english.classInsights, 'Class insights');
      expect(
        AppStrings.arabic.noCompleteResultsYet,
        'لا توجد نتائج مكتملة بعد',
      );
      expect(AppStrings.english.foundationGroup, 'Foundation');
      expect(AppStrings.english.pendingEvaluation, 'Pending evaluation');
      expect(AppStrings.arabic.remediationPlan, 'الخطة العلاجية');
      expect(AppStrings.english.aiGeneratedPlan, 'AI-generated plan');
      expect(
        AppStrings.english.apiError('تعذر إنشاء الخطة.'),
        'Could not generate plan.',
      );
      expect(AppStrings.arabic.schoolInsights, 'تحليلات المدرسة');
      expect(AppStrings.english.notEnoughDataYet, 'Not enough data yet');
      expect(AppStrings.arabic.resultNotEvaluable, 'الاختبار غير قابل للتقييم');
      expect(
        AppStrings.english.pendingReason('no questions'),
        'Assessment has no questions',
      );
      expect(
        AppStrings.arabic.apiError('Invalid token.'),
        'انتهت الجلسة. سجّل الدخول مرة أخرى.',
      );
    });
  });

  group('responsive layout', () {
    void setSize(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('login card stays compact on a desktop width', (tester) async {
      setSize(tester, const Size(1440, 1024));
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'TEACHER')));
      final width = tester.getSize(find.byType(Card).first).width;
      expect(width, lessThanOrEqualTo(430));
    });

    testWidgets('teacher dashboard content is capped on desktop', (tester) async {
      setSize(tester, const Size(1440, 1024));
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a, _classroom6b],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      final card = tester.getSize(find.byType(Card).first);
      expect(card.width, lessThanOrEqualTo(1120));
      expect(card.width, lessThan(1300));
    });

    testWidgets('teacher classes sit in two columns on desktop', (tester) async {
      setSize(tester, const Size(1440, 1024));
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'TEACHER',
            classrooms: [_classroom6a, _classroom6b],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      final first = tester.getTopLeft(find.text('سادس أ'));
      final second = tester.getTopLeft(find.text('سادس ب'));
      expect(first.dy, closeTo(second.dy, 8));
      expect((first.dx - second.dx).abs(), greaterThan(200));
    });

    testWidgets('narrow mobile login does not overflow', (tester) async {
      setSize(tester, const Size(320, 700));
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'TEACHER')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('مرحبًا بك في بيّن'), findsOneWidget);
    });

    testWidgets('tablet teacher dashboard does not overflow', (tester) async {
      setSize(tester, const Size(768, 1024));
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(role: 'TEACHER', classrooms: [_classroom6a]),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      expect(tester.takeException(), isNull);
      expect(find.text('صفوفي'), findsOneWidget);
    });

    testWidgets('desktop manager dashboard does not overflow', (tester) async {
      setSize(tester, const Size(1440, 1024));
      await tester.pumpWidget(
        BayyinApp(
          gateway: FakeGateway(
            role: 'MANAGER',
            teachers: [_teacherNoah],
            classrooms: [_managedClassroom],
          ),
        ),
      );
      await _signIn(tester, 'تسجيل الدخول');
      expect(tester.takeException(), isNull);
      expect(find.text('لوحة المدير'), findsOneWidget);
    });
  });
}

const _teacherNoah = TeacherAccount(
  id: '2',
  profileId: 'profile-naaa',
  username: 'naaa',
  fullName: 'Noah ahmad',
  email: '',
  isActive: true,
);

const _teacherWijdan = TeacherAccount(
  id: '5',
  profileId: 'profile-aaa',
  username: 'aaa',
  fullName: 'wijdan alqarni',
  email: '',
  isActive: true,
);

const _managedClassroom = ClassroomRecord(
  id: 'class-ne',
  name: 'n • e',
  grade: 'متوسط',
  subject: 'رياضيات',
  academicYear: '1448',
  teacherName: 'Noah ahmad',
  teacherProfileId: 'profile-naaa',
  studentsCount: 6,
);

const _classroom6a = ClassroomRecord(
  id: 'class-6a',
  name: 'سادس أ',
  grade: 'الصف السادس',
  subject: 'الرياضيات',
  academicYear: '1448',
  teacherName: 'teacher',
  studentsCount: 3,
);

const _classroom6b = ClassroomRecord(
  id: 'class-6b',
  name: 'سادس ب',
  grade: 'الصف السادس',
  subject: 'العلوم',
  academicYear: '1448',
  teacherName: 'teacher',
  studentsCount: 0,
);

const _fractionsAssessment = AssessmentRecord(
  id: 'assessment-1',
  title: 'اختبار الكسور الأول',
  classroomId: 'class-6a',
  classroomName: 'سادس أ',
  grade: 'الصف السادس',
  subject: 'الرياضيات',
  questionsCount: 2,
  totalScore: 5,
  questions: [
    QuestionRecord(
      id: 'question-1',
      order: 1,
      text: 'ما ناتج 1/2 + 1/4؟',
      maxScore: 2,
      modelAnswer: '3/4',
    ),
    QuestionRecord(
      id: 'question-2',
      order: 2,
      text: 'بسّط الكسر 4/8',
      maxScore: 3,
      modelAnswer: '1/2',
    ),
  ],
);

const _roster = [
  StudentRecord(id: 'student-1', internalCode: 'S-001', displayName: 'طالب أ'),
  StudentRecord(id: 'student-2', internalCode: 'S-002', displayName: ''),
];

const _existingSubmission = SubmissionRecord(
  id: 'submission-1',
  studentId: 'student-1',
  studentName: 'طالب أ',
  studentCode: 'S-001',
  assessmentTitle: 'اختبار الكسور الأول',
  answers: [
    AnswerRecord(
      id: 'answer-question-1',
      questionId: 'question-1',
      order: 1,
      text: 'ما ناتج 1/2 + 1/4؟',
      maxScore: 2,
      answerText: '3/4',
    ),
    AnswerRecord(
      id: 'answer-question-2',
      questionId: 'question-2',
      order: 2,
      text: 'بسّط الكسر 4/8',
      maxScore: 3,
      answerText: '',
    ),
  ],
);

const _existingAttachment = AttachmentRecord(
  id: 'attachment-1',
  filename: 'ورقة-الطالب.jpg',
  contentType: 'image/jpeg',
  fileSize: 2048,
);

const _sixQuestionAssessment = AssessmentRecord(
  id: 'assessment-six',
  title: 'اختبار الكسور الأول',
  classroomId: 'class-6a',
  classroomName: 'سادس أ',
  grade: 'الصف السادس',
  subject: 'الرياضيات',
  questionsCount: 6,
  totalScore: 12,
  questions: [
    QuestionRecord(
      id: 'six-q1',
      order: 1,
      text: 'سؤال 1',
      maxScore: 2,
      modelAnswer: '3/4',
    ),
    QuestionRecord(
      id: 'six-q2',
      order: 2,
      text: 'سؤال 2',
      maxScore: 2,
      modelAnswer: '1/5',
    ),
    QuestionRecord(
      id: 'six-q3',
      order: 3,
      text: 'سؤال 3',
      maxScore: 2,
      modelAnswer: '1/2',
    ),
    QuestionRecord(
      id: 'six-q4',
      order: 4,
      text: 'سؤال 4',
      maxScore: 2,
      modelAnswer: '3/4',
    ),
    QuestionRecord(
      id: 'six-q5',
      order: 5,
      text: 'سؤال 5',
      maxScore: 2,
      modelAnswer: '18 سم',
    ),
    QuestionRecord(
      id: 'six-q6',
      order: 6,
      text: 'سؤال 6',
      maxScore: 2,
      modelAnswer: 'لأننا ضربنا 1 في 2',
    ),
  ],
);

const _emptySixSubmission = SubmissionRecord(
  id: 'submission-six',
  studentId: 'student-1',
  studentName: 'طالب أ',
  studentCode: 'S-001',
  assessmentTitle: 'اختبار الكسور الأول',
  answers: [
    AnswerRecord(
      questionId: 'six-q1',
      order: 1,
      text: 'سؤال 1',
      maxScore: 2,
      answerText: '',
    ),
    AnswerRecord(
      questionId: 'six-q2',
      order: 2,
      text: 'سؤال 2',
      maxScore: 2,
      answerText: '',
    ),
    AnswerRecord(
      questionId: 'six-q3',
      order: 3,
      text: 'سؤال 3',
      maxScore: 2,
      answerText: '',
    ),
    AnswerRecord(
      questionId: 'six-q4',
      order: 4,
      text: 'سؤال 4',
      maxScore: 2,
      answerText: '',
    ),
    AnswerRecord(
      questionId: 'six-q5',
      order: 5,
      text: 'سؤال 5',
      maxScore: 2,
      answerText: '',
    ),
    AnswerRecord(
      questionId: 'six-q6',
      order: 6,
      text: 'سؤال 6',
      maxScore: 2,
      answerText: '',
    ),
  ],
);

const _sixOcrMapping = OcrMappingRecord(
  candidates: [
    OcrCandidateRecord(
      id: 'six-cand-1',
      questionId: 'six-q1',
      order: 1,
      questionText: 'سؤال 1',
      maxScore: 2,
      extractedText: '3/4',
      status: 'suggested',
      currentAnswer: '',
    ),
    OcrCandidateRecord(
      id: 'six-cand-2',
      questionId: 'six-q2',
      order: 2,
      questionText: 'سؤال 2',
      maxScore: 2,
      extractedText: '1/5',
      status: 'suggested',
      currentAnswer: '',
    ),
    OcrCandidateRecord(
      id: 'six-cand-3',
      questionId: 'six-q3',
      order: 3,
      questionText: 'سؤال 3',
      maxScore: 2,
      extractedText: '1/2',
      status: 'suggested',
      currentAnswer: '',
    ),
    OcrCandidateRecord(
      id: 'six-cand-4',
      questionId: 'six-q4',
      order: 4,
      questionText: 'سؤال 4',
      maxScore: 2,
      extractedText: '3/4',
      status: 'suggested',
      currentAnswer: '',
    ),
    OcrCandidateRecord(
      id: 'six-cand-5',
      questionId: 'six-q5',
      order: 5,
      questionText: 'سؤال 5',
      maxScore: 2,
      extractedText: '18 سم',
      status: 'suggested',
      currentAnswer: '',
    ),
    OcrCandidateRecord(
      id: 'six-cand-6',
      questionId: 'six-q6',
      order: 6,
      questionText: 'سؤال 6',
      maxScore: 2,
      extractedText: 'لأننا ضربنا 1 في 2',
      status: 'suggested',
      currentAnswer: '',
    ),
  ],
  incompleteOcr: false,
);

const _secondAttachment = AttachmentRecord(
  id: 'attachment-2',
  filename: 'صفحة-2.png',
  contentType: 'image/png',
  fileSize: 1024,
);

const _completedOcr = OcrRecord(
  id: 'ocr-1',
  status: 'completed',
  extractedText: 'الإجابة هي ثلاثة أرباع',
);

const _failedOcr = OcrRecord(id: 'ocr-1', status: 'failed', extractedText: '');

const _emptyAssessment = AssessmentRecord(
  id: 'assessment-1',
  title: 'اختبار الكسور الأول',
  classroomId: 'class-6a',
  classroomName: 'سادس أ',
  grade: 'الصف السادس',
  subject: 'الرياضيات',
  questionsCount: 0,
  totalScore: 0,
);

Future<void> _signIn(
  WidgetTester tester,
  String buttonLabel, {
  bool settle = true,
  bool skipWelcome = true,
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'user');
  await tester.enterText(find.byType(TextFormField).at(1), 'password');
  await tester.tap(find.text(buttonLabel));
  await tester.pump();
  await tester.pump();
  if (skipWelcome) {
    final duration =
        WelcomeTransitionPage.debugDurationOverride ??
        WelcomeTransitionPage.playDuration;
    await tester.pump(duration + const Duration(milliseconds: 20));
    await tester.pump();
  }
  if (settle) {
    await tester.pumpAndSettle();
  }
}

/// Leaves the teacher dashboard for the assessments screen. [settle] is off
/// when the destination shows a spinner, which never stops animating.
Future<void> _openAssessments(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  await tester.tap(find.text(label));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Signs in and walks dashboard → assessments → details → submissions, which
/// is how a teacher reaches the roster.
Future<void> _reachSubmissions(
  WidgetTester tester, {
  required String signIn,
  required String assessments,
  required String submissions,
}) async {
  await _signIn(tester, signIn);
  await _openAssessments(tester, assessments);
  await tester.tap(find.text('اختبار الكسور الأول'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(submissions));
  await tester.pumpAndSettle();
}

/// Carries on from the roster into one student's answer sheet.
Future<void> _reachEntry(
  WidgetTester tester, {
  required String signIn,
  required String assessments,
  required String submissions,
  String student = 'طالب أ',
}) async {
  await _reachSubmissions(
    tester,
    signIn: signIn,
    assessments: assessments,
    submissions: submissions,
  );
  await tester.tap(find.text(student));
  await tester.pumpAndSettle();
}

/// The student-paper section plus a full answer sheet is taller than the
/// default 800x600 viewport, and a lazy [ListView] never builds what falls
/// outside it. Tests that assert on the whole sheet at once need the room.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Taps a control that may sit below the fold of the 800x600 test viewport.
/// Sticky bars have no [Scrollable] ancestor, so those taps skip scrolling.
Future<void> _scrollAndTap(WidgetTester tester, String label) async {
  final target = find.text(label);
  final scrollable = find.ancestor(
    of: target,
    matching: find.byType(Scrollable),
  );
  if (scrollable.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _expandEvaluationDetails(WidgetTester tester) async {
  for (final label in ['عرض تفاصيل التقييم', 'View evaluation details']) {
    while (find.text(label).evaluate().isNotEmpty) {
      final target = find.text(label).first;
      final scrollable = find.ancestor(
        of: target,
        matching: find.byType(Scrollable),
      );
      if (scrollable.evaluate().isNotEmpty) {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
      }
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
  }
}

/// RTL: archive is start-to-end (drag left), delete is end-to-start (drag right).
Future<void> _swipeAssessment(
  WidgetTester tester, {
  required bool archive,
}) async {
  final offset = archive ? const Offset(-500, 0) : const Offset(500, 0);
  await tester.fling(find.byType(Dismissible), offset, 1000);
  await tester.pumpAndSettle();
}

/// Lets a snack bar expire so its timer does not outlive the test.
Future<void> _settleSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _pickLanguage(WidgetTester tester, String label) async {
  await tester.tap(find.byType(PopupMenuButton<AppLocale>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class FakeGateway implements BayyinGateway {
  FakeGateway({
    required this.role,
    this.failLogin = false,
    this.classrooms = const [],
    this.teachers = const [],
    this.students = const [],
    this.classroomsError,
    this.classroomsFuture,
    this.username,
    this.fullName = '',
    this.serverDisplayName = '',
    List<AssessmentRecord> assessments = const [],
    this.assessmentsError,
    this.assessmentsFuture,
    List<SubmissionRecord> submissions = const [],
    List<AttachmentRecord> attachments = const [],
    Map<String, OcrRecord> ocrResults = const {},
    this.uploadError,
    this.uploadGate,
    this.ocrError,
    this.ocrGate,
    this.ocrText = 'ثلاثة أرباع',
    this.ocrMapping,
    this.mappingError,
    this.mappingGate,
    this.evaluateError,
    this.evaluateGate,
    this.evaluateFailedCount = 0,
    this.resultError,
    this.classInsights,
    this.classInsightsError,
    List<RemediationPlanRecord> remediationPlans = const [],
    this.generatePlanError,
    this.remediationGate,
    this.generatedPlan,
    this.managerInsights,
    this.managerInsightsError,
    Map<String, EvaluationRecord> evaluationsByQuestionId = const {},
    List<QuestionCandidateRecord> questionCandidates = const [],
    this.examUploadError,
    this.examUploadGate,
    this.extractError,
    this.extractGate,
  }) : _classrooms = [...classrooms],
       _students = [...students],
       _assessments = [...assessments],
       _submissions = [...submissions],
       _attachments = [...attachments],
       _ocrResults = Map.of(ocrResults),
       evaluationsByQuestionId = Map.of(evaluationsByQuestionId),
       _remediationPlans = [...remediationPlans],
       _questionCandidates = [...questionCandidates];

  final String role;
  final bool failLogin;

  /// Stands in for what Django returns for the signed-in user.
  final String? username;
  final String fullName;
  final String serverDisplayName;
  final List<ClassroomRecord> classrooms;
  final List<ClassroomRecord> _classrooms;
  final List<TeacherAccount> teachers;
  final List<StudentRecord> students;
  final List<StudentRecord> _students;
  final Object? classroomsError;
  final Future<List<ClassroomRecord>>? classroomsFuture;

  /// Mutable so a created assessment or question shows up on the next read,
  /// the way the real API behaves.
  final List<AssessmentRecord> _assessments;
  final Object? assessmentsError;
  final Future<List<AssessmentRecord>>? assessmentsFuture;

  final List<SubmissionRecord> _submissions;
  final List<AttachmentRecord> _attachments;
  final Map<String, OcrRecord> _ocrResults;
  final Object? uploadError;
  final Object? ocrError;

  /// Held by a test that wants to catch the uploading state before the request
  /// resolves.
  final Completer<void>? uploadGate;
  final Completer<void>? ocrGate;
  final String ocrText;
  final OcrMappingRecord? ocrMapping;
  final Object? mappingError;
  final Completer<void>? mappingGate;
  final Object? evaluateError;
  final Completer<void>? evaluateGate;
  final int evaluateFailedCount;
  final Object? resultError;
  final ClassInsightsRecord? classInsights;
  final Object? classInsightsError;
  final Object? generatePlanError;
  final Completer<void>? remediationGate;
  final RemediationPlanRecord? generatedPlan;
  final ManagerInsightsRecord? managerInsights;
  final Object? managerInsightsError;
  final List<RemediationPlanRecord> _remediationPlans;
  final Map<String, EvaluationRecord> evaluationsByQuestionId;
  final List<QuestionCandidateRecord> _questionCandidates;
  final Object? examUploadError;
  final Completer<void>? examUploadGate;
  final Object? extractError;
  final Completer<void>? extractGate;

  /// Lets a test prove an existing submission was reused instead of recreated.
  int createSubmissionCalls = 0;

  /// Lets a test prove a file rejected on the device never left it.
  int uploadCalls = 0;
  int runOcrCalls = 0;
  int mappingCalls = 0;
  int confirmMappingCalls = 0;
  int evaluateCalls = 0;
  int generatePlanCalls = 0;
  int examUploadCalls = 0;
  int extractCalls = 0;
  int confirmQuestionsCalls = 0;
  final List<String> evaluateLocales = [];
  final List<String> generatePlanLocales = [];

  @override
  Future<UserSession> login(String username, String password) async {
    if (failLogin) {
      throw const ApiException('بيانات الدخول غير صحيحة أو الحساب غير نشط.');
    }
    return UserSession(
      token: 'test-token',
      username: this.username ?? username,
      fullName: fullName,
      serverDisplayName: serverDisplayName,
      role: role,
    );
  }

  @override
  Future<List<TeacherAccount>> fetchTeachers(String token) async => teachers;

  @override
  Future<List<ClassroomRecord>> fetchClassrooms(String token) {
    if (classroomsFuture != null) return classroomsFuture!;
    if (classroomsError != null) return Future.error(classroomsError!);
    return Future.value(List<ClassroomRecord>.from(_classrooms));
  }

  @override
  Future<List<StudentRecord>> fetchStudents({
    required String token,
    required String classroomId,
  }) async => List<StudentRecord>.from(_students);

  @override
  Future<TeacherAccount> createTeacher({
    required String token,
    required String username,
    required String password,
    required String firstName,
    required String lastName,
    required String email,
  }) async => TeacherAccount(
    id: '1',
    profileId: 'profile-1',
    username: username,
    fullName: '$firstName $lastName',
    email: email,
    isActive: true,
  );

  @override
  Future<ClassroomRecord> createClassroom({
    required String token,
    required String name,
    required String grade,
    required String subject,
    required String academicYear,
    required String teacherProfileId,
  }) async {
    final classroom = ClassroomRecord(
      id: 'classroom-${_classrooms.length + 1}',
      name: name,
      grade: grade,
      subject: subject,
      academicYear: academicYear,
      teacherName: _teacherName(teacherProfileId),
      teacherProfileId: teacherProfileId,
      studentsCount: 0,
    );
    _classrooms.add(classroom);
    return classroom;
  }

  @override
  Future<ClassroomRecord> updateClassroom({
    required String token,
    required String classroomId,
    required String name,
    required String grade,
    required String subject,
    required String academicYear,
    required String teacherProfileId,
  }) async {
    final updated = ClassroomRecord(
      id: classroomId,
      name: name,
      grade: grade,
      subject: subject,
      academicYear: academicYear,
      teacherName: _teacherName(teacherProfileId),
      teacherProfileId: teacherProfileId,
      studentsCount: _classroomById(classroomId)?.studentsCount ?? 0,
      assessmentsCount: _classroomById(classroomId)?.assessmentsCount ?? 0,
    );
    final index = _classrooms.indexWhere((item) => item.id == classroomId);
    if (index >= 0) {
      _classrooms[index] = updated;
    } else {
      _classrooms.add(updated);
    }
    return updated;
  }

  @override
  Future<void> deleteClassroom({
    required String token,
    required String classroomId,
  }) async {
    _classrooms.removeWhere((item) => item.id == classroomId);
  }

  ClassroomRecord? _classroomById(String id) {
    for (final classroom in _classrooms) {
      if (classroom.id == id) return classroom;
    }
    return null;
  }

  String _teacherName(String teacherProfileId) {
    for (final teacher in teachers) {
      if (teacher.profileId == teacherProfileId) return teacher.displayName;
    }
    return 'teacher';
  }

  @override
  Future<void> createStudent({
    required String token,
    required String classroomId,
    required String internalCode,
    required String displayName,
  }) async {
    _students.add(
      StudentRecord(
        id: 'student-${_students.length + 1}',
        internalCode: internalCode,
        displayName: displayName,
      ),
    );
    final classroom = _classroomById(classroomId);
    if (classroom != null) {
      final index = _classrooms.indexWhere((item) => item.id == classroomId);
      if (index >= 0) {
        _classrooms[index] = classroom.copyWith(
          studentsCount: classroom.studentsCount + 1,
        );
      }
    }
  }

  @override
  Future<List<AssessmentRecord>> fetchAssessments(
    String token, {
    bool archived = false,
  }) {
    if (assessmentsFuture != null) return assessmentsFuture!;
    if (assessmentsError != null) return Future.error(assessmentsError!);
    return Future.value([
      for (final assessment in _assessments)
        if (assessment.isArchived == archived) assessment,
    ]);
  }

  @override
  Future<AssessmentRecord> fetchAssessment({
    required String token,
    required String assessmentId,
  }) async =>
      _assessments.firstWhere((assessment) => assessment.id == assessmentId);

  @override
  Future<AssessmentRecord> createAssessment({
    required String token,
    required String classroomId,
    required String title,
  }) async {
    final classroom = classrooms.firstWhere(
      (candidate) => candidate.id == classroomId,
    );
    final created = AssessmentRecord(
      id: 'assessment-${_assessments.length + 1}',
      title: title,
      classroomId: classroom.id,
      classroomName: classroom.name,
      grade: classroom.grade,
      subject: classroom.subject,
      questionsCount: 0,
      totalScore: 0,
    );
    _assessments.add(created);
    return created;
  }

  @override
  Future<AssessmentRecord> setAssessmentArchived({
    required String token,
    required String assessmentId,
    required bool archived,
  }) async {
    final index = _assessments.indexWhere(
      (assessment) => assessment.id == assessmentId,
    );
    final updated = _assessments[index].copyWith(
      archivedAt: archived ? DateTime.utc(2026, 1, 1) : null,
      clearArchivedAt: !archived,
    );
    _assessments[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteAssessment({
    required String token,
    required String assessmentId,
  }) async {
    _assessments.removeWhere((assessment) => assessment.id == assessmentId);
  }

  @override
  Future<QuestionRecord> createQuestion({
    required String token,
    required String assessmentId,
    required String text,
    required double maxScore,
    required String modelAnswer,
  }) async {
    final index = _assessments.indexWhere(
      (assessment) => assessment.id == assessmentId,
    );
    final assessment = _assessments[index];
    final question = QuestionRecord(
      id: 'question-${assessment.questions.length + 1}',
      order: assessment.questions.length + 1,
      text: text,
      maxScore: maxScore,
      modelAnswer: modelAnswer,
    );
    _assessments[index] = _withQuestions(assessment, [
      ...assessment.questions,
      question,
    ]);
    return question;
  }

  @override
  Future<void> deleteQuestion({
    required String token,
    required String assessmentId,
    required String questionId,
  }) async {
    final index = _assessments.indexWhere(
      (assessment) => assessment.id == assessmentId,
    );
    final assessment = _assessments[index];
    _assessments[index] = _withQuestions(assessment, [
      for (final question in assessment.questions)
        if (question.id != questionId) question,
    ]);
  }

  @override
  Future<void> uploadExamPaper({
    required String token,
    required String assessmentId,
    required String filename,
    required Uint8List bytes,
  }) async {
    examUploadCalls++;
    if (examUploadGate != null) await examUploadGate!.future;
    if (examUploadError != null) throw examUploadError!;
  }

  @override
  Future<List<QuestionCandidateRecord>> extractQuestions({
    required String token,
    required String assessmentId,
  }) async {
    extractCalls++;
    if (extractGate != null) await extractGate!.future;
    if (extractError != null) throw extractError!;
    return [..._questionCandidates];
  }

  @override
  Future<List<QuestionCandidateRecord>> fetchQuestionCandidates({
    required String token,
    required String assessmentId,
  }) async => [..._questionCandidates];

  @override
  Future<AssessmentRecord> confirmQuestionCandidates({
    required String token,
    required String assessmentId,
    required List<QuestionCandidateRecord> candidates,
  }) async {
    confirmQuestionsCalls++;
    final index = _assessments.indexWhere(
      (assessment) => assessment.id == assessmentId,
    );
    final assessment = _assessments[index];
    final questions = [
      for (final candidate in candidates)
        QuestionRecord(
          id: candidate.id.isEmpty
              ? 'question-${candidate.order}'
              : 'question-${candidate.id}',
          order: candidate.order,
          text: candidate.extractedText,
          maxScore: candidate.proposedMaxScore ?? 0,
          modelAnswer: candidate.proposedModelAnswer,
        ),
    ];
    _assessments[index] = _withQuestions(assessment, questions);
    _questionCandidates
      ..clear()
      ..addAll(candidates);
    return _assessments[index];
  }

  /// Mirrors the real list endpoint, which returns summaries without answers.
  @override
  Future<List<SubmissionRecord>> fetchSubmissions({
    required String token,
    required String assessmentId,
  }) async => [
    for (final submission in _submissions)
      SubmissionRecord(
        id: submission.id,
        studentId: submission.studentId,
        studentName: submission.studentName,
        studentCode: submission.studentCode,
      ),
  ];

  @override
  Future<SubmissionRecord> fetchSubmission({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async =>
      _submissions.firstWhere((submission) => submission.id == submissionId);

  @override
  Future<SubmissionRecord> createSubmission({
    required String token,
    required String assessmentId,
    required String studentId,
  }) async {
    createSubmissionCalls++;
    if (_submissions.any((submission) => submission.studentId == studentId)) {
      throw const ApiException('لهذا الطالب تسليم مسجل في هذا الاختبار.');
    }
    final student = students.firstWhere((entry) => entry.id == studentId);
    final assessment = _assessments.firstWhere(
      (entry) => entry.id == assessmentId,
    );
    final created = SubmissionRecord(
      id: 'submission-${_submissions.length + 1}',
      studentId: student.id,
      studentName: student.displayName,
      studentCode: student.internalCode,
      assessmentTitle: assessment.title,
      answers: [
        for (final question in assessment.questions)
          AnswerRecord(
            questionId: question.id,
            order: question.order,
            text: question.text,
            maxScore: question.maxScore,
            answerText: '',
          ),
      ],
    );
    _submissions.add(created);
    return created;
  }

  final List<Map<String, String>> savedAnswerPayloads = [];

  @override
  Future<SubmissionRecord> saveAnswers({
    required String token,
    required String assessmentId,
    required String submissionId,
    required Map<String, String> answersByQuestionId,
  }) async {
    savedAnswerPayloads.add(Map<String, String>.from(answersByQuestionId));
    final index = _submissions.indexWhere(
      (submission) => submission.id == submissionId,
    );
    final submission = _submissions[index];
    final updated = SubmissionRecord(
      id: submission.id,
      studentId: submission.studentId,
      studentName: submission.studentName,
      studentCode: submission.studentCode,
      assessmentTitle: submission.assessmentTitle,
      answers: [
        for (final answer in submission.answers)
          answer.copyWith(
            id: answer.id ?? 'answer-${answer.questionId}',
            answerText:
                answersByQuestionId[answer.questionId] ?? answer.answerText,
            clearEvaluation:
                (answersByQuestionId[answer.questionId] ?? answer.answerText) !=
                answer.answerText,
          ),
      ],
    );
    _submissions[index] = updated;
    return updated;
  }

  @override
  Future<List<AttachmentRecord>> fetchAttachments({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async => [..._attachments];

  @override
  Future<AttachmentRecord> uploadAttachment({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String filename,
    required Uint8List bytes,
  }) async {
    uploadCalls++;
    if (uploadGate != null) await uploadGate!.future;
    if (uploadError != null) throw uploadError!;
    final created = AttachmentRecord(
      id: 'attachment-${_attachments.length + 1}',
      filename: filename,
      // The real server derives this from the bytes; here the name is enough.
      contentType: switch (filename.split('.').last.toLowerCase()) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        _ => 'image/jpeg',
      },
      fileSize: bytes.length,
    );
    _attachments.add(created);
    return created;
  }

  @override
  Future<void> deleteAttachment({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String attachmentId,
  }) async => _attachments.removeWhere((item) => item.id == attachmentId);

  @override
  Future<OcrRecord?> fetchOcr({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String attachmentId,
  }) async => _ocrResults[attachmentId];

  @override
  Future<OcrRecord> runOcr({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String attachmentId,
  }) async {
    runOcrCalls++;
    if (ocrGate != null) await ocrGate!.future;
    if (ocrError != null) {
      final failed = OcrRecord(
        id: 'ocr-$attachmentId',
        status: 'failed',
        extractedText: '',
      );
      _ocrResults[attachmentId] = failed;
      return failed;
    }
    final created = OcrRecord(
      id: 'ocr-$attachmentId',
      status: 'completed',
      extractedText: ocrText,
    );
    _ocrResults[attachmentId] = created;
    return created;
  }

  @override
  Future<OcrMappingRecord> fetchOcrMapping({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async =>
      ocrMapping ??
      const OcrMappingRecord(candidates: [], incompleteOcr: false);

  @override
  Future<OcrMappingRecord> runOcrMapping({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async {
    mappingCalls++;
    if (mappingGate != null) await mappingGate!.future;
    if (mappingError != null) throw mappingError!;
    final mapping = ocrMapping;
    if (mapping == null) {
      throw const ApiException('لا يوجد نص مستخرج يمكن استخدامه بعد.');
    }
    return mapping;
  }

  @override
  Future<OcrMappingRecord> confirmOcrMapping({
    required String token,
    required String assessmentId,
    required String submissionId,
    required Map<String, String> answersByQuestionId,
  }) async {
    confirmMappingCalls++;
    if (mappingError != null) throw mappingError!;
    await saveAnswers(
      token: token,
      assessmentId: assessmentId,
      submissionId: submissionId,
      answersByQuestionId: answersByQuestionId,
    );
    return ocrMapping ??
        const OcrMappingRecord(candidates: [], incompleteOcr: false);
  }

  @override
  Future<SubmissionRecord> evaluateAnswers({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String locale,
  }) async {
    evaluateCalls++;
    evaluateLocales.add(locale);
    if (evaluateGate != null) await evaluateGate!.future;
    if (evaluateError != null) throw evaluateError!;
    final index = _submissions.indexWhere(
      (submission) => submission.id == submissionId,
    );
    final submission = _submissions[index];
    final confirmed = [
      for (final answer in submission.answers)
        if (answer.isConfirmed) answer,
    ];
    if (confirmed.isEmpty) {
      throw const ApiException('لا توجد إجابات مؤكدة للتقييم.');
    }
    final updated = SubmissionRecord(
      id: submission.id,
      studentId: submission.studentId,
      studentName: submission.studentName,
      studentCode: submission.studentCode,
      assessmentTitle: submission.assessmentTitle,
      failedCount: evaluateFailedCount,
      answers: [
        for (final answer in submission.answers)
          if (answer.isConfirmed)
            answer.copyWith(
              evaluation:
                  evaluationsByQuestionId[answer.questionId] ??
                  _defaultEvaluation(answer),
            )
          else
            answer,
      ],
    );
    _submissions[index] = updated;
    return updated;
  }

  @override
  Future<SubmissionResultRecord> fetchSubmissionResult({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async {
    if (resultError != null) throw resultError!;
    final submission = _submissions.firstWhere(
      (item) => item.id == submissionId,
    );
    return _resultFrom(submission);
  }

  @override
  Future<ClassInsightsRecord> fetchClassInsights({
    required String token,
    required String assessmentId,
  }) async {
    if (classInsightsError != null) throw classInsightsError!;
    return classInsights ??
        const ClassInsightsRecord(
          summary: ClassInsightsSummary(
            totalStudentsInClass: 0,
            studentsWithSubmission: 0,
            studentsWithoutSubmission: 0,
            completeResults: 0,
            incompleteResults: 0,
          ),
        );
  }

  @override
  Future<List<RemediationPlanRecord>> fetchRemediationPlans({
    required String token,
    required String assessmentId,
  }) async => List.of(_remediationPlans);

  @override
  Future<RemediationGenerateRecord> generateRemediationPlan({
    required String token,
    required String assessmentId,
    required String group,
    required String locale,
  }) async {
    generatePlanCalls++;
    generatePlanLocales.add(locale);
    if (remediationGate != null) await remediationGate!.future;
    if (generatePlanError != null) throw generatePlanError!;
    final hadPlan = _remediationPlans.any((item) => item.group == group);
    final source = generatedPlan;
    final plan = RemediationPlanRecord(
      id: source?.id ?? 'plan-$group',
      group: group,
      status: 'completed',
      title: hadPlan ? 'خطة محدثة' : (source?.title ?? 'خطة تأسيس الكسور'),
      summary: source?.summary ?? 'بناء مفهوم الكسر من المحسوس إلى الرمز.',
      teacherGuidance:
          source?.teacherGuidance ?? 'ابدأ بالمحسوس ثم انتقل إلى الرمز.',
      objectives: source?.objectives ?? const ['يفهم معنى المقام'],
      activities:
          source?.activities ??
          const [
            RemediationActivityRecord(
              title: 'أمثلة موجهة',
              description: 'حل مثالين مع المعلم.',
              durationMinutes: 15,
            ),
          ],
    );
    _remediationPlans.removeWhere((item) => item.group == group);
    _remediationPlans.add(plan);
    return RemediationGenerateRecord(
      groupEmpty: false,
      group: group,
      plan: plan,
    );
  }

  @override
  Future<ManagerInsightsRecord> fetchManagerInsights(String token) async {
    if (managerInsightsError != null) throw managerInsightsError!;
    return managerInsights ??
        const ManagerInsightsRecord(
          summary: ManagerInsightsSummary(
            totalTeachers: 0,
            totalClassrooms: 0,
            totalStudents: 0,
            totalAssessments: 0,
            assessmentsWithCompleteResults: 0,
            assessmentsWithIncompleteResults: 0,
          ),
        );
  }

  SubmissionResultRecord _resultFrom(SubmissionRecord submission) {
    var awarded = 0.0;
    var evaluatedMax = 0.0;
    var correct = 0;
    var partial = 0;
    var incorrect = 0;
    final gaps = <GapRecord>[];
    final misconceptions = <String>[];
    final seen = <String>{};
    for (final answer in submission.answers) {
      final evaluation = answer.evaluation;
      if (evaluation == null) continue;
      awarded += evaluation.awardedScore;
      evaluatedMax += answer.maxScore;
      switch (evaluation.status) {
        case 'correct':
          correct++;
        case 'partial':
          partial++;
          gaps.add(_gapFrom(answer, evaluation));
        case 'incorrect':
          incorrect++;
          gaps.add(_gapFrom(answer, evaluation));
      }
      final misconception = evaluation.misconception.trim();
      if (misconception.isNotEmpty && seen.add(misconception)) {
        misconceptions.add(misconception);
      }
    }
    final evaluated = correct + partial + incorrect;
    final total = submission.answers.length;
    final evaluable = total > 0;
    final maxTotal = submission.answers.fold<double>(
      0,
      (sum, answer) => sum + answer.maxScore,
    );
    return SubmissionResultRecord(
      isEvaluable: evaluable,
      isComplete: evaluable && unevaluated(evaluated, total) == 0,
      awardedScoreTotal: awarded,
      maxScoreTotal: maxTotal,
      percentage: evaluatedMax <= 0
          ? 0
          : double.parse((awarded / evaluatedMax * 100).toStringAsFixed(2)),
      evaluatedQuestions: evaluated,
      totalQuestions: total,
      correctCount: correct,
      partialCount: partial,
      incorrectCount: incorrect,
      unevaluatedCount: unevaluated(evaluated, total),
      gaps: gaps,
      misconceptions: misconceptions,
    );
  }

  int unevaluated(int evaluated, int total) => total - evaluated;

  GapRecord _gapFrom(AnswerRecord answer, EvaluationRecord evaluation) =>
      GapRecord(
        questionId: answer.questionId,
        questionOrder: answer.order,
        questionText: answer.text,
        status: evaluation.status,
        awardedScore: evaluation.awardedScore,
        maxScore: answer.maxScore,
        feedback: evaluation.feedback,
        misconception: evaluation.misconception,
      );

  EvaluationRecord _defaultEvaluation(AnswerRecord answer) {
    if (answer.answerText.trim().isEmpty) {
      return const EvaluationRecord(
        status: 'incorrect',
        awardedScore: 0,
        feedback: 'لم يُدخل الطالب إجابة.',
      );
    }
    return EvaluationRecord(
      status: 'correct',
      awardedScore: answer.maxScore,
      feedback: 'الإجابة صحيحة.',
    );
  }

  @override
  Future<void> logout(String token) async {}
}

/// Stands in for the platform file dialog, which widget tests cannot open.
class FakeAttachmentPicker implements AttachmentPicker {
  FakeAttachmentPicker({this.filename, this.byteCount = 2048});

  /// A null name stands for the teacher dismissing the dialog.
  final String? filename;
  final int byteCount;

  @override
  Future<PickedAttachment?> pick() async {
    final name = filename;
    if (name == null) return null;
    return PickedAttachment(filename: name, bytes: Uint8List(byteCount));
  }
}

AssessmentRecord _withQuestions(
  AssessmentRecord assessment,
  List<QuestionRecord> questions,
) => assessment.copyWith(
  questionsCount: questions.length,
  totalScore: questions.fold<double>(
    0,
    (sum, question) => sum + question.maxScore,
  ),
  questions: questions,
);
