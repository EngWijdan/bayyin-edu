import 'dart:convert';

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
  });

  factory ClassroomRecord.fromJson(Map<String, dynamic> json) =>
      ClassroomRecord(
        id: json['id'].toString(),
        name: json['name'] as String,
        grade: json['grade'] as String,
        subject: json['subject'] as String,
        academicYear: json['academic_year'] as String,
        teacherName: json['teacher_name'] as String,
        studentsCount: json['students_count'] as int? ?? 0,
      );

  final String id;
  final String name;
  final String grade;
  final String subject;
  final String academicYear;
  final String teacherName;
  final int studentsCount;
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
            .map((item) => QuestionRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
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
}

/// One question of the assessment paired with what the student answered.
/// The backend returns an entry for every question, so [answerText] is empty
/// rather than absent when nothing has been entered yet.
class AnswerRecord {
  const AnswerRecord({
    required this.questionId,
    required this.order,
    required this.text,
    required this.maxScore,
    required this.answerText,
  });

  factory AnswerRecord.fromJson(Map<String, dynamic> json) => AnswerRecord(
    questionId: json['question_id'].toString(),
    order: json['order'] as int? ?? 0,
    text: json['text'] as String? ?? '',
    maxScore: (json['max_score'] as num?)?.toDouble() ?? 0,
    answerText: json['answer_text'] as String? ?? '',
  );

  final String questionId;
  final int order;
  final String text;
  final double maxScore;
  final String answerText;
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
      );

  final String id;
  final String studentId;
  final String studentName;
  final String studentCode;
  final String assessmentTitle;
  final List<AnswerRecord> answers;

  bool get hasName => studentName.trim().isNotEmpty;
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
  Future<List<AssessmentRecord>> fetchAssessments(String token);
  Future<AssessmentRecord> fetchAssessment({
    required String token,
    required String assessmentId,
  });
  Future<AssessmentRecord> createAssessment({
    required String token,
    required String classroomId,
    required String title,
  });
  Future<QuestionRecord> createQuestion({
    required String token,
    required String assessmentId,
    required String text,
    required double maxScore,
    required String modelAnswer,
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
  Future<List<AssessmentRecord>> fetchAssessments(String token) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/assessments/'),
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
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
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
