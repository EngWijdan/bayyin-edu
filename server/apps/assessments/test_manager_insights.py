import json
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import UserProfile
from apps.assessments.models import (
    AnswerEvaluation,
    Assessment,
    Question,
    Submission,
    SubmissionAnswer,
)
from apps.assessments.services.manager_insights import build_manager_insights
from apps.classrooms.models import Student

from .tests import make_classroom


def grade(answer, eval_status, score, misconception=""):
    return AnswerEvaluation.objects.create(
        answer=answer,
        status=eval_status,
        awarded_score=Decimal(str(score)),
        feedback="ملاحظات.",
        misconception=misconception,
        model_name="fake-model",
        evaluated_at=timezone.now(),
    )


class ManagerInsightsTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="insights-mgr",
                password="strong-pass-123",
                first_name="نورة",
                last_name="المدير",
            ),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="insights-teacher-a",
                password="strong-pass-123",
                first_name="أحمد",
                last_name="الغامدي",
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="insights-teacher-b",
                password="strong-pass-123",
                first_name="سارة",
                last_name="المطيري",
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.class_a = make_classroom(self.teacher_a, "سادس أ")
        self.class_b = make_classroom(self.teacher_b, "خامس أ", subject="العلوم")
        self.assessment_a = Assessment.objects.create(
            classroom=self.class_a,
            title="اختبار الكسور",
            created_by=self.teacher_a,
        )
        self.assessment_b = Assessment.objects.create(
            classroom=self.class_b,
            title="اختبار الخلية",
            created_by=self.teacher_b,
        )
        self.q1 = Question.objects.create(
            assessment=self.assessment_a,
            order=1,
            text="ما ناتج 1/2 + 1/4؟",
            max_score=Decimal("10"),
            model_answer="3/4",
        )
        self.q2 = Question.objects.create(
            assessment=self.assessment_a,
            order=2,
            text="بسّط الكسر 4/8",
            max_score=Decimal("10"),
            model_answer="1/2",
        )
        self.complete_student = Student.objects.create(
            classroom=self.class_a, internal_code="S-001", display_name="طالب أ"
        )
        self.incomplete_student = Student.objects.create(
            classroom=self.class_a, internal_code="S-002", display_name="طالب ب"
        )
        self.absent_student = Student.objects.create(
            classroom=self.class_a, internal_code="S-003", display_name="طالب ج"
        )
        Student.objects.create(
            classroom=self.class_b, internal_code="S-900", display_name="طالب علوم"
        )
        self.complete_sub = Submission.objects.create(
            assessment=self.assessment_a, student=self.complete_student
        )
        self.incomplete_sub = Submission.objects.create(
            assessment=self.assessment_a, student=self.incomplete_student
        )
        a1 = SubmissionAnswer.objects.create(
            submission=self.complete_sub, question=self.q1, answer_text="3/4"
        )
        a2 = SubmissionAnswer.objects.create(
            submission=self.complete_sub, question=self.q2, answer_text="4/8"
        )
        b1 = SubmissionAnswer.objects.create(
            submission=self.incomplete_sub, question=self.q1, answer_text="خطأ"
        )
        grade(a1, AnswerEvaluation.Status.CORRECT, 10)
        grade(a2, AnswerEvaluation.Status.INCORRECT, 0, misconception="خلط المقام")
        grade(b1, AnswerEvaluation.Status.INCORRECT, 0, misconception="نسي التبسيط")

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def url(self):
        return "/api/v1/manager/insights/"

    def test_summary_counts_are_correct(self):
        summary = build_manager_insights().summary
        self.assertEqual(summary.total_teachers, 2)
        self.assertEqual(summary.total_classrooms, 2)
        self.assertEqual(summary.total_students, 4)
        self.assertEqual(summary.total_assessments, 2)
        self.assertEqual(summary.assessments_with_complete_results, 1)
        self.assertEqual(summary.assessments_with_incomplete_results, 1)

    def test_teacher_count_is_correct(self):
        self.assertEqual(build_manager_insights().summary.total_teachers, 2)
        self.assertEqual(len(build_manager_insights().teachers), 2)

    def test_classroom_count_is_correct(self):
        self.assertEqual(build_manager_insights().summary.total_classrooms, 2)
        self.assertEqual(len(build_manager_insights().classrooms), 2)

    def test_student_count_is_correct(self):
        self.assertEqual(build_manager_insights().summary.total_students, 4)

    def test_assessment_count_is_correct(self):
        self.assertEqual(build_manager_insights().summary.total_assessments, 2)
        self.assertEqual(len(build_manager_insights().assessments), 2)

    def test_overall_average_uses_complete_results_only(self):
        summary = build_manager_insights().summary
        self.assertEqual(summary.overall_average_percentage, Decimal("50.00"))

    def test_no_question_submission_does_not_affect_average(self):
        empty_student = Student.objects.create(
            classroom=self.class_a, internal_code="S-010", display_name="طالب بلا أسئلة"
        )
        empty_assessment = Assessment.objects.create(
            classroom=self.class_a,
            title="اختبار بلا أسئلة",
            created_by=self.teacher_a,
        )
        Submission.objects.create(
            assessment=empty_assessment, student=empty_student
        )
        summary = build_manager_insights().summary
        self.assertEqual(summary.overall_average_percentage, Decimal("50.00"))
        self.assertEqual(summary.assessments_with_complete_results, 1)

    def test_average_is_null_when_no_complete_results(self):
        AnswerEvaluation.objects.all().delete()
        self.complete_sub.delete()
        summary = build_manager_insights().summary
        self.assertIsNone(summary.overall_average_percentage)
        self.assertEqual(summary.assessments_with_complete_results, 0)

    def test_classroom_summaries_are_correct(self):
        by_name = {row.classroom_name: row for row in build_manager_insights().classrooms}
        sixth = by_name["سادس أ"]
        self.assertEqual(sixth.teacher_name, "أحمد الغامدي")
        self.assertEqual(sixth.student_count, 3)
        self.assertEqual(sixth.assessment_count, 1)
        self.assertEqual(sixth.completed_results_count, 1)
        self.assertEqual(sixth.incomplete_results_count, 1)
        self.assertEqual(sixth.average_percentage, Decimal("50.00"))
        fifth = by_name["خامس أ"]
        self.assertEqual(fifth.student_count, 1)
        self.assertEqual(fifth.completed_results_count, 0)
        self.assertIsNone(fifth.average_percentage)

    def test_teacher_summaries_are_correct(self):
        by_name = {row.display_name: row for row in build_manager_insights().teachers}
        ahmed = by_name["أحمد الغامدي"]
        self.assertEqual(ahmed.classrooms_count, 1)
        self.assertEqual(ahmed.students_count, 3)
        self.assertEqual(ahmed.assessments_count, 1)
        self.assertEqual(ahmed.complete_results_count, 1)
        self.assertEqual(ahmed.incomplete_results_count, 1)
        self.assertEqual(ahmed.average_percentage, Decimal("50.00"))
        sara = by_name["سارة المطيري"]
        self.assertEqual(sara.classrooms_count, 1)
        self.assertEqual(sara.students_count, 1)
        self.assertEqual(sara.complete_results_count, 0)
        self.assertIsNone(sara.average_percentage)

    def test_assessment_summaries_are_correct(self):
        rows = list(build_manager_insights().assessments)
        self.assertEqual(rows[0].title, "اختبار الخلية")
        fractions = next(row for row in rows if row.title == "اختبار الكسور")
        self.assertEqual(fractions.classroom, "سادس أ")
        self.assertEqual(fractions.teacher, "أحمد الغامدي")
        self.assertEqual(fractions.students_with_submission, 2)
        self.assertEqual(fractions.complete_results, 1)
        self.assertEqual(fractions.incomplete_results, 1)
        self.assertEqual(fractions.average_percentage, Decimal("50.00"))

    def test_incomplete_results_are_counted_separately(self):
        insights = build_manager_insights()
        self.assertEqual(insights.summary.assessments_with_incomplete_results, 1)
        fractions = next(
            row for row in insights.assessments if row.title == "اختبار الكسور"
        )
        self.assertEqual(fractions.incomplete_results, 1)
        self.assertEqual(fractions.complete_results, 1)

    def test_highest_gap_questions_are_correct(self):
        gaps = build_manager_insights().highest_gap_questions
        self.assertEqual(gaps[0].question_order, 2)
        self.assertEqual(gaps[0].question_text, "بسّط الكسر 4/8")
        self.assertEqual(gaps[0].assessment_title, "اختبار الكسور")
        self.assertEqual(gaps[0].classroom, "سادس أ")
        self.assertEqual(gaps[0].evaluated_students, 1)
        self.assertEqual(gaps[0].gap_count, 1)
        self.assertEqual(gaps[0].gap_percentage, Decimal("100.00"))
        q1 = next(item for item in gaps if item.question_order == 1)
        self.assertEqual(q1.evaluated_students, 2)
        self.assertEqual(q1.gap_count, 1)
        self.assertEqual(q1.gap_percentage, Decimal("50.00"))

    def test_misconceptions_are_aggregated_exactly(self):
        items = {
            item.text: item.count
            for item in build_manager_insights().misconceptions
        }
        self.assertEqual(items["خلط المقام"], 1)
        self.assertEqual(items["نسي التبسيط"], 1)

    def test_overview_does_not_leak_student_names(self):
        self.authenticate(self.manager)
        response = self.client.get(self.url())
        blob = json.dumps(response.data, ensure_ascii=False, default=str)
        self.assertNotIn("طالب أ", blob)
        self.assertNotIn("طالب ب", blob)
        self.assertNotIn("طالب ج", blob)
        self.assertNotIn("طالب علوم", blob)
        self.assertNotIn("S-001", blob)

    def test_teacher_cannot_access_manager_insights(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(self.url())
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_manager_can_access(self):
        self.authenticate(self.manager)
        response = self.client.get(self.url())
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["summary"]["total_teachers"], 2)
        self.assertEqual(
            response.data["summary"]["overall_average_percentage"], Decimal("50.00")
        )
        self.assertEqual(len(response.data["classrooms"]), 2)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get(self.url())
        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )

    def test_deactivated_manager_is_rejected(self):
        self.manager.is_active = False
        self.manager.save(update_fields=["is_active"])
        self.authenticate(self.manager)
        response = self.client.get(self.url())
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_no_data_state_is_safe(self):
        Assessment.objects.all().delete()
        Student.objects.all().delete()
        self.class_a.delete()
        self.class_b.delete()
        UserProfile.objects.filter(role=UserProfile.Role.TEACHER).delete()
        insights = build_manager_insights()
        self.assertEqual(insights.summary.total_teachers, 0)
        self.assertEqual(insights.summary.total_classrooms, 0)
        self.assertEqual(insights.summary.total_students, 0)
        self.assertEqual(insights.summary.total_assessments, 0)
        self.assertIsNone(insights.summary.overall_average_percentage)
        self.assertEqual(insights.classrooms, ())
        self.assertEqual(insights.highest_gap_questions, ())
        self.assertEqual(insights.misconceptions, ())
