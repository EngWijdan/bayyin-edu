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
  String get welcomeBack => _('مرحبًا بعودتك', 'Welcome back');
  String welcomeHello(String name) => _('أهلًا، $name', 'Welcome, $name');
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
  String get passwordTooShort => _('8 أحرف على الأقل', 'At least 8 characters');
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
  String get editClassroom => _('تعديل الصف', 'Edit classroom');
  String get saveClassroom => _('حفظ التعديلات', 'Save changes');
  String get classroomUpdated => _('تم تحديث الصف.', 'Classroom updated.');
  String get changeTeacher => _('تغيير المعلم', 'Change teacher');
  String get teacherReassigned =>
      _('تم تغيير معلم الصف.', 'Classroom teacher updated.');
  String get viewStudents => _('عرض الطلاب', 'View students');
  String get classroomActions => _('إجراءات الصف', 'Classroom actions');
  String get deleteClassroom => _('حذف الصف', 'Delete classroom');
  String get classroomDeleted => _('تم حذف الصف.', 'Classroom deleted.');
  String deleteClassroomConfirm(String name) => _(
    'سيُحذف الصف "$name" مع طلابه واختباراته. لا يمكن التراجع عن هذا الإجراء.',
    'This permanently deletes "$name" and its students and assessments. This cannot be undone.',
  );
  String classroomTitle(String name, String subject) => '$name • $subject';
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
  String get teacherClassesSubtitle =>
      _('هذه الصفوف المسندة إليك.', 'These are the classes assigned to you.');
  String get quickActions => _('إجراءات سريعة', 'Quick actions');
  String get openAssessmentsHint => _(
    'أنشئ الاختبارات وأرشفها وراجع النتائج.',
    'Create, archive, and review assessments.',
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
  String get manageAssessmentsHint => _(
    'إدارة الاختبارات وتسليمات الطلاب',
    'Manage exams and student assessments',
  );
  String get examWorkflowBanner => _(
    'ارفعي ورقة الاختبار الأصلية أولًا.\nثم أضيفي تسليمات الطلاب للتحليل.',
    'Upload the original exam first.\nThen add student submissions for analysis.',
  );
  String get currentAssessments =>
      _('الاختبارات الحالية', 'Current assessments');
  String assessmentsCountLabel(int count) {
    if (isArabic) {
      if (count == 0) return 'لا اختبارات';
      if (count == 1) return 'اختبار واحد';
      if (count == 2) return 'اختباران';
      if (count <= 10) return '$count اختبارات';
      return '$count اختبارًا';
    }
    return count == 1 ? '1 assessment' : '$count assessments';
  }

  String get assessmentsSubtitle => _(
    'أضف ورقة الاختبار الأصلية أولًا، ثم ادخل على اسم الطالب لرفع ورقته وتحليلها.',
    'Add the original exam paper first, then open a student to upload their paper and analyze it.',
  );
  String get teacherWorkflow => _('طريقة العمل', 'How it works');
  String get teacherWorkflowHint => _(
    'ورقة الاختبار الأصلية أولًا، ثم ورقة الطالب، ثم التحليل للمطابقة.',
    'Original exam paper first, then the student paper, then analyze to match them.',
  );
  String get flowExamSetup => _('إعداد الاختبار', 'Exam setup');
  String get flowStudentWork => _('عمل الطلاب', 'Student work');
  String get flowInsightsStep => _('التحليل', 'Insights');
  String get flowStepOriginalPaper => _('ورقة الاختبار', 'Exam paper');
  String get flowStepStudent => _('الطالب', 'Student');
  String get flowStepAnalyze => _('التحليل', 'Analyze');
  String flowStepNumber(int step) => _('الخطوة $step', 'Step $step');
  String get originalExamPaperTitle =>
      _('أضف ورقة الاختبار الأصلية', 'Add the original exam paper');
  String get originalExamPaperBody => _(
    'ارفع ورقة الأسئلة النموذجية حتى يعرف بيّن الأسئلة قبل مطابقة أوراق الطلاب.',
    'Upload the model question paper so Bayyin knows the questions before matching student papers.',
  );
  String get originalExamReady => _(
    'أسئلة الاختبار جاهزة للمطابقة.',
    'The exam questions are ready to match against.',
  );
  String get openStudentsTitle =>
      _('ادخل على اسم الطالب', 'Open a student by name');
  String get openStudentsBody => _(
    'بعد تجهيز ورقة الاختبار الأصلية، اختر الطالب لرفع ورقته.',
    'After the original exam paper is ready, pick the student to upload their paper.',
  );
  String get createAssessment => _('إنشاء اختبار', 'Create assessment');
  String get archivedAssessments =>
      _('الاختبارات المؤرشفة', 'Archived assessments');
  String get archiveAssessment => _('أرشفة', 'Archive');
  String get restoreAssessment => _('استعادة', 'Restore');
  String get deleteAssessment => _('حذف الاختبار', 'Delete assessment');
  String get deleteAssessmentConfirm => _(
    'سيُحذف الاختبار وكل تسليماته نهائيًا. لإعادة استخدامه لاحقًا استخدم الأرشفة.',
    'This permanently deletes the assessment and all of its submissions. Archive it if you want to reuse it later.',
  );
  String get assessmentArchived =>
      _('نُقل الاختبار إلى الأرشيف.', 'Assessment moved to the archive.');
  String get assessmentRestored =>
      _('تمت استعادة الاختبار.', 'Assessment restored.');
  String get assessmentDeleted => _('تم حذف الاختبار.', 'Assessment deleted.');
  String get noArchivedAssessments =>
      _('لا توجد اختبارات مؤرشفة', 'No archived assessments');
  String get noArchivedAssessmentsSubtitle => _(
    'أرشفي الاختبارات من القائمة لتعودي إليها في السنوات القادمة.',
    'Archive assessments from the list to reuse them in later years.',
  );
  String get swipeToArchiveOrDelete => _(
    'اسحبي البطاقة لأرشفة الاختبار أو حذفه.',
    'Swipe a card to archive or delete it.',
  );
  String get newestFirst => _('الأحدث', 'Newest');
  String get oldestFirst => _('الأقدم', 'Oldest');
  String get archivedAssessmentsSubtitle => _(
    'محفوظة لإعادة استخدامها في السنوات القادمة.',
    'Saved so you can reuse them in later years.',
  );
  String createdOn(String date) => _('أُنشئ في $date', 'Created $date');
  String get assessmentTitle => _('اسم الاختبار', 'Assessment title');
  String get assessmentTitleHint =>
      _('مثال: اختبار الكسور الأول', 'e.g. First fractions test');
  String get assessmentClassroom => _('الصف', 'Classroom');
  String get assessmentDetails => _('تفاصيل الاختبار', 'Assessment details');
  String get startHere => _('ابدأ من هنا', 'Start here');
  String get nextStep => _('الخطوة التالية', 'Next step');
  String get submissionsActionHint => _(
    'ارفع أوراق الطلاب بعد تجهيز الأسئلة.',
    'Upload student papers after the questions are ready.',
  );
  String get insightsActionHint => _(
    'راجع أداء الصف بعد اكتمال التقييم.',
    'Review class performance after evaluation is complete.',
  );
  String get optional => _('اختياري', 'Optional');
  String get uploadExamPaperHint => _(
    'ارفع ورقة الاختبار لاستخراج الأسئلة تلقائيًا.',
    'Upload the exam paper to extract questions automatically.',
  );
  String get uploadExamPaperSupport => _(
    'يمكنك مراجعة الأسئلة وتعديلها قبل اعتمادها.',
    'You can review and edit them before confirming.',
  );
  String get chooseFile => _('اختيار ملف', 'Choose file');
  String get supportedExamFormats => _('PDF · JPG · PNG', 'PDF · JPG · PNG');
  String classroomOptionDetail(String subject, String grade) =>
      '$subject · $grade';
  String get noAssessments => _('لا توجد اختبارات بعد', 'No assessments yet');
  String get noAssessmentsSubtitle => _(
    'أنشئ أول اختبار لبدء مراجعة أعمال الطلاب.',
    'Create your first assessment to start reviewing student work.',
  );
  String get assessmentCreated =>
      _('تم إنشاء الاختبار.', 'Assessment created.');
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
  String get noQuestionsHint => _(
    'ارفع ورقة الاختبار أو أضف سؤالًا يدويًا.',
    'Upload the exam paper or add a question manually.',
  );
  String get questionsMenu => _('خيارات الأسئلة', 'Question options');
  String get deleteAllQuestions =>
      _('حذف جميع الأسئلة', 'Delete all questions');
  String get showMore => _('عرض المزيد', 'Show more');
  String get showLess => _('عرض أقل', 'Show less');
  String get questionAdded => _('تمت إضافة السؤال.', 'Question added.');
  String get addQuestionsManually =>
      _('إضافة الأسئلة يدويًا', 'Add questions manually');
  String get uploadExamPaper => _('رفع ورقة الاختبار', 'Upload exam paper');
  String get extractQuestions => _('استخراج الأسئلة', 'Extract questions');
  String get extractingQuestions =>
      _('جاري استخراج الأسئلة', 'Extracting questions');
  String get uploadingExamPaper =>
      _('جاري رفع ورقة الاختبار', 'Uploading exam paper');
  String get reviewQuestions => _('مراجعة الأسئلة', 'Review questions');
  String get reviewQuestionsHint => _(
    'راجع الأسئلة المستخرجة قبل اعتمادها.',
    'Review extracted questions before confirming.',
  );
  String extractedQuestionsFound(int count) {
    if (isArabic) {
      if (count == 0) return 'لا أسئلة مستخرجة';
      if (count == 1) return 'سؤال واحد مستخرج';
      if (count == 2) return 'سؤالان مستخرجان';
      if (count <= 10) return '$count أسئلة مستخرجة';
      return '$count سؤالًا مستخرجًا';
    }
    return count == 1 ? '1 question found' : '$count questions found';
  }

  String get questionLabel => _('السؤال', 'Question');
  String get extractedQuestion => _('السؤال المستخرج', 'Extracted question');
  String get suggestedScore => _('الدرجة المقترحة', 'Suggested score');
  String get addQuestionManually =>
      _('إضافة سؤال يدويًا', 'Add question manually');
  String get removeQuestion => _('حذف السؤال', 'Remove question');
  String get deleteQuestions => _('حذف الأسئلة', 'Delete questions');
  String get deleteQuestionConfirm =>
      _('هل تريد حذف هذا السؤال؟', 'Delete this question?');
  String get deleteQuestionsConfirm => _(
    'هل تريد حذف كل الأسئلة الحالية؟ يمكنك بعدها رفع ورقة اختبار جديدة أو إضافتها يدويًا.',
    'Delete all current questions? You can then upload a new exam paper or add them manually.',
  );
  String get questionDeleted => _('تم حذف السؤال.', 'Question deleted.');
  String get questionsDeleted => _('تم حذف الأسئلة.', 'Questions deleted.');
  String get confirmQuestions => _('تأكيد الأسئلة', 'Confirm questions');
  String get noQuestionsFound =>
      _('لم يتم العثور على أسئلة', 'No questions found');
  String get couldNotExtractQuestions =>
      _('تعذر استخراج الأسئلة', 'Could not extract questions');
  String get questionsConfirmed =>
      _('تم تأكيد الأسئلة.', 'Questions confirmed.');
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

  // --------------------------------------------------------- submissions
  String get studentSubmissions => _('تسليمات الطلاب', 'Student submissions');
  String get submissionsHint => _(
    'اختر اسم الطالب لرفع ورقته ومطابقتها مع ورقة الاختبار الأصلية.',
    'Pick a student to upload their paper and match it with the original exam.',
  );
  String get submissionEntered => _('تم الإدخال', 'Entered');
  String get submissionNotEntered => _('لم يُدخل', 'Not entered');
  String get noSubmissionsYet => _('لا توجد تسليمات بعد', 'No submissions yet');
  String submissionsProgress(int entered, int total) =>
      _('تم إدخال $entered من $total', '$entered of $total entered');
  String get studentAnswer => _('إجابة الطالب', 'Student answer');
  String get saveAnswers => _('حفظ الإجابات', 'Save answers');
  String get answersSaved => _('تم الحفظ', 'Saved');
  String get noQuestionsInAssessment =>
      _('لا توجد أسئلة في هذا الاختبار', 'No questions in this assessment');

  // ------------------------------------------------------------ attachments
  String get studentPaper => _('ورقة الطالب', 'Student paper');
  String get uploadStudentPaperTitle =>
      _('ارفع ورقة الطالب', 'Upload the student paper');
  String get uploadStudentPaperBody => _(
    'هذه ورقة إجابة الطالب. التحليل يطابقها مع ورقة الاختبار الأصلية التي أضفتها في البداية.',
    'This is the student’s answer paper. Analyze matches it with the original exam paper you added first.',
  );
  String get analyzePaper => _('تحليل', 'Analyze');
  String get analyzingPaper => _('جاري التحليل…', 'Analyzing…');
  String get analyzeNeedsFile => _(
    'ارفع ورقة الطالب أولًا ثم اضغط تحليل.',
    'Upload the student paper first, then tap Analyze.',
  );
  String get addFile => _('إضافة ملف', 'Add file');
  String get uploadFile => _('رفع ملف', 'Upload file');
  String get uploading => _('جاري الرفع…', 'Uploading…');
  String get deleteFile => _('حذف الملف', 'Delete file');
  String get noFilesAttached => _('لا توجد ملفات مرفوعة', 'No files attached');
  String get unsupportedFileType =>
      _('نوع الملف غير مدعوم', 'Unsupported file type');
  String get fileTooLarge => _('حجم الملف كبير جدًا', 'File is too large');
  String get fileUploaded => _('تم رفع الملف', 'File uploaded');
  String get fileDeleted => _('تم حذف الملف', 'File deleted');
  String get deleteFileQuestion =>
      _('هل تريد حذف هذا الملف؟', 'Delete this file?');
  String get supportedFileTypes => _(
    'JPG أو PNG أو PDF، بحد أقصى 10 ميجابايت',
    'JPG, PNG or PDF, up to 10 MB',
  );

  /// Format names read the same in both languages; only the fallback for an
  /// unexpected type needs translating.
  String fileTypeLabel(String contentType) => switch (contentType) {
    'image/jpeg' => 'JPEG',
    'image/png' => 'PNG',
    'application/pdf' => 'PDF',
    _ => _('ملف', 'File'),
  };

  String fileSizeLabel(int bytes) {
    const kilobyte = 1024;
    if (bytes < kilobyte * kilobyte) {
      return _(
        '${(bytes / kilobyte).ceil()} كيلوبايت',
        '${(bytes / kilobyte).ceil()} KB',
      );
    }
    final megabytes = (bytes / (kilobyte * kilobyte)).toStringAsFixed(1);
    return _('$megabytes ميجابايت', '$megabytes MB');
  }

  // ------------------------------------------------------------------- ocr
  String get extractText => _('استخراج النص', 'Extract text');
  String get extractingText => _('جاري استخراج النص…', 'Extracting text…');
  String get extractedText => _('النص المستخرج', 'Extracted text');
  String get ocrFailed => _('تعذر استخراج النص', 'Could not extract text');
  String get retryExtraction => _('إعادة المحاولة', 'Retry');
  String get textNotExtractedYet =>
      _('لم يتم استخراج النص بعد', 'Text has not been extracted yet');
  String get viewExtractedText => _('عرض النص', 'View text');
  String get copyText => _('نسخ النص', 'Copy text');
  String get textCopied => _('تم نسخ النص', 'Text copied');
  String get noExtractedText =>
      _('لا يوجد نص في هذه الورقة', 'No text in this paper');

  // ------------------------------------------------------- ocr mapping
  String get reviewExtractedAnswers =>
      _('مراجعة الإجابات المستخرجة', 'Review extracted answers');
  String get extractAnswers => _('استخراج الإجابات', 'Extract answers');
  String get extractedAnswer => _('الإجابة المستخرجة', 'Extracted answer');
  String get noAnswerDetected =>
      _('لم يتم التعرف على إجابة', 'No answer detected');
  String get confirmAnswers => _('تأكيد الإجابات', 'Confirm answers');
  String get answersConfirmed => _('تم تأكيد الإجابات', 'Answers confirmed');
  String get someFilesNotProcessed => _(
    'بعض الملفات لم يتم استخراج النص منها بعد',
    'Some files have not been processed yet',
  );
  String get noExtractedTextAvailable => _(
    'لا يوجد نص مستخرج يمكن استخدامه بعد',
    'There is no extracted text available yet',
  );
  String get confirming => _('جاري التأكيد…', 'Confirming…');

  // ------------------------------------------------------- evaluation
  String get evaluateAnswers => _('تقييم الإجابات', 'Evaluate answers');
  String get evaluating => _('جاري التقييم', 'Evaluating');
  String get reevaluate => _('إعادة التقييم', 'Re-evaluate');
  String get aiEvaluation => _('تقييم آلي', 'AI evaluation');
  String get viewEvaluationDetails =>
      _('عرض تفاصيل التقييم', 'View evaluation details');
  String get hideEvaluationDetails =>
      _('إخفاء تفاصيل التقييم', 'Hide evaluation details');
  String get feedback => _('الملاحظات', 'Feedback');
  String get misconception => _('الفهم الخاطئ', 'Misconception');
  String get score => _('الدرجة', 'Score');
  String get couldNotEvaluateAnswer =>
      _('تعذر تقييم الإجابة', 'Could not evaluate answer');

  /// The only values the evaluation API accepts. Anything else is `ar` server-side.
  String get evaluationLocale => isArabic ? 'ar' : 'en';

  String evaluationStatus(String status) => switch (status) {
    'correct' => _('صحيح', 'Correct'),
    'partial' => _('صحيح جزئيًا', 'Partially correct'),
    'incorrect' => _('غير صحيح', 'Incorrect'),
    _ => status,
  };

  String awardedScoreValue(double awarded, double max) =>
      '$score: ${_score(awarded)} / ${_score(max)}';

  /// Deterministic empty-answer copy lives in Arabic on the server; translate
  /// it here so an English teacher does not see that raw string.
  String evaluationFeedback(String feedback) {
    if (feedback.trim() == 'لم يُدخل الطالب إجابة.') {
      return _(
        'لم يُدخل الطالب إجابة.',
        'The student did not enter an answer.',
      );
    }
    return feedback;
  }

  // ------------------------------------------------------------ results
  String get assessmentResult => _('نتيجة الاختبار', 'Assessment result');
  String get viewResultDetails =>
      _('عرض تفاصيل النتيجة', 'View result details');
  String get questionDetails => _('تفاصيل الأسئلة', 'Question details');
  String questionsEvaluated(int evaluated, int total) => _(
    '$evaluated من $total أسئلة مقيّمة',
    '$evaluated of $total questions evaluated',
  );
  String get percentage => _('النسبة', 'Percentage');
  String get unevaluated => _('غير مقيم', 'Unevaluated');
  String get gaps => _('الفجوات', 'Gaps');
  String get misconceptions => _('المفاهيم الخاطئة', 'Misconceptions');
  String get resultComplete => _('النتيجة مكتملة', 'Result complete');
  String get resultIncomplete => _('النتيجة غير مكتملة', 'Result incomplete');
  String get someQuestionsNotEvaluated => _(
    'بعض الأسئلة لم يتم تقييمها بعد',
    'Some questions have not been evaluated yet',
  );
  String get resultIncompleteWarning => _(
    'النتيجة غير مكتملة لأن بعض الأسئلة لم يتم تقييمها بعد.',
    'The result is incomplete because some questions have not been evaluated yet.',
  );
  String get resultNotEvaluable =>
      _('الاختبار غير قابل للتقييم', 'Assessment is not evaluable');
  String get resultNotEvaluableWarning => _(
    'لا يمكن إصدار نتيجة مكتملة لأن الاختبار بلا أسئلة.',
    'A complete result cannot be produced because this assessment has no questions.',
  );

  String percentageValue(double value) => '$percentage: ${_score(value)}%';

  String statusCount(String status, int count) =>
      '${evaluationStatus(status)}: $count';

  String unevaluatedCount(int count) => '$unevaluated: $count';

  // ------------------------------------------------------ class insights
  String get classInsights => _('تحليل الصف', 'Class insights');
  String get classAverage => _('متوسط الصف', 'Class average');
  String get completeResults => _('نتائج مكتملة', 'Complete results');
  String get incompleteResults => _('نتائج غير مكتملة', 'Incomplete results');
  String get noSubmission => _('بدون تسليم', 'No submission');
  String get highestGapQuestions =>
      _('أكثر الأسئلة احتياجًا', 'Highest-gap questions');
  String get gapPercentage => _('نسبة الفجوة', 'Gap percentage');
  String get commonMisconceptions =>
      _('المفاهيم الخاطئة المتكررة', 'Common misconceptions');
  String get foundationGroup => _('تأسيس', 'Foundation');
  String get practiceGroup => _('تدريب', 'Practice');
  String get readyGroup => _('جاهز', 'Ready');
  String get pendingEvaluation =>
      _('بانتظار اكتمال التقييم', 'Pending evaluation');
  String get noCompleteResultsYet =>
      _('لا توجد نتائج مكتملة بعد', 'No complete results yet');
  String get noMisconceptions =>
      _('لا توجد مفاهيم خاطئة مسجّلة', 'No misconceptions recorded');
  String get incompleteEvaluationReason =>
      _('تقييم غير مكتمل', 'Incomplete evaluation');
  String get noQuestionsReason =>
      _('الاختبار بلا أسئلة', 'Assessment has no questions');

  String classAverageValue(double value) => '$classAverage: ${_score(value)}%';
  String completeResultsCount(int count) => '$completeResults: $count';
  String incompleteResultsCount(int count) => '$incompleteResults: $count';
  String noSubmissionCount(int count) => '$noSubmission: $count';
  String misconceptionOccurrences(int count) => _('×$count', '×$count');
  String studentPercentage(double value) => '${_score(value)}%';

  String pendingReason(String reason) {
    if (reason == 'incomplete evaluation') return incompleteEvaluationReason;
    if (reason == 'no questions') return noQuestionsReason;
    return reason;
  }

  String questionGapHeadline(int order, double? percent) {
    if (percent == null) return questionPosition(order);
    return _(
      'السؤال $order — فجوة ${_score(percent)}%',
      'Question $order — ${_score(percent)}% gap',
    );
  }

  String gapStatusCounts({
    required int correct,
    required int partial,
    required int incorrect,
  }) =>
      '${statusCount('correct', correct)}  •  '
      '${statusCount('partial', partial)}  •  '
      '${statusCount('incorrect', incorrect)}';

  // --------------------------------------------------- remediation plans
  String get remediationPlan => _('الخطة العلاجية', 'Remediation plan');
  String get generatePlan => _('إنشاء خطة', 'Generate plan');
  String get regeneratePlan => _('إعادة التوليد', 'Regenerate');
  String get viewPlan => _('عرض الخطة', 'View plan');
  String get objectives => _('الأهداف', 'Objectives');
  String get activities => _('الأنشطة', 'Activities');
  String get teacherGuidance => _('إرشادات المعلم', 'Teacher guidance');
  String get generatingPlan => _('جاري إنشاء الخطة', 'Generating plan');
  String get couldNotGeneratePlan =>
      _('تعذر إنشاء الخطة', 'Could not generate plan');
  String get noStudentsInGroup =>
      _('لا يوجد طلاب في هذه المجموعة', 'No students in this group');
  String get aiGeneratedPlan =>
      _('خطة مولدة بالذكاء الاصطناعي', 'AI-generated plan');

  String activityDuration(int minutes) =>
      _('$minutes دقيقة', '$minutes minutes');

  String groupTitle(String group) => switch (group) {
    'foundation' => foundationGroup,
    'practice' => practiceGroup,
    'ready' => readyGroup,
    _ => group,
  };

  // --------------------------------------------------- manager insights
  String get schoolInsights => _('تحليلات المدرسة', 'School insights');
  String get overview => _('نظرة عامة', 'Overview');
  String get teachers => _('المعلمون', 'Teachers');
  String get classrooms => _('الصفوف', 'Classrooms');
  String get averagePerformance => _('متوسط الأداء', 'Average performance');
  String get highestGaps => _('أبرز الفجوات', 'Highest gaps');
  String get notEnoughDataYet =>
      _('لا توجد بيانات كافية بعد', 'Not enough data yet');

  String averagePerformanceValue(double value) =>
      '$averagePerformance: ${_score(value)}%';
  String countWithLabel(String label, int count) => '$label: $count';

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
    if (_isSessionExpired(message)) {
      return _(
        'انتهت الجلسة. سجّل الدخول مرة أخرى.',
        'Your session has ended. Please sign in again.',
      );
    }
    if (isArabic) return message;
    final translated = _serverMessagesEn[message];
    if (translated != null) return translated;
    return _hasArabicScript(message) ? genericRequestError : message;
  }

  static bool _isSessionExpired(String message) =>
      message == 'Invalid token.' ||
      message == 'Authentication credentials were not provided.';

  static const _serverMessagesEn = <String, String>{
    'بيانات الدخول غير صحيحة أو الحساب غير نشط.':
        'Incorrect credentials, or the account is inactive.',
    'رمز الطالب مستخدم داخل هذا الصف.':
        'That student code is already used in this classroom.',
    'هذه العملية متاحة لمدير المدرسة فقط.':
        'This action is available to the school manager only.',
    'هذه العملية تتطلب حسابًا نشطًا.':
        'This action requires an active account.',
    'الدرجة القصوى يجب أن تكون أكبر من صفر.':
        'The maximum score must be greater than zero.',
    'ترتيب السؤال مستخدم داخل هذا الاختبار.':
        'That question order is already used in this assessment.',
    'لهذا الطالب تسليم مسجل في هذا الاختبار.':
        'This student already has a submission for this assessment.',
    'السؤال لا ينتمي إلى هذا الاختبار.':
        'That question does not belong to this assessment.',
    'لا يمكن إرسال إجابتين لنفس السؤال.':
        'Two answers cannot be sent for the same question.',
    'الطالب لا ينتمي إلى صف هذا الاختبار.':
        'That student does not belong to this assessment\'s classroom.',
    'نوع الملف غير مدعوم.': 'Unsupported file type.',
    'حجم الملف كبير جدًا.': 'File is too large.',
    'تعذر استخراج الأسئلة.': 'Could not extract questions.',
    'ارفع ورقة الاختبار أولًا.': 'Upload the exam paper first.',
    'نص السؤال مطلوب.': 'Question text is required.',
    'لا يوجد نص مستخرج يمكن استخدامه بعد.':
        'There is no extracted text available yet.',
    'تعذر تقييم الإجابة.': 'Could not evaluate answer.',
    'تعذر إنشاء الخطة.': 'Could not generate plan.',
    'المجموعة غير صالحة.': 'That group is not valid.',
    'لا توجد إجابات مؤكدة للتقييم.':
        'There are no confirmed answers to evaluate.',
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
