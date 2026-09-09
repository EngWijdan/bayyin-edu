import 'package:flutter/widgets.dart';

/// The languages the app ships with. [label] is intentionally written in the
/// language itself so the switcher reads correctly whatever the active locale.
enum AppLocale {
  arabic(Locale('ar', 'SA'), 'العربية'),
  english(Locale('en'), 'English');

  const AppLocale(this.locale, this.label);

  final Locale locale;
  final String label;

  static AppLocale fromLocale(Locale locale) =>
      locale.languageCode == 'ar' ? AppLocale.arabic : AppLocale.english;
}

const supportedLocales = [Locale('ar', 'SA'), Locale('en')];

/// Implemented by `ApiException` so this layer can localise API failures
/// without depending on the networking layer.
abstract interface class ApiErrorMessage {
  String get message;
}

/// Single source of truth for every user facing string in the app.
@immutable
class AppStrings {
  const AppStrings._(this.isArabic);

  static const arabic = AppStrings._(true);
  static const english = AppStrings._(false);

  static AppStrings of(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar' ? arabic : english;

  final bool isArabic;

  String _(String ar, String en) => isArabic ? ar : en;

  // ---------------------------------------------------------------- general
  String get appName => _('بيّن', 'Bayyin');
  String get appTitle => _('بيّن للمعلم', 'Bayyin for Teachers');
  String get appTagline => _('مساعد القرار التعليمي', 'Teaching decision aid');
  String get language => _('اللغة', 'Language');
  String get save => _('حفظ', 'Save');
  String get cancel => _('إلغاء', 'Cancel');
  String get logout => _('تسجيل الخروج', 'Log out');
  String get retry => _('إعادة المحاولة', 'Try again');
  String get loading => _('جارٍ التحميل...', 'Loading...');
  String get saving => _('جارٍ الحفظ...', 'Saving...');
  String get requiredField => _('مطلوب', 'Required');

  // ------------------------------------------------------------------ login
  String get loginTitle => _('مرحبًا بك في بيّن', 'Welcome to Bayyin');
  String get loginSubtitle => _(
    'سجّل الدخول بحساب المدير أو المعلم',
    'Sign in as a manager or teacher',
  );
  String get username => _('اسم المستخدم', 'Username');
  String get password => _('كلمة المرور', 'Password');
  String get usernameRequired => _('أدخل اسم المستخدم', 'Enter your username');
  String get passwordRequired => _('أدخل كلمة المرور', 'Enter your password');
  String get signIn => _('تسجيل الدخول', 'Sign in');
  String get signingIn => _('جارٍ تسجيل الدخول...', 'Signing in...');
  String get loginConnectionError => _(
    'تعذر الاتصال بالخادم. تأكد من تشغيل Docker.',
    'Could not reach the server. Make sure Docker is running.',
  );

  // -------------------------------------------------------- manager: shell
  String get managerDashboard => _('لوحة المدير', 'Manager dashboard');
  String greeting(String name) => _('مرحبًا، $name', 'Welcome, $name');
  String get managerSubtitle => _(
    'أدر حسابات المعلمين الذين يستخدمون النظام.',
    'Manage the teacher accounts that use the system.',
  );

  // ----------------------------------------------------- manager: teachers
  String teachersCount(int count) =>
      _('المعلمون ($count)', 'Teachers ($count)');
  String get addTeacher => _('إضافة معلم', 'Add teacher');
  String get teacherActive => _('نشط', 'Active');
  String get teacherSuspended => _('موقوف', 'Suspended');
  String get noTeachersTitle => _('لا يوجد معلمون بعد', 'No teachers yet');
  String get noTeachersSubtitle => _(
    'ابدأ بإضافة أول معلم إلى نظام بيّن.',
    'Start by adding the first teacher to Bayyin.',
  );
  String get teacherCreated =>
      _('تم إنشاء حساب المعلم.', 'Teacher account created.');
  String get firstName => _('الاسم الأول', 'First name');
  String get lastName => _('اسم العائلة', 'Last name');
  String get emailOptional =>
      _('البريد الإلكتروني (اختياري)', 'Email (optional)');
  String get temporaryPassword =>
      _('كلمة المرور المؤقتة', 'Temporary password');
  String get passwordTooShort =>
      _('8 أحرف على الأقل', 'At least 8 characters');
  String get createAccount => _('إنشاء الحساب', 'Create account');

  // --------------------------------------------------- manager: classrooms
  String classroomsCount(int count) =>
      _('الصفوف ($count)', 'Classrooms ($count)');
  String get addClassroom => _('إضافة صف', 'Add classroom');
  String get createClassroom => _('إنشاء الصف', 'Create classroom');
  String get noClassrooms => _(
    'لا توجد صفوف بعد. أضف معلمًا ثم أنشئ أول صف.',
    'No classrooms yet. Add a teacher, then create the first one.',
  );
  String get addTeacherBeforeClassroom => _(
    'أضف معلمًا قبل إنشاء الصف.',
    'Add a teacher before creating a classroom.',
  );
  String get classroomName =>
      _('اسم الصف، مثل: سادس أ', 'Classroom name, e.g. Grade 6A');
  String get grade => _('المرحلة أو الصف الدراسي', 'Grade');
  String get subject => _('المادة', 'Subject');
  String get academicYear => _('العام الدراسي', 'Academic year');
  String get assignedTeacher => _('المعلم المسؤول', 'Assigned teacher');
  String get classroomCreated => _('تم إنشاء الصف.', 'Classroom created.');
  String classroomTitle(String name, String subject) =>
      '$name • $subject';
  String classroomSubtitle({
    required String grade,
    required String teacherName,
    required int studentsCount,
    required String academicYear,
  }) => _(
    '$grade • المعلم: $teacherName\n${studentsLabel(studentsCount)} • $academicYear',
    '$grade • Teacher: $teacherName\n${studentsLabel(studentsCount)} • $academicYear',
  );

  // ----------------------------------------------------- manager: students
  String get addStudent => _('إضافة طالب', 'Add student');
  String addStudentTo(String classroom) =>
      _('إضافة طالب إلى $classroom', 'Add student to $classroom');
  String get studentCode =>
      _('الرمز الداخلي، مثل S-001', 'Student code, e.g. S-001');
  String get studentNameOptional =>
      _('اسم الطالب (اختياري)', 'Student name (optional)');
  String get studentCreated => _('تمت إضافة الطالب.', 'Student added.');
  String studentsLabel(int count) {
    if (isArabic) {
      if (count == 1) return 'طالب واحد';
      if (count == 2) return 'طالبان';
      if (count >= 3 && count <= 10) return '$count طلاب';
      return '$count طالبًا';
    }
    return count == 1 ? '1 student' : '$count students';
  }

  // ---------------------------------------------------- teacher: dashboard
  String get myClasses => _('صفوفي', 'My classes');
  String get teacherClassesSubtitle => _(
    'هذه الصفوف المسندة إليك.',
    'These are the classes assigned to you.',
  );
  String get noAssignedClasses => _(
    'لم يُسند إليك أي صف بعد. تواصل مع مدير المدرسة.',
    'No classes are assigned to you yet. Please contact your school manager.',
  );
  String classroomMeta(String grade, String subject) => '$grade • $subject';
  String classroomCounts(String academicYear, int studentsCount) =>
      '$academicYear • ${studentsLabel(studentsCount)}';

  // ----------------------------------------------------- teacher: students
  String get students => _('الطلاب', 'Students');
  String get noStudentsInClass => _(
    'لا يوجد طلاب في هذا الصف بعد.',
    'There are no students in this class yet.',
  );
  String get unnamedStudent => _('بدون اسم', 'Unnamed');

  // -------------------------------------------------- teacher: assessments
  String get assessments => _('الاختبارات', 'Assessments');
  String get assessmentsSubtitle => _(
    'أنشئ اختبارات صفوفك وأضف أسئلتها.',
    'Create assessments for your classes and add their questions.',
  );
  String get createAssessment => _('إنشاء اختبار', 'Create assessment');
  String get assessmentTitle => _('اسم الاختبار', 'Assessment title');
  String get assessmentTitleHint =>
      _('مثال: اختبار الكسور الأول', 'e.g. First fractions test');
  String get assessmentClassroom => _('الصف', 'Classroom');
  String get noAssessments => _('لا توجد اختبارات بعد', 'No assessments yet');
  String get noAssessmentsSubtitle => _(
    'ابدأ بإنشاء أول اختبار لأحد صفوفك.',
    'Start by creating the first assessment for one of your classes.',
  );
  String get assessmentCreated => _('تم إنشاء الاختبار.', 'Assessment created.');
  String get noClassroomForAssessment => _(
    'لم يُسند إليك أي صف بعد، لذلك لا يمكن إنشاء اختبار.',
    'No class is assigned to you yet, so you cannot create an assessment.',
  );
  String assessmentMeta(String classroomName, String subject) =>
      '$classroomName • $subject';

  // ----------------------------------------------------------- questions
  String get questions => _('الأسئلة', 'Questions');
  String get addQuestion => _('إضافة سؤال', 'Add question');
  String get questionText => _('نص السؤال', 'Question text');
  String get maximumScore => _('الدرجة القصوى', 'Maximum score');
  String get modelAnswer => _('الإجابة النموذجية', 'Model answer');
  String get noQuestions => _('لا توجد أسئلة بعد', 'No questions yet');
  String get questionAdded => _('تمت إضافة السؤال.', 'Question added.');
  String get invalidScore =>
      _('أدخل رقمًا أكبر من صفر', 'Enter a number greater than zero');
  String questionsLabel(int count) {
    if (isArabic) {
      if (count == 0) return 'لا أسئلة';
      if (count == 1) return 'سؤال واحد';
      if (count == 2) return 'سؤالان';
      if (count <= 10) return '$count أسئلة';
      return '$count سؤالًا';
    }
    if (count == 0) return 'No questions';
    return count == 1 ? '1 question' : '$count questions';
  }

  String questionPosition(int order) => _('السؤال $order', 'Question $order');
  String maximumScoreValue(double value) =>
      _('الدرجة القصوى: ${_score(value)}', 'Max score: ${_score(value)}');
  String modelAnswerValue(String answer) =>
      _('الإجابة النموذجية: $answer', 'Model answer: $answer');
  String totalScoreValue(double value) =>
      _('مجموع الدرجات: ${_score(value)}', 'Total score: ${_score(value)}');

  /// Scores come back as decimals so half marks survive, but whole numbers
  /// should still read as `2` rather than `2.00`.
  static String _score(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  // ----------------------------------------------------------------- errors
  String get serverUnreachable =>
      _('تعذر الاتصال بالخادم.', 'Could not reach the server.');
  String get genericRequestError => _(
    'تعذر إكمال الطلب. حاول مرة أخرى.',
    'The request could not be completed. Please try again.',
  );

  /// Renders anything thrown by the gateway in the active language.
  /// [fallback] covers failures that never reached the API, such as a dead
  /// connection.
  String describeError(Object? error, {String? fallback}) {
    if (error is ApiErrorMessage) return apiError(error.message);
    return fallback ?? serverUnreachable;
  }

  /// The Django API answers in Arabic. In Arabic mode we surface its message
  /// as-is; in English mode we translate the known ones and fall back to a
  /// generic message so no Arabic leaks into an English screen.
  String apiError(String serverMessage) {
    final message = serverMessage.trim();
    if (message.isEmpty) return genericRequestError;
    if (isArabic) return message;
    final translated = _serverMessagesEn[message];
    if (translated != null) return translated;
    return _hasArabicScript(message) ? genericRequestError : message;
  }

  static const _serverMessagesEn = <String, String>{
    'بيانات الدخول غير صحيحة أو الحساب غير نشط.':
        'Incorrect credentials, or the account is inactive.',
    'رمز الطالب مستخدم داخل هذا الصف.':
        'That student code is already used in this classroom.',
    'هذه العملية متاحة لمدير المدرسة فقط.':
        'This action is available to the school manager only.',
    'هذه العملية تتطلب حسابًا نشطًا.': 'This action requires an active account.',
    'الدرجة القصوى يجب أن تكون أكبر من صفر.':
        'The maximum score must be greater than zero.',
    'ترتيب السؤال مستخدم داخل هذا الاختبار.':
        'That question order is already used in this assessment.',
    'غير موجود.': 'Not found.',
    'تعذر قراءة استجابة الخادم.': 'The server response could not be read.',
    'تعذر إكمال الطلب. حاول مرة أخرى.':
        'The request could not be completed. Please try again.',
  };

  static bool _hasArabicScript(String value) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(value);
}

extension AppTranslation on BuildContext {
  bool get isArabic => Localizations.localeOf(this).languageCode == 'ar';

  String tr({required String ar, required String en}) => isArabic ? ar : en;

  AppStrings get strings => AppStrings.of(this);
}
