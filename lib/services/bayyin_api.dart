import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../l10n/app_language.dart';

const defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

/// Picks the name to show: whatever the backend resolved, then the full name,
/// then the username as a last resort. Never a literal.
String _resolveDisplayName({
  required String serverDisplayName,
  required String fullName,
  required String username,
}) {
  for (final candidate in [serverDisplayName, fullName, username]) {
    if (candidate.trim().isNotEmpty) return candidate.trim();
  }
  return username;
}

class UserSession {
  const UserSession({
    required this.token,
    required this.username,
    required this.fullName,
    required this.role,
    this.serverDisplayName = '',
  });

  final String token;
  final String username;
  final String fullName;
  final String role;

  /// `display_name` as resolved by Django, empty when the backend omits it.
  final String serverDisplayName;

  bool get isManager => role == 'MANAGER';

  String get displayName => _resolveDisplayName(
    serverDisplayName: serverDisplayName,
    fullName: fullName,
    username: username,
  );
}

class TeacherAccount {
  const TeacherAccount({
    required this.id,
    required this.profileId,
    required this.username,
    required this.fullName,
    required this.email,
    required this.isActive,
    this.serverDisplayName = '',
  });

  factory TeacherAccount.fromJson(Map<String, dynamic> json) => TeacherAccount(
    id: json['id'].toString(),
    profileId: json['profile_id'].toString(),
    username: json['username'] as String,
    fullName: json['full_name'] as String? ?? '',
    serverDisplayName: json['display_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    isActive: json['is_active'] as bool? ?? true,
  );

  final String id;
  final String profileId;
  final String username;
  final String fullName;
  final String serverDisplayName;
  final String email;
  final bool isActive;

  String get displayName => _resolveDisplayName(
    serverDisplayName: serverDisplayName,
    fullName: fullName,
    username: username,
  );
}

class ClassroomRecord {
  const ClassroomRecord({
    required this.id,
    required this.name,
    required this.grade,
    required this.subject,
    required this.academicYear,
    required this.teacherName,
    required this.studentsCount,
    this.teacherProfileId = '',
    this.assessmentsCount = 0,
  });

  factory ClassroomRecord.fromJson(Map<String, dynamic> json) =>
      ClassroomRecord(
        id: json['id'].toString(),
        name: json['name'] as String,
        grade: json['grade'] as String,
        subject: json['subject'] as String,
        academicYear: json['academic_year'] as String,
        teacherName: json['teacher_name'] as String,
        teacherProfileId: json['teacher_profile_id']?.toString() ?? '',
        studentsCount: json['students_count'] as int? ?? 0,
        assessmentsCount: json['assessments_count'] as int? ?? 0,
      );

  final String id;
  final String name;
  final String grade;
  final String subject;
  final String academicYear;
  final String teacherName;
  final String teacherProfileId;
  final int studentsCount;
  final int assessmentsCount;

  ClassroomRecord copyWith({
    String? name,
    String? grade,
    String? subject,
    String? academicYear,
    String? teacherName,
    String? teacherProfileId,
    int? studentsCount,
    int? assessmentsCount,
  }) => ClassroomRecord(
    id: id,
    name: name ?? this.name,
    grade: grade ?? this.grade,
    subject: subject ?? this.subject,
    academicYear: academicYear ?? this.academicYear,
    teacherName: teacherName ?? this.teacherName,
    teacherProfileId: teacherProfileId ?? this.teacherProfileId,
    studentsCount: studentsCount ?? this.studentsCount,
    assessmentsCount: assessmentsCount ?? this.assessmentsCount,
  );
}

class StudentRecord {
  const StudentRecord({
    required this.id,
    required this.internalCode,
    required this.displayName,
  });

  factory StudentRecord.fromJson(Map<String, dynamic> json) => StudentRecord(
    id: json['id'].toString(),
    internalCode: json['internal_code'] as String,
    displayName: json['display_name'] as String? ?? '',
  );

  final String id;
  final String internalCode;
  final String displayName;

  bool get hasName => displayName.trim().isNotEmpty;
}

class QuestionRecord {
  const QuestionRecord({
    required this.id,
    required this.order,
    required this.text,
    required this.maxScore,
    required this.modelAnswer,
  });

  factory QuestionRecord.fromJson(Map<String, dynamic> json) => QuestionRecord(
    id: json['id'].toString(),
    order: json['order'] as int? ?? 0,
    text: json['text'] as String? ?? '',
    maxScore: (json['max_score'] as num?)?.toDouble() ?? 0,
    modelAnswer: json['model_answer'] as String? ?? '',
  );

  final String id;
  final int order;
  final String text;
  final double maxScore;
  final String modelAnswer;
}

class QuestionCandidateRecord {
  const QuestionCandidateRecord({
    required this.id,
    required this.order,
    required this.extractedText,
    this.proposedMaxScore,
    this.proposedModelAnswer = '',
    this.status = 'suggested',
  });

  factory QuestionCandidateRecord.fromJson(Map<String, dynamic> json) =>
      QuestionCandidateRecord(
        id: json['id']?.toString() ?? '',
        order: json['order'] as int? ?? 0,
        extractedText: json['extracted_text'] as String? ?? '',
        proposedMaxScore: (json['proposed_max_score'] as num?)?.toDouble(),
        proposedModelAnswer: json['proposed_model_answer'] as String? ?? '',
        status: json['status'] as String? ?? 'suggested',
      );

  final String id;
  final int order;
  final String extractedText;
  final double? proposedMaxScore;
  final String proposedModelAnswer;
  final String status;
}

/// One assessment. The list endpoint omits [questions]; the detail endpoint
/// fills it in, which is why it defaults to empty rather than being required.
class AssessmentRecord {
  const AssessmentRecord({
    required this.id,
    required this.title,
    required this.classroomId,
    required this.classroomName,
    required this.grade,
    required this.subject,
    required this.questionsCount,
    required this.totalScore,
    this.questions = const [],
    this.createdAt,
    this.archivedAt,
  });

  factory AssessmentRecord.fromJson(Map<String, dynamic> json) =>
      AssessmentRecord(
        id: json['id'].toString(),
        title: json['title'] as String? ?? '',
        classroomId: json['classroom_id'].toString(),
        classroomName: json['classroom_name'] as String? ?? '',
        grade: json['grade'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        questionsCount: json['questions_count'] as int? ?? 0,
        totalScore: (json['total_score'] as num?)?.toDouble() ?? 0,
        questions: ((json['questions'] as List<dynamic>?) ?? [])
            .map(
              (item) => QuestionRecord.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        createdAt: _parseDateTime(json['created_at']),
        archivedAt: _parseDateTime(json['archived_at']),
      );

  final String id;
  final String title;
  final String classroomId;
  final String classroomName;
  final String grade;
  final String subject;
  final int questionsCount;
  final double totalScore;
  final List<QuestionRecord> questions;
  final DateTime? createdAt;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  AssessmentRecord copyWith({
    String? title,
    int? questionsCount,
    double? totalScore,
    List<QuestionRecord>? questions,
    DateTime? createdAt,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) => AssessmentRecord(
    id: id,
    title: title ?? this.title,
    classroomId: classroomId,
    classroomName: classroomName,
    grade: grade,
    subject: subject,
    questionsCount: questionsCount ?? this.questionsCount,
    totalScore: totalScore ?? this.totalScore,
    questions: questions ?? this.questions,
    createdAt: createdAt ?? this.createdAt,
    archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
  );
}

DateTime? _parseDateTime(dynamic value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value);
}

/// One question of the assessment paired with what the student answered.
/// The backend returns an entry for every question, so [answerText] is empty
/// rather than absent when nothing has been entered yet.
class AnswerRecord {
  const AnswerRecord({
    this.id,
    required this.questionId,
    required this.order,
    required this.text,
    required this.maxScore,
    required this.answerText,
    this.evaluation,
  });

  factory AnswerRecord.fromJson(Map<String, dynamic> json) => AnswerRecord(
    id: json['id']?.toString(),
    questionId: json['question_id'].toString(),
    order: json['order'] as int? ?? 0,
    text: json['text'] as String? ?? '',
    maxScore: (json['max_score'] as num?)?.toDouble() ?? 0,
    answerText: json['answer_text'] as String? ?? '',
    evaluation: json['evaluation'] is Map<String, dynamic>
        ? EvaluationRecord.fromJson(json['evaluation'] as Map<String, dynamic>)
        : null,
  );

  /// Null until the teacher has saved a [SubmissionAnswer] for this question.
  final String? id;
  final String questionId;
  final int order;
  final String text;
  final double maxScore;
  final String answerText;
  final EvaluationRecord? evaluation;

  bool get isConfirmed => id != null && id!.isNotEmpty;

  AnswerRecord copyWith({
    String? id,
    String? answerText,
    EvaluationRecord? evaluation,
    bool clearEvaluation = false,
  }) => AnswerRecord(
    id: id ?? this.id,
    questionId: questionId,
    order: order,
    text: text,
    maxScore: maxScore,
    answerText: answerText ?? this.answerText,
    evaluation: clearEvaluation ? null : (evaluation ?? this.evaluation),
  );
}

/// The current AI grade for one confirmed student answer.
class EvaluationRecord {
  const EvaluationRecord({
    required this.status,
    required this.awardedScore,
    required this.feedback,
    this.misconception = '',
  });

  factory EvaluationRecord.fromJson(Map<String, dynamic> json) =>
      EvaluationRecord(
        status: json['status'] as String? ?? '',
        awardedScore: (json['awarded_score'] as num?)?.toDouble() ?? 0,
        feedback: json['feedback'] as String? ?? '',
        misconception: json['misconception'] as String? ?? '',
      );

  final String status;
  final double awardedScore;
  final String feedback;
  final String misconception;

  bool get hasMisconception => misconception.trim().isNotEmpty;
}

class GapRecord {
  const GapRecord({
    required this.questionId,
    required this.questionOrder,
    required this.questionText,
    required this.status,
    required this.awardedScore,
    required this.maxScore,
    required this.feedback,
    this.misconception = '',
  });

  factory GapRecord.fromJson(Map<String, dynamic> json) => GapRecord(
    questionId: json['question_id'].toString(),
    questionOrder: json['question_order'] as int? ?? 0,
    questionText: json['question_text'] as String? ?? '',
    status: json['status'] as String? ?? '',
    awardedScore: (json['awarded_score'] as num?)?.toDouble() ?? 0,
    maxScore: (json['max_score'] as num?)?.toDouble() ?? 0,
    feedback: json['feedback'] as String? ?? '',
    misconception: json['misconception'] as String? ?? '',
  );

  final String questionId;
  final int questionOrder;
  final String questionText;
  final String status;
  final double awardedScore;
  final double maxScore;
  final String feedback;
  final String misconception;

  bool get hasMisconception => misconception.trim().isNotEmpty;
}

class SubmissionResultRecord {
  const SubmissionResultRecord({
    required this.isComplete,
    required this.awardedScoreTotal,
    required this.maxScoreTotal,
    required this.percentage,
    required this.evaluatedQuestions,
    required this.totalQuestions,
    required this.correctCount,
    required this.partialCount,
    required this.incorrectCount,
    required this.unevaluatedCount,
    this.isEvaluable,
    this.gaps = const [],
    this.misconceptions = const [],
  });

  factory SubmissionResultRecord.fromJson(Map<String, dynamic> json) {
    final totalQuestions = json['total_questions'] as int? ?? 0;
    return SubmissionResultRecord(
      isEvaluable: json['is_evaluable'] as bool? ?? totalQuestions > 0,
      isComplete: json['is_complete'] as bool? ?? false,
      awardedScoreTotal: (json['awarded_score_total'] as num?)?.toDouble() ?? 0,
      maxScoreTotal: (json['max_score_total'] as num?)?.toDouble() ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
      evaluatedQuestions: json['evaluated_questions'] as int? ?? 0,
      totalQuestions: totalQuestions,
      correctCount: json['correct_count'] as int? ?? 0,
      partialCount: json['partial_count'] as int? ?? 0,
      incorrectCount: json['incorrect_count'] as int? ?? 0,
      unevaluatedCount: json['unevaluated_count'] as int? ?? 0,
      gaps: ((json['gaps'] as List<dynamic>?) ?? [])
          .map((item) => GapRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      misconceptions: ((json['misconceptions'] as List<dynamic>?) ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  final bool? isEvaluable;
  final bool isComplete;
  final double awardedScoreTotal;
  final double maxScoreTotal;
  final double percentage;
  final int evaluatedQuestions;
  final int totalQuestions;
  final int correctCount;
  final int partialCount;
  final int incorrectCount;
  final int unevaluatedCount;
  final List<GapRecord> gaps;
  final List<String> misconceptions;

  bool get canEvaluate => isEvaluable ?? totalQuestions > 0;
}

class ClassInsightsSummary {
  const ClassInsightsSummary({
    required this.totalStudentsInClass,
    required this.studentsWithSubmission,
    required this.studentsWithoutSubmission,
    required this.completeResults,
    required this.incompleteResults,
    this.averagePercentage,
  });

  factory ClassInsightsSummary.fromJson(Map<String, dynamic> json) =>
      ClassInsightsSummary(
        totalStudentsInClass: json['total_students_in_class'] as int? ?? 0,
        studentsWithSubmission: json['students_with_submission'] as int? ?? 0,
        studentsWithoutSubmission:
            json['students_without_submission'] as int? ?? 0,
        completeResults: json['complete_results'] as int? ?? 0,
        incompleteResults: json['incomplete_results'] as int? ?? 0,
        averagePercentage: (json['average_percentage'] as num?)?.toDouble(),
      );

  final int totalStudentsInClass;
  final int studentsWithSubmission;
  final int studentsWithoutSubmission;
  final int completeResults;
  final int incompleteResults;
  final double? averagePercentage;
}

class ClassQuestionGapRecord {
  const ClassQuestionGapRecord({
    required this.questionId,
    required this.questionOrder,
    required this.questionText,
    required this.maxScore,
    required this.evaluatedStudents,
    required this.correctCount,
    required this.partialCount,
    required this.incorrectCount,
    required this.gapCount,
    this.gapPercentage,
  });

  factory ClassQuestionGapRecord.fromJson(Map<String, dynamic> json) =>
      ClassQuestionGapRecord(
        questionId: json['question_id'].toString(),
        questionOrder: json['question_order'] as int? ?? 0,
        questionText: json['question_text'] as String? ?? '',
        maxScore: (json['max_score'] as num?)?.toDouble() ?? 0,
        evaluatedStudents: json['evaluated_students'] as int? ?? 0,
        correctCount: json['correct_count'] as int? ?? 0,
        partialCount: json['partial_count'] as int? ?? 0,
        incorrectCount: json['incorrect_count'] as int? ?? 0,
        gapCount: json['gap_count'] as int? ?? 0,
        gapPercentage: (json['gap_percentage'] as num?)?.toDouble(),
      );

  final String questionId;
  final int questionOrder;
  final String questionText;
  final double maxScore;
  final int evaluatedStudents;
  final int correctCount;
  final int partialCount;
  final int incorrectCount;
  final int gapCount;
  final double? gapPercentage;
}

class MisconceptionCountRecord {
  const MisconceptionCountRecord({required this.text, required this.count});

  factory MisconceptionCountRecord.fromJson(Map<String, dynamic> json) =>
      MisconceptionCountRecord(
        text: json['text'] as String? ?? '',
        count: json['count'] as int? ?? 0,
      );

  final String text;
  final int count;
}

class GroupedStudentRecord {
  const GroupedStudentRecord({
    required this.studentId,
    required this.displayName,
    required this.studentCode,
    required this.percentage,
    required this.group,
  });

  factory GroupedStudentRecord.fromJson(Map<String, dynamic> json) =>
      GroupedStudentRecord(
        studentId: json['student_id'].toString(),
        displayName: json['display_name'] as String? ?? '',
        studentCode: json['student_code'] as String? ?? '',
        percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
        group: json['group'] as String? ?? '',
      );

  final String studentId;
  final String displayName;
  final String studentCode;
  final double percentage;
  final String group;

  bool get hasName => displayName.trim().isNotEmpty;
}

class PendingStudentRecord {
  const PendingStudentRecord({
    required this.studentId,
    required this.displayName,
    required this.studentCode,
    required this.reason,
  });

  factory PendingStudentRecord.fromJson(Map<String, dynamic> json) =>
      PendingStudentRecord(
        studentId: json['student_id'].toString(),
        displayName: json['display_name'] as String? ?? '',
        studentCode: json['student_code'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
      );

  final String studentId;
  final String displayName;
  final String studentCode;
  final String reason;

  bool get hasName => displayName.trim().isNotEmpty;
}

class ClassInsightsRecord {
  const ClassInsightsRecord({
    required this.summary,
    this.questionGaps = const [],
    this.misconceptions = const [],
    this.foundation = const [],
    this.practice = const [],
    this.ready = const [],
    this.pendingStudents = const [],
  });

  factory ClassInsightsRecord.fromJson(Map<String, dynamic> json) {
    final groups = json['groups'] as Map<String, dynamic>? ?? const {};
    return ClassInsightsRecord(
      summary: ClassInsightsSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      questionGaps: ((json['question_gaps'] as List<dynamic>?) ?? [])
          .map(
            (item) =>
                ClassQuestionGapRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      misconceptions: ((json['misconceptions'] as List<dynamic>?) ?? [])
          .map(
            (item) =>
                MisconceptionCountRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      foundation: _grouped(groups['foundation']),
      practice: _grouped(groups['practice']),
      ready: _grouped(groups['ready']),
      pendingStudents: ((json['pending_students'] as List<dynamic>?) ?? [])
          .map(
            (item) =>
                PendingStudentRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  static List<GroupedStudentRecord> _grouped(dynamic value) =>
      ((value as List<dynamic>?) ?? [])
          .map(
            (item) =>
                GroupedStudentRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList();

  final ClassInsightsSummary summary;
  final List<ClassQuestionGapRecord> questionGaps;
  final List<MisconceptionCountRecord> misconceptions;
  final List<GroupedStudentRecord> foundation;
  final List<GroupedStudentRecord> practice;
  final List<GroupedStudentRecord> ready;
  final List<PendingStudentRecord> pendingStudents;
}

class RemediationActivityRecord {
  const RemediationActivityRecord({
    required this.title,
    required this.description,
    this.durationMinutes,
  });

  factory RemediationActivityRecord.fromJson(Map<String, dynamic> json) =>
      RemediationActivityRecord(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        durationMinutes: json['duration_minutes'] as int?,
      );

  final String title;
  final String description;
  final int? durationMinutes;
}

class RemediationPlanRecord {
  const RemediationPlanRecord({
    required this.id,
    required this.group,
    required this.status,
    required this.title,
    required this.summary,
    required this.teacherGuidance,
    this.objectives = const [],
    this.activities = const [],
    this.modelName = '',
    this.generatedAt = '',
  });

  factory RemediationPlanRecord.fromJson(Map<String, dynamic> json) =>
      RemediationPlanRecord(
        id: json['id'].toString(),
        group: json['group'] as String? ?? '',
        status: json['status'] as String? ?? '',
        title: json['title'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        teacherGuidance: json['teacher_guidance'] as String? ?? '',
        objectives: ((json['objectives'] as List<dynamic>?) ?? [])
            .map((item) => item.toString())
            .toList(),
        activities: ((json['activities'] as List<dynamic>?) ?? [])
            .map(
              (item) => RemediationActivityRecord.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
        modelName: json['model_name'] as String? ?? '',
        generatedAt: json['generated_at']?.toString() ?? '',
      );

  final String id;
  final String group;
  final String status;
  final String title;
  final String summary;
  final String teacherGuidance;
  final List<String> objectives;
  final List<RemediationActivityRecord> activities;
  final String modelName;
  final String generatedAt;
}

class RemediationGenerateRecord {
  const RemediationGenerateRecord({
    required this.groupEmpty,
    required this.group,
    this.plan,
  });

  factory RemediationGenerateRecord.fromJson(Map<String, dynamic> json) =>
      RemediationGenerateRecord(
        groupEmpty: json['group_empty'] as bool? ?? false,
        group: json['group'] as String? ?? '',
        plan: json['plan'] is Map<String, dynamic>
            ? RemediationPlanRecord.fromJson(
                json['plan'] as Map<String, dynamic>,
              )
            : null,
      );

  final bool groupEmpty;
  final String group;
  final RemediationPlanRecord? plan;
}

class ManagerInsightsSummary {
  const ManagerInsightsSummary({
    required this.totalTeachers,
    required this.totalClassrooms,
    required this.totalStudents,
    required this.totalAssessments,
    required this.assessmentsWithCompleteResults,
    required this.assessmentsWithIncompleteResults,
    this.overallAveragePercentage,
  });

  factory ManagerInsightsSummary.fromJson(Map<String, dynamic> json) =>
      ManagerInsightsSummary(
        totalTeachers: json['total_teachers'] as int? ?? 0,
        totalClassrooms: json['total_classrooms'] as int? ?? 0,
        totalStudents: json['total_students'] as int? ?? 0,
        totalAssessments: json['total_assessments'] as int? ?? 0,
        assessmentsWithCompleteResults:
            json['assessments_with_complete_results'] as int? ?? 0,
        assessmentsWithIncompleteResults:
            json['assessments_with_incomplete_results'] as int? ?? 0,
        overallAveragePercentage: (json['overall_average_percentage'] as num?)
            ?.toDouble(),
      );

  final int totalTeachers;
  final int totalClassrooms;
  final int totalStudents;
  final int totalAssessments;
  final int assessmentsWithCompleteResults;
  final int assessmentsWithIncompleteResults;
  final double? overallAveragePercentage;
}

class ManagerClassroomInsight {
  const ManagerClassroomInsight({
    required this.classroomId,
    required this.classroomName,
    required this.grade,
    required this.subject,
    required this.teacherName,
    required this.studentCount,
    required this.assessmentCount,
    required this.completedResultsCount,
    required this.incompleteResultsCount,
    this.averagePercentage,
  });

  factory ManagerClassroomInsight.fromJson(Map<String, dynamic> json) =>
      ManagerClassroomInsight(
        classroomId: json['classroom_id'].toString(),
        classroomName: json['classroom_name'] as String? ?? '',
        grade: json['grade'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        teacherName: json['teacher_name'] as String? ?? '',
        studentCount: json['student_count'] as int? ?? 0,
        assessmentCount: json['assessment_count'] as int? ?? 0,
        completedResultsCount: json['completed_results_count'] as int? ?? 0,
        incompleteResultsCount: json['incomplete_results_count'] as int? ?? 0,
        averagePercentage: (json['average_percentage'] as num?)?.toDouble(),
      );

  final String classroomId;
  final String classroomName;
  final String grade;
  final String subject;
  final String teacherName;
  final int studentCount;
  final int assessmentCount;
  final int completedResultsCount;
  final int incompleteResultsCount;
  final double? averagePercentage;
}

class ManagerTeacherInsight {
  const ManagerTeacherInsight({
    required this.teacherId,
    required this.displayName,
    required this.classroomsCount,
    required this.studentsCount,
    required this.assessmentsCount,
    required this.completeResultsCount,
    required this.incompleteResultsCount,
    this.averagePercentage,
  });

  factory ManagerTeacherInsight.fromJson(Map<String, dynamic> json) =>
      ManagerTeacherInsight(
        teacherId: json['teacher_id'].toString(),
        displayName: json['display_name'] as String? ?? '',
        classroomsCount: json['classrooms_count'] as int? ?? 0,
        studentsCount: json['students_count'] as int? ?? 0,
        assessmentsCount: json['assessments_count'] as int? ?? 0,
        completeResultsCount: json['complete_results_count'] as int? ?? 0,
        incompleteResultsCount: json['incomplete_results_count'] as int? ?? 0,
        averagePercentage: (json['average_percentage'] as num?)?.toDouble(),
      );

  final String teacherId;
  final String displayName;
  final int classroomsCount;
  final int studentsCount;
  final int assessmentsCount;
  final int completeResultsCount;
  final int incompleteResultsCount;
  final double? averagePercentage;
}

class ManagerAssessmentInsight {
  const ManagerAssessmentInsight({
    required this.assessmentId,
    required this.title,
    required this.classroom,
    required this.teacher,
    required this.studentsWithSubmission,
    required this.completeResults,
    required this.incompleteResults,
    this.averagePercentage,
  });

  factory ManagerAssessmentInsight.fromJson(Map<String, dynamic> json) =>
      ManagerAssessmentInsight(
        assessmentId: json['assessment_id'].toString(),
        title: json['title'] as String? ?? '',
        classroom: json['classroom'] as String? ?? '',
        teacher: json['teacher'] as String? ?? '',
        studentsWithSubmission: json['students_with_submission'] as int? ?? 0,
        completeResults: json['complete_results'] as int? ?? 0,
        incompleteResults: json['incomplete_results'] as int? ?? 0,
        averagePercentage: (json['average_percentage'] as num?)?.toDouble(),
      );

  final String assessmentId;
  final String title;
  final String classroom;
  final String teacher;
  final int studentsWithSubmission;
  final int completeResults;
  final int incompleteResults;
  final double? averagePercentage;
}

class ManagerGapInsight {
  const ManagerGapInsight({
    required this.assessmentTitle,
    required this.classroom,
    required this.questionOrder,
    required this.questionText,
    required this.evaluatedStudents,
    required this.gapCount,
    this.gapPercentage,
  });

  factory ManagerGapInsight.fromJson(Map<String, dynamic> json) =>
      ManagerGapInsight(
        assessmentTitle: json['assessment_title'] as String? ?? '',
        classroom: json['classroom'] as String? ?? '',
        questionOrder: json['question_order'] as int? ?? 0,
        questionText: json['question_text'] as String? ?? '',
        evaluatedStudents: json['evaluated_students'] as int? ?? 0,
        gapCount: json['gap_count'] as int? ?? 0,
        gapPercentage: (json['gap_percentage'] as num?)?.toDouble(),
      );

  final String assessmentTitle;
  final String classroom;
  final int questionOrder;
  final String questionText;
  final int evaluatedStudents;
  final int gapCount;
  final double? gapPercentage;
}

class ManagerInsightsRecord {
  const ManagerInsightsRecord({
    required this.summary,
    this.classrooms = const [],
    this.teachers = const [],
    this.assessments = const [],
    this.highestGapQuestions = const [],
    this.misconceptions = const [],
  });

  factory ManagerInsightsRecord.fromJson(
    Map<String, dynamic> json,
  ) => ManagerInsightsRecord(
    summary: ManagerInsightsSummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    ),
    classrooms: ((json['classrooms'] as List<dynamic>?) ?? [])
        .map(
          (item) =>
              ManagerClassroomInsight.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    teachers: ((json['teachers'] as List<dynamic>?) ?? [])
        .map(
          (item) =>
              ManagerTeacherInsight.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    assessments: ((json['assessments'] as List<dynamic>?) ?? [])
        .map(
          (item) =>
              ManagerAssessmentInsight.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    highestGapQuestions:
        ((json['highest_gap_questions'] as List<dynamic>?) ?? [])
            .map(
              (item) =>
                  ManagerGapInsight.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
    misconceptions: ((json['misconceptions'] as List<dynamic>?) ?? [])
        .map(
          (item) =>
              MisconceptionCountRecord.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
  );

  final ManagerInsightsSummary summary;
  final List<ManagerClassroomInsight> classrooms;
  final List<ManagerTeacherInsight> teachers;
  final List<ManagerAssessmentInsight> assessments;
  final List<ManagerGapInsight> highestGapQuestions;
  final List<MisconceptionCountRecord> misconceptions;
}

/// A student's submission. The list endpoint omits [assessmentTitle] and
/// [answers]; the detail and save endpoints fill them in.
class SubmissionRecord {
  const SubmissionRecord({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.studentCode,
    this.assessmentTitle = '',
    this.answers = const [],
    this.failedCount = 0,
  });

  factory SubmissionRecord.fromJson(Map<String, dynamic> json) =>
      SubmissionRecord(
        id: json['id'].toString(),
        studentId: json['student_id'].toString(),
        studentName: json['student_name'] as String? ?? '',
        studentCode: json['student_code'] as String? ?? '',
        assessmentTitle: json['assessment_title'] as String? ?? '',
        answers: ((json['answers'] as List<dynamic>?) ?? [])
            .map((item) => AnswerRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        failedCount: json['failed_count'] as int? ?? 0,
      );

  final String id;
  final String studentId;
  final String studentName;
  final String studentCode;
  final String assessmentTitle;
  final List<AnswerRecord> answers;

  /// Present on bulk evaluate responses. Zero on ordinary submission reads.
  final int failedCount;

  bool get hasName => studentName.trim().isNotEmpty;
}

/// A page of the student's paper stored on the server. The bytes stay on the
/// server; the app only ever handles this metadata.
class AttachmentRecord {
  const AttachmentRecord({
    required this.id,
    required this.filename,
    required this.contentType,
    required this.fileSize,
  });

  factory AttachmentRecord.fromJson(Map<String, dynamic> json) =>
      AttachmentRecord(
        id: json['id'].toString(),
        filename: json['original_filename'] as String? ?? '',
        contentType: json['content_type'] as String? ?? '',
        fileSize: json['file_size'] as int? ?? 0,
      );

  final String id;
  final String filename;
  final String contentType;
  final int fileSize;
}

/// One OCR pass on one attachment. Independent of every other page.
class OcrRecord {
  const OcrRecord({
    required this.id,
    required this.status,
    required this.extractedText,
  });

  factory OcrRecord.fromJson(Map<String, dynamic> json) => OcrRecord(
    id: json['id'].toString(),
    status: json['status'] as String? ?? '',
    extractedText: json['extracted_text'] as String? ?? '',
  );

  final String id;
  final String status;
  final String extractedText;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isProcessing => status == 'processing' || status == 'pending';
}

/// One suggested answer produced from OCR, plus whatever the teacher already
/// typed. The TextField prefers [currentAnswer] so a manual entry is not lost.
class OcrCandidateRecord {
  const OcrCandidateRecord({
    required this.id,
    required this.questionId,
    required this.order,
    required this.questionText,
    required this.maxScore,
    required this.extractedText,
    required this.status,
    required this.currentAnswer,
  });

  factory OcrCandidateRecord.fromJson(Map<String, dynamic> json) =>
      OcrCandidateRecord(
        id: json['id'].toString(),
        questionId: json['question_id'].toString(),
        order: json['order'] as int? ?? 0,
        questionText: json['question_text'] as String? ?? '',
        maxScore: (json['max_score'] as num?)?.toDouble() ?? 0,
        extractedText: json['extracted_text'] as String? ?? '',
        status: json['status'] as String? ?? '',
        currentAnswer: json['current_answer'] as String? ?? '',
      );

  final String id;
  final String questionId;
  final int order;
  final String questionText;
  final double maxScore;
  final String extractedText;
  final String status;
  final String currentAnswer;

  /// What the review field should start with: a saved answer beats OCR.
  String get fieldText =>
      currentAnswer.trim().isNotEmpty ? currentAnswer : extractedText;
}

class OcrMappingRecord {
  const OcrMappingRecord({
    required this.candidates,
    required this.incompleteOcr,
  });

  factory OcrMappingRecord.fromJson(Map<String, dynamic> json) =>
      OcrMappingRecord(
        candidates: ((json['candidates'] as List<dynamic>?) ?? [])
            .map(
              (item) =>
                  OcrCandidateRecord.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        incompleteOcr: json['incomplete_ocr'] as bool? ?? false,
      );

  final List<OcrCandidateRecord> candidates;
  final bool incompleteOcr;
}

class ApiException implements Exception, ApiErrorMessage {
  const ApiException(this.message);
  @override
  final String message;
  @override
  String toString() => message;
}

abstract class BayyinGateway {
  Future<UserSession> login(String username, String password);
  Future<List<TeacherAccount>> fetchTeachers(String token);
  Future<TeacherAccount> createTeacher({
    required String token,
    required String username,
    required String password,
    required String firstName,
    required String lastName,
    required String email,
  });
  Future<List<ClassroomRecord>> fetchClassrooms(String token);
  Future<ClassroomRecord> createClassroom({
    required String token,
    required String name,
    required String grade,
    required String subject,
    required String academicYear,
    required String teacherProfileId,
  });
  Future<ClassroomRecord> updateClassroom({
    required String token,
    required String classroomId,
    required String name,
    required String grade,
    required String subject,
    required String academicYear,
    required String teacherProfileId,
  });
  Future<void> deleteClassroom({
    required String token,
    required String classroomId,
  });
  Future<List<StudentRecord>> fetchStudents({
    required String token,
    required String classroomId,
  });
  Future<void> createStudent({
    required String token,
    required String classroomId,
    required String internalCode,
    required String displayName,
  });
  Future<List<AssessmentRecord>> fetchAssessments(
    String token, {
    bool archived = false,
  });
  Future<AssessmentRecord> fetchAssessment({
    required String token,
    required String assessmentId,
  });
  Future<AssessmentRecord> createAssessment({
    required String token,
    required String classroomId,
    required String title,
  });
  Future<AssessmentRecord> setAssessmentArchived({
    required String token,
    required String assessmentId,
    required bool archived,
  });
  Future<void> deleteAssessment({
    required String token,
    required String assessmentId,
  });
  Future<QuestionRecord> createQuestion({
    required String token,
    required String assessmentId,
    required String text,
    required double maxScore,
    required String modelAnswer,
  });
  Future<void> deleteQuestion({
    required String token,
    required String assessmentId,
    required String questionId,
  });
  Future<void> uploadExamPaper({
    required String token,
    required String assessmentId,
    required String filename,
    required Uint8List bytes,
  });
  Future<List<QuestionCandidateRecord>> extractQuestions({
    required String token,
    required String assessmentId,
  });
  Future<List<QuestionCandidateRecord>> fetchQuestionCandidates({
    required String token,
    required String assessmentId,
  });
  Future<AssessmentRecord> confirmQuestionCandidates({
    required String token,
    required String assessmentId,
    required List<QuestionCandidateRecord> candidates,
  });
  Future<List<SubmissionRecord>> fetchSubmissions({
    required String token,
    required String assessmentId,
  });
  Future<SubmissionRecord> fetchSubmission({
    required String token,
    required String assessmentId,
    required String submissionId,
  });
  Future<SubmissionRecord> createSubmission({
    required String token,
    required String assessmentId,
    required String studentId,
  });

  /// Saves the whole answer sheet at once, keyed by question id.
  Future<SubmissionRecord> saveAnswers({
    required String token,
    required String assessmentId,
    required String submissionId,
    required Map<String, String> answersByQuestionId,
  });
  Future<List<AttachmentRecord>> fetchAttachments({
    required String token,
    required String assessmentId,
    required String submissionId,
  });
  Future<AttachmentRecord> uploadAttachment({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String filename,
    required Uint8List bytes,
  });
  Future<void> deleteAttachment({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String attachmentId,
  });

  /// The current OCR result, or null when it has never been run.
  Future<OcrRecord?> fetchOcr({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String attachmentId,
  });
  Future<OcrRecord> runOcr({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String attachmentId,
  });
  Future<OcrMappingRecord> fetchOcrMapping({
    required String token,
    required String assessmentId,
    required String submissionId,
  });
  Future<OcrMappingRecord> runOcrMapping({
    required String token,
    required String assessmentId,
    required String submissionId,
  });
  Future<OcrMappingRecord> confirmOcrMapping({
    required String token,
    required String assessmentId,
    required String submissionId,
    required Map<String, String> answersByQuestionId,
  });

  /// Grades every confirmed answer on the sheet and returns the submission.
  Future<SubmissionRecord> evaluateAnswers({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String locale,
  });
  Future<SubmissionResultRecord> fetchSubmissionResult({
    required String token,
    required String assessmentId,
    required String submissionId,
  });
  Future<ClassInsightsRecord> fetchClassInsights({
    required String token,
    required String assessmentId,
  });
  Future<List<RemediationPlanRecord>> fetchRemediationPlans({
    required String token,
    required String assessmentId,
  });
  Future<RemediationGenerateRecord> generateRemediationPlan({
    required String token,
    required String assessmentId,
    required String group,
    required String locale,
  });
  Future<ManagerInsightsRecord> fetchManagerInsights(String token);
  Future<void> logout(String token);
}

class BayyinApi implements BayyinGateway {
  BayyinApi({this.baseUrl = defaultApiBaseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<UserSession> login(String username, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/auth/login/'),
      headers: _jsonHeaders,
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    final user = data['user'] as Map<String, dynamic>;
    return UserSession(
      token: data['token'] as String,
      username: user['username'] as String,
      fullName: user['full_name'] as String? ?? '',
      serverDisplayName: user['display_name'] as String? ?? '',
      role: user['role'] as String,
    );
  }

  @override
  Future<List<TeacherAccount>> fetchTeachers(String token) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/management/teachers/'),
      headers: _authorizedHeaders(token),
    );
    final data = _decodeAny(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data));
    }
    return (data as List<dynamic>)
        .map((item) => TeacherAccount.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<TeacherAccount> createTeacher({
    required String token,
    required String username,
    required String password,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/management/teachers/'),
      headers: _authorizedHeaders(token),
      body: jsonEncode({
        'username': username,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 201) throw ApiException(_errorMessage(data));
    return TeacherAccount.fromJson(data);
  }

  @override
  Future<List<ClassroomRecord>> fetchClassrooms(String token) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/management/classrooms/'),
      headers: _authorizedHeaders(token),
    );
    final data = _decodeAny(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return (data as List<dynamic>)
        .map((item) => ClassroomRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ClassroomRecord> createClassroom({
    required String token,
    required String name,
    required String grade,
    required String subject,
    required String academicYear,
    required String teacherProfileId,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/management/classrooms/'),
      headers: _authorizedHeaders(token),
      body: jsonEncode({
        'name': name,
        'grade': grade,
        'subject': subject,
        'academic_year': academicYear,
        'teacher_profile_id': teacherProfileId,
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 201) throw ApiException(_errorMessage(data));
    return ClassroomRecord.fromJson(data);
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
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/v1/management/classrooms/$classroomId/'),
      headers: _authorizedHeaders(token),
      body: jsonEncode({
        'name': name,
        'grade': grade,
        'subject': subject,
        'academic_year': academicYear,
        'teacher_profile_id': teacherProfileId,
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return ClassroomRecord.fromJson(data);
  }

  @override
  Future<void> deleteClassroom({
    required String token,
    required String classroomId,
  }) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/v1/management/classrooms/$classroomId/'),
      headers: _authorizedHeaders(token),
    );
    if (response.statusCode != 204) {
      throw ApiException(_errorMessage(_decodeAny(response)));
    }
  }

  @override
  Future<List<StudentRecord>> fetchStudents({
    required String token,
    required String classroomId,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/management/classrooms/$classroomId/students/'),
      headers: _authorizedHeaders(token),
    );
    final data = _decodeAny(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return (data as List<dynamic>)
        .map((item) => StudentRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createStudent({
    required String token,
    required String classroomId,
    required String internalCode,
    required String displayName,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/management/classrooms/$classroomId/students/'),
      headers: _authorizedHeaders(token),
      body: jsonEncode({
        'internal_code': internalCode,
        'display_name': displayName,
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 201) throw ApiException(_errorMessage(data));
  }

  @override
  Future<List<AssessmentRecord>> fetchAssessments(
    String token, {
    bool archived = false,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/assessments/').replace(
        queryParameters: archived ? const {'status': 'archived'} : null,
      ),
      headers: _authorizedHeaders(token),
    );
    final data = _decodeAny(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return (data as List<dynamic>)
        .map((item) => AssessmentRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AssessmentRecord> fetchAssessment({
    required String token,
    required String assessmentId,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/assessments/$assessmentId/'),
      headers: _authorizedHeaders(token),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return AssessmentRecord.fromJson(data);
  }

  @override
  Future<AssessmentRecord> createAssessment({
    required String token,
    required String classroomId,
    required String title,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/assessments/'),
      headers: _authorizedHeaders(token),
      body: jsonEncode({'classroom_id': classroomId, 'title': title}),
    );
    final data = _decode(response);
    if (response.statusCode != 201) throw ApiException(_errorMessage(data));
    return AssessmentRecord.fromJson(data);
  }

  @override
  Future<AssessmentRecord> setAssessmentArchived({
    required String token,
    required String assessmentId,
    required bool archived,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/v1/assessments/$assessmentId/'),
      headers: _authorizedHeaders(token),
      body: jsonEncode({'archived': archived}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return AssessmentRecord.fromJson(data);
  }

  @override
  Future<void> deleteAssessment({
    required String token,
    required String assessmentId,
  }) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/v1/assessments/$assessmentId/'),
      headers: _authorizedHeaders(token),
    );
    if (response.statusCode != 204) {
      throw ApiException(_errorMessage(_decodeAny(response)));
    }
  }

  @override
  Future<QuestionRecord> createQuestion({
    required String token,
    required String assessmentId,
    required String text,
    required double maxScore,
    required String modelAnswer,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/assessments/$assessmentId/questions/'),
      headers: _authorizedHeaders(token),
      body: jsonEncode({
        'text': text,
        'max_score': maxScore,
        'model_answer': modelAnswer,
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 201) throw ApiException(_errorMessage(data));
    return QuestionRecord.fromJson(data);
  }

  @override
  Future<void> deleteQuestion({
    required String token,
    required String assessmentId,
    required String questionId,
  }) async {
    final response = await _client.delete(
      Uri.parse(
        '$baseUrl/api/v1/assessments/$assessmentId/questions/$questionId/',
      ),
      headers: _authorizedHeaders(token),
    );
    if (response.statusCode != 204) {
      throw ApiException(_errorMessage(_decodeAny(response)));
    }
  }

  @override
  Future<void> uploadExamPaper({
    required String token,
    required String assessmentId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse(
              '$baseUrl/api/v1/assessments/$assessmentId/source-attachments/',
            ),
          )
          ..headers['Authorization'] = 'Token $token'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    final data = _decode(response);
    if (response.statusCode != 201) throw ApiException(_errorMessage(data));
  }

  @override
  Future<List<QuestionCandidateRecord>> extractQuestions({
    required String token,
    required String assessmentId,
  }) async {
    final response = await _client.post(
      Uri.parse(
        '$baseUrl/api/v1/assessments/$assessmentId/extract-questions/',
      ),
      headers: _authorizedHeaders(token),
    );
    final data = _decodeAny(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data));
    }
    return (data as List<dynamic>)
        .map(
          (item) =>
              QuestionCandidateRecord.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<QuestionCandidateRecord>> fetchQuestionCandidates({
    required String token,
    required String assessmentId,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '$baseUrl/api/v1/assessments/$assessmentId/question-candidates/',
      ),
      headers: _authorizedHeaders(token),
    );
    final data = _decodeAny(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data));
    }
    return (data as List<dynamic>)
        .map(
          (item) =>
              QuestionCandidateRecord.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<AssessmentRecord> confirmQuestionCandidates({
    required String token,
    required String assessmentId,
    required List<QuestionCandidateRecord> candidates,
  }) async {
    final response = await _client.put(
      Uri.parse(
        '$baseUrl/api/v1/assessments/$assessmentId/question-candidates/confirm/',
      ),
      headers: _authorizedHeaders(token),
      body: jsonEncode({
        'candidates': [
          for (final candidate in candidates)
            {
              if (candidate.id.isNotEmpty) 'id': candidate.id,
              'order': candidate.order,
              'extracted_text': candidate.extractedText,
              'proposed_max_score': candidate.proposedMaxScore,
              'proposed_model_answer': candidate.proposedModelAnswer,
            },
        ],
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return AssessmentRecord.fromJson(
      data['assessment'] as Map<String, dynamic>,
    );
  }

  @override
  Future<List<SubmissionRecord>> fetchSubmissions({
    required String token,
    required String assessmentId,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/assessments/$assessmentId/submissions/'),
      headers: _authorizedHeaders(token),
    );
    final data = _decodeAny(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return (data as List<dynamic>)
        .map((item) => SubmissionRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<SubmissionRecord> fetchSubmission({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '$baseUrl/api/v1/assessments/$assessmentId/submissions/$submissionId/',
      ),
      headers: _authorizedHeaders(token),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return SubmissionRecord.fromJson(data);
  }

  @override
  Future<SubmissionRecord> createSubmission({
    required String token,
    required String assessmentId,
    required String studentId,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/assessments/$assessmentId/submissions/'),
      headers: _authorizedHeaders(token),
      body: jsonEncode({'student_id': studentId}),
    );
    final data = _decode(response);
    if (response.statusCode != 201) throw ApiException(_errorMessage(data));
    return SubmissionRecord.fromJson(data);
  }

  @override
  Future<SubmissionRecord> saveAnswers({
    required String token,
    required String assessmentId,
    required String submissionId,
    required Map<String, String> answersByQuestionId,
  }) async {
    final response = await _client.put(
      Uri.parse(
        '$baseUrl/api/v1/assessments/$assessmentId/submissions/$submissionId/answers/',
      ),
      headers: _authorizedHeaders(token),
      body: jsonEncode({
        'answers': [
          for (final entry in answersByQuestionId.entries)
            {'question_id': entry.key, 'answer_text': entry.value},
        ],
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return SubmissionRecord.fromJson(data);
  }

  @override
  Future<List<AttachmentRecord>> fetchAttachments({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async {
    final response = await _client.get(
      _attachmentsUri(assessmentId, submissionId),
      headers: _authorizedHeaders(token),
    );
    final data = _decodeAny(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return (data as List<dynamic>)
        .map((item) => AttachmentRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AttachmentRecord> uploadAttachment({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String filename,
    required Uint8List bytes,
  }) async {
    // The submission comes from the URL and the uploader from the token, so
    // the file is the only thing the body carries.
    final request =
        http.MultipartRequest(
            'POST',
            _attachmentsUri(assessmentId, submissionId),
          )
          ..headers['Authorization'] = 'Token $token'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    final data = _decode(response);
    if (response.statusCode != 201) throw ApiException(_errorMessage(data));
    return AttachmentRecord.fromJson(data);
  }

  @override
  Future<void> deleteAttachment({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String attachmentId,
  }) async {
    final response = await _client.delete(
      Uri.parse('${_attachmentsUri(assessmentId, submissionId)}$attachmentId/'),
      headers: _authorizedHeaders(token),
    );
    if (response.statusCode != 204) {
      throw ApiException(_errorMessage(_decodeAny(response)));
    }
  }

  @override
  Future<OcrRecord?> fetchOcr({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String attachmentId,
  }) async {
    final response = await _client.get(
      _ocrUri(assessmentId, submissionId, attachmentId),
      headers: _authorizedHeaders(token),
    );
    if (response.statusCode == 404) return null;
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return OcrRecord.fromJson(data);
  }

  @override
  Future<OcrRecord> runOcr({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String attachmentId,
  }) async {
    final response = await _client.post(
      _ocrUri(assessmentId, submissionId, attachmentId),
      headers: _authorizedHeaders(token),
      body: '{}',
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return OcrRecord.fromJson(data);
  }

  @override
  Future<OcrMappingRecord> fetchOcrMapping({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async {
    final response = await _client.get(
      _ocrMappingUri(assessmentId, submissionId),
      headers: _authorizedHeaders(token),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return OcrMappingRecord.fromJson(data);
  }

  @override
  Future<OcrMappingRecord> runOcrMapping({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async {
    final response = await _client.post(
      _ocrMappingUri(assessmentId, submissionId),
      headers: _authorizedHeaders(token),
      body: '{}',
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return OcrMappingRecord.fromJson(data);
  }

  @override
  Future<OcrMappingRecord> confirmOcrMapping({
    required String token,
    required String assessmentId,
    required String submissionId,
    required Map<String, String> answersByQuestionId,
  }) async {
    final response = await _client.put(
      Uri.parse('${_ocrMappingUri(assessmentId, submissionId)}confirm/'),
      headers: _authorizedHeaders(token),
      body: jsonEncode({
        'answers': [
          for (final entry in answersByQuestionId.entries)
            {'question_id': entry.key, 'answer_text': entry.value},
        ],
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return OcrMappingRecord.fromJson(data);
  }

  @override
  Future<SubmissionRecord> evaluateAnswers({
    required String token,
    required String assessmentId,
    required String submissionId,
    required String locale,
  }) async {
    final response = await _client.post(
      Uri.parse(
        '$baseUrl/api/v1/assessments/$assessmentId/submissions/$submissionId/evaluate/',
      ),
      headers: _authorizedHeaders(token),
      body: jsonEncode({'locale': locale}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return SubmissionRecord.fromJson(data);
  }

  @override
  Future<SubmissionResultRecord> fetchSubmissionResult({
    required String token,
    required String assessmentId,
    required String submissionId,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '$baseUrl/api/v1/assessments/$assessmentId/submissions/$submissionId/result/',
      ),
      headers: _authorizedHeaders(token),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return SubmissionResultRecord.fromJson(data);
  }

  @override
  Future<ClassInsightsRecord> fetchClassInsights({
    required String token,
    required String assessmentId,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/assessments/$assessmentId/class-insights/'),
      headers: _authorizedHeaders(token),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return ClassInsightsRecord.fromJson(data);
  }

  @override
  Future<List<RemediationPlanRecord>> fetchRemediationPlans({
    required String token,
    required String assessmentId,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/assessments/$assessmentId/remediation-plans/'),
      headers: _authorizedHeaders(token),
    );
    final data = _decodeAny(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorMessage(data));
    }
    return ((data as List<dynamic>?) ?? [])
        .map(
          (item) =>
              RemediationPlanRecord.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<RemediationGenerateRecord> generateRemediationPlan({
    required String token,
    required String assessmentId,
    required String group,
    required String locale,
  }) async {
    final response = await _client.post(
      Uri.parse(
        '$baseUrl/api/v1/assessments/$assessmentId/remediation-plans/$group/generate/',
      ),
      headers: _authorizedHeaders(token),
      body: jsonEncode({'locale': locale}),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return RemediationGenerateRecord.fromJson(data);
  }

  @override
  Future<ManagerInsightsRecord> fetchManagerInsights(String token) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/manager/insights/'),
      headers: _authorizedHeaders(token),
    );
    final data = _decode(response);
    if (response.statusCode != 200) throw ApiException(_errorMessage(data));
    return ManagerInsightsRecord.fromJson(data);
  }

  Uri _ocrMappingUri(String assessmentId, String submissionId) => Uri.parse(
    '$baseUrl/api/v1/assessments/$assessmentId'
    '/submissions/$submissionId/ocr-mapping/',
  );

  Uri _ocrUri(String assessmentId, String submissionId, String attachmentId) =>
      Uri.parse(
        '${_attachmentsUri(assessmentId, submissionId)}$attachmentId/ocr/',
      );

  Uri _attachmentsUri(String assessmentId, String submissionId) => Uri.parse(
    '$baseUrl/api/v1/assessments/$assessmentId'
    '/submissions/$submissionId/attachments/',
  );

  @override
  Future<void> logout(String token) async {
    await _client.post(
      Uri.parse('$baseUrl/api/v1/auth/logout/'),
      headers: _authorizedHeaders(token),
    );
  }

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  Map<String, String> _authorizedHeaders(String token) => {
    ..._jsonHeaders,
    'Authorization': 'Token $token',
  };

  Map<String, dynamic> _decode(http.Response response) {
    final data = _decodeAny(response);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  dynamic _decodeAny(http.Response response) {
    final raw = utf8.decode(response.bodyBytes);
    final trimmed = raw.trimLeft();
    if (trimmed.startsWith('<')) {
      throw const ApiException('تعذر قراءة استجابة الخادم.');
    }
    try {
      return jsonDecode(raw);
    } on FormatException {
      throw const ApiException('تعذر قراءة استجابة الخادم.');
    }
  }

  String _errorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) return detail;
      final errors = data.values.expand(
        (value) => value is List ? value : [value],
      );
      if (errors.isNotEmpty) return errors.first.toString();
    }
    return 'تعذر إكمال الطلب. حاول مرة أخرى.';
  }
}
