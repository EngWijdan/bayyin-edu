import 'dart:async';

import 'package:bayyin_teacher/l10n/app_language.dart';
import 'package:bayyin_teacher/main.dart';
import 'package:bayyin_teacher/services/bayyin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('العربية', () {
    testWidgets('يعرض شاشة تسجيل الدخول أولًا', (tester) async {
      await tester.pumpWidget(BayyinApp(gateway: FakeGateway(role: 'TEACHER')));
      expect(find.text('مرحبًا بك في بيّن'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
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
            classroomsError: const ApiException('تعذر إكمال الطلب. حاول مرة أخرى.'),
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
        BayyinApp(gateway: FakeGateway(role: 'TEACHER', username: 'teacher-42')),
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

    test('UserSession يطبق ترتيب الأولوية display_name ثم full_name ثم username', () {
      UserSession session({String display = '', String full = ''}) => UserSession(
        token: 't',
        username: 'fallback-user',
        fullName: full,
        serverDisplayName: display,
        role: 'TEACHER',
      );

      expect(session(display: 'د. نورة', full: 'نورة').displayName, 'د. نورة');
      expect(session(full: 'نورة').displayName, 'نورة');
      expect(session().displayName, 'fallback-user');
      expect(session(display: '   ', full: '  ').displayName, 'fallback-user');
    });
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

      await tester.enterText(
        find.byType(TextFormField),
        'اختبار الكسور الأول',
      );
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

      await tester.enterText(find.byType(TextFormField), 'First fractions test');
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
      await tester.tap(find.text('Add question'));
      await tester.pumpAndSettle();

      expect(find.text('Question text'), findsOneWidget);
      expect(find.text('Maximum score'), findsOneWidget);
      expect(find.text('Model answer'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'What is 1/2 + 1/4?');
      await tester.enterText(find.byType(TextFormField).at(1), '2.5');
      await tester.enterText(find.byType(TextFormField).at(2), '3/4');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('What is 1/2 + 1/4?'), findsOneWidget);
      expect(find.textContaining('Max score: 2.5'), findsOneWidget);
      expect(find.textContaining('1 question'), findsOneWidget);
      await _settleSnackBars(tester);
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

    testWidgets('تحفظ الإجابات المعدلة وتؤكد الحفظ', (tester) async {
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
    });

    testWidgets('enters and saves answers in English', (tester) async {
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
  });
}

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
      questionId: 'question-1',
      order: 1,
      text: 'ما ناتج 1/2 + 1/4؟',
      maxScore: 2,
      answerText: '3/4',
    ),
    AnswerRecord(
      questionId: 'question-2',
      order: 2,
      text: 'بسّط الكسر 4/8',
      maxScore: 3,
      answerText: '',
    ),
  ],
);

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
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'user');
  await tester.enterText(find.byType(TextFormField).at(1), 'password');
  await tester.tap(find.text(buttonLabel));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
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

/// Taps a control that may sit below the fold of the 800x600 test viewport.
Future<void> _scrollAndTap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
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
  }) : _assessments = [...assessments],
       _submissions = [...submissions];

  final String role;
  final bool failLogin;

  /// Stands in for what Django returns for the signed-in user.
  final String? username;
  final String fullName;
  final String serverDisplayName;
  final List<ClassroomRecord> classrooms;
  final List<StudentRecord> students;
  final Object? classroomsError;
  final Future<List<ClassroomRecord>>? classroomsFuture;

  /// Mutable so a created assessment or question shows up on the next read,
  /// the way the real API behaves.
  final List<AssessmentRecord> _assessments;
  final Object? assessmentsError;
  final Future<List<AssessmentRecord>>? assessmentsFuture;

  final List<SubmissionRecord> _submissions;

  /// Lets a test prove an existing submission was reused instead of recreated.
  int createSubmissionCalls = 0;

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
  Future<List<TeacherAccount>> fetchTeachers(String token) async => [];

  @override
  Future<List<ClassroomRecord>> fetchClassrooms(String token) {
    if (classroomsFuture != null) return classroomsFuture!;
    if (classroomsError != null) return Future.error(classroomsError!);
    return Future.value(classrooms);
  }

  @override
  Future<List<StudentRecord>> fetchStudents({
    required String token,
    required String classroomId,
  }) async => students;

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
  }) async => ClassroomRecord(
    id: 'classroom-1',
    name: name,
    grade: grade,
    subject: subject,
    academicYear: academicYear,
    teacherName: 'teacher',
    studentsCount: 0,
  );

  @override
  Future<void> createStudent({
    required String token,
    required String classroomId,
    required String internalCode,
    required String displayName,
  }) async {}

  @override
  Future<List<AssessmentRecord>> fetchAssessments(String token) {
    if (assessmentsFuture != null) return assessmentsFuture!;
    if (assessmentsError != null) return Future.error(assessmentsError!);
    return Future.value(List.of(_assessments));
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

  @override
  Future<SubmissionRecord> saveAnswers({
    required String token,
    required String assessmentId,
    required String submissionId,
    required Map<String, String> answersByQuestionId,
  }) async {
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
          AnswerRecord(
            questionId: answer.questionId,
            order: answer.order,
            text: answer.text,
            maxScore: answer.maxScore,
            answerText:
                answersByQuestionId[answer.questionId] ?? answer.answerText,
          ),
      ],
    );
    _submissions[index] = updated;
    return updated;
  }

  @override
  Future<void> logout(String token) async {}
}

AssessmentRecord _withQuestions(
  AssessmentRecord assessment,
  List<QuestionRecord> questions,
) => AssessmentRecord(
  id: assessment.id,
  title: assessment.title,
  classroomId: assessment.classroomId,
  classroomName: assessment.classroomName,
  grade: assessment.grade,
  subject: assessment.subject,
  questionsCount: questions.length,
  totalScore: questions.fold(0, (sum, question) => sum + question.maxScore),
  questions: questions,
);
