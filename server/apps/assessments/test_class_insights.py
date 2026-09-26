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
from apps.assessments.services.class_insights import (
    GROUP_FOUNDATION,
    GROUP_PRACTICE,
    GROUP_READY,
    PENDING_INCOMPLETE_EVALUATION,
    PENDING_NO_QUESTIONS,
    assign_group,
    build_class_insights,
)
from apps.classrooms.models import Student

from .tests import make_classroom


def grade(answer, status, score, feedback="ملاحظات.", misconception=""):
    return AnswerEvaluation.objects.create(
        answer=answer,
        status=status,
        awarded_score=Decimal(str(score)),
        feedback=feedback,
        misconception=misconception,
        model_name="fake-model",
        evaluated_at=timezone.now(),
    )


class ClassInsightsTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="insights-manager", password="strong-pass-123"
            ),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="insights-teacher-a", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="insights-teacher-b", password="strong-pass-123"
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
        self.foundation_student = Student.objects.create(
            classroom=self.class_a, internal_code="S-001", display_name="طالب تأسيس"
        )
        self.practice_student = Student.objects.create(
            classroom=self.class_a, internal_code="S-002", display_name="طالب تدريب"
        )
        self.ready_student = Student.objects.create(
            classroom=self.class_a, internal_code="S-003", display_name="طالب جاهز"
        )
        self.pending_student = Student.objects.create(
            classroom=self.class_a, internal_code="S-004", display_name="طالب معلق"
        )
        self.absent_student = Student.objects.create(
            classroom=self.class_a, internal_code="S-005", display_name="بدون تسليم"
        )
        self.other_student = Student.objects.create(
            classroom=self.class_b, internal_code="S-900", display_name="طالب آخر"
        )
        self.foundation_sub = Submission.objects.create(
            assessment=self.assessment_a, student=self.foundation_student
        )
        self.practice_sub = Submission.objects.create(
            assessment=self.assessment_a, student=self.practice_student
        )
        self.ready_sub = Submission.objects.create(
            assessment=self.assessment_a, student=self.ready_student
        )
        self.pending_sub = Submission.objects.create(
            assessment=self.assessment_a, student=self.pending_student
        )
        self.other_sub = Submission.objects.create(
            assessment=self.assessment_b, student=self.other_student
        )
        self._answer(self.foundation_sub, self.q1, "3/4")
        self._answer(self.foundation_sub, self.q2, "4/8")
        self._answer(self.practice_sub, self.q1, "3/4")
        self._answer(self.practice_sub, self.q2, "2/4")
        self._answer(self.ready_sub, self.q1, "3/4")
        self._answer(self.ready_sub, self.q2, "1/2")
        self._answer(self.pending_sub, self.q1, "خطأ")
        self._answer(self.pending_sub, self.q2, "")

    def _answer(self, submission, question, text):
        return SubmissionAnswer.objects.create(
            submission=submission, question=question, answer_text=text
        )

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def insights_url(self, assessment):
        return f"/api/v1/assessments/{assessment.id}/class-insights/"

    def grade_fixture(self):
        grade(
            self.foundation_sub.answers.get(question=self.q1),
            AnswerEvaluation.Status.CORRECT,
            10,
        )
        grade(
            self.foundation_sub.answers.get(question=self.q2),
            AnswerEvaluation.Status.INCORRECT,
            0,
            misconception="خلط المقام",
        )
        grade(
            self.practice_sub.answers.get(question=self.q1),
            AnswerEvaluation.Status.CORRECT,
            10,
        )
        grade(
            self.practice_sub.answers.get(question=self.q2),
            AnswerEvaluation.Status.PARTIAL,
            4,
            misconception="خلط المقام",
        )
        grade(
            self.ready_sub.answers.get(question=self.q1),
            AnswerEvaluation.Status.CORRECT,
            10,
        )
        grade(
            self.ready_sub.answers.get(question=self.q2),
            AnswerEvaluation.Status.CORRECT,
            10,
        )
        grade(
            self.pending_sub.answers.get(question=self.q1),
            AnswerEvaluation.Status.INCORRECT,
            0,
            misconception="نسي التبسيط",
        )

    def test_assign_group_thresholds(self):
        self.assertEqual(assign_group(Decimal("59.99")), GROUP_FOUNDATION)
        self.assertEqual(assign_group(Decimal("60")), GROUP_PRACTICE)
        self.assertEqual(assign_group(Decimal("79.99")), GROUP_PRACTICE)
        self.assertEqual(assign_group(Decimal("80")), GROUP_READY)

    def test_summary_counts_are_correct(self):
        self.grade_fixture()
        summary = build_class_insights(self.assessment_a).summary
        self.assertEqual(summary.total_students_in_class, 5)
        self.assertEqual(summary.students_with_submission, 4)
        self.assertEqual(summary.students_without_submission, 1)
        self.assertEqual(summary.complete_results, 3)
        self.assertEqual(summary.incomplete_results, 1)

    def test_students_without_submission_are_counted(self):
        self.grade_fixture()
        summary = build_class_insights(self.assessment_a).summary
        self.assertEqual(summary.students_without_submission, 1)

    def test_incomplete_results_are_counted_separately(self):
        self.grade_fixture()
        insights = build_class_insights(self.assessment_a)
        self.assertEqual(insights.summary.incomplete_results, 1)
        self.assertEqual(len(insights.pending_students), 1)
        self.assertEqual(
            insights.pending_students[0].student_id, self.pending_student.id
        )

    def test_average_uses_complete_results_only(self):
        self.grade_fixture()
        summary = build_class_insights(self.assessment_a).summary
        self.assertEqual(summary.average_percentage, Decimal("73.33"))

    def test_average_is_null_when_no_complete_results(self):
        grade(
            self.pending_sub.answers.get(question=self.q1),
            AnswerEvaluation.Status.CORRECT,
            10,
        )
        self.foundation_sub.delete()
        self.practice_sub.delete()
        self.ready_sub.delete()
        summary = build_class_insights(self.assessment_a).summary
        self.assertEqual(summary.complete_results, 0)
        self.assertIsNone(summary.average_percentage)

    def test_question_gap_counts_are_correct(self):
        self.grade_fixture()
        gaps = {
            gap.question_id: gap
            for gap in build_class_insights(self.assessment_a).question_gaps
        }
        q1 = gaps[self.q1.id]
        q2 = gaps[self.q2.id]
        self.assertEqual(q1.correct_count, 3)
        self.assertEqual(q1.partial_count, 0)
        self.assertEqual(q1.incorrect_count, 1)
        self.assertEqual(q1.gap_count, 1)
        self.assertEqual(q2.correct_count, 1)
        self.assertEqual(q2.partial_count, 1)
        self.assertEqual(q2.incorrect_count, 1)
        self.assertEqual(q2.gap_count, 2)

    def test_gap_percentage_is_correct(self):
        self.grade_fixture()
        gaps = {
            gap.question_id: gap
            for gap in build_class_insights(self.assessment_a).question_gaps
        }
        self.assertEqual(gaps[self.q1.id].gap_percentage, Decimal("25.00"))
        self.assertEqual(gaps[self.q2.id].gap_percentage, Decimal("66.67"))

    def test_unevaluated_student_is_excluded_from_question_denominator(self):
        self.grade_fixture()
        q2 = next(
            gap
            for gap in build_class_insights(self.assessment_a).question_gaps
            if gap.question_id == self.q2.id
        )
        self.assertEqual(q2.evaluated_students, 3)

    def test_gaps_are_ordered_highest_first(self):
        self.grade_fixture()
        gaps = build_class_insights(self.assessment_a).question_gaps
        self.assertEqual(gaps[0].question_id, self.q2.id)
        self.assertEqual(gaps[1].question_id, self.q1.id)

    def test_misconceptions_are_counted(self):
        self.grade_fixture()
        texts = {
            item.text: item.count
            for item in build_class_insights(self.assessment_a).misconceptions
        }
        self.assertEqual(texts["خلط المقام"], 2)
        self.assertEqual(texts["نسي التبسيط"], 1)

    def test_exact_duplicate_misconception_is_aggregated(self):
        self.grade_fixture()
        items = build_class_insights(self.assessment_a).misconceptions
        self.assertEqual(items[0].text, "خلط المقام")
        self.assertEqual(items[0].count, 2)
        self.assertEqual(len([item for item in items if item.text == "خلط المقام"]), 1)

    def test_foundation_grouping(self):
        self.grade_fixture()
        members = build_class_insights(self.assessment_a).groups.foundation
        self.assertEqual(len(members), 1)
        self.assertEqual(members[0].student_id, self.foundation_student.id)
        self.assertEqual(members[0].percentage, Decimal("50.00"))
        self.assertEqual(members[0].group, GROUP_FOUNDATION)
        self.assertEqual(members[0].student_code, "S-001")

    def test_practice_grouping(self):
        self.grade_fixture()
        members = build_class_insights(self.assessment_a).groups.practice
        self.assertEqual(len(members), 1)
        self.assertEqual(members[0].student_id, self.practice_student.id)
        self.assertEqual(members[0].percentage, Decimal("70.00"))
        self.assertEqual(members[0].group, GROUP_PRACTICE)

    def test_ready_grouping(self):
        self.grade_fixture()
        members = build_class_insights(self.assessment_a).groups.ready
        self.assertEqual(len(members), 1)
        self.assertEqual(members[0].student_id, self.ready_student.id)
        self.assertEqual(members[0].percentage, Decimal("100.00"))
        self.assertEqual(members[0].group, GROUP_READY)

    def test_incomplete_students_are_excluded_from_groups(self):
        self.grade_fixture()
        insights = build_class_insights(self.assessment_a)
        grouped_ids = {
            member.student_id
            for members in (
                insights.groups.foundation,
                insights.groups.practice,
                insights.groups.ready,
            )
            for member in members
        }
        self.assertNotIn(self.pending_student.id, grouped_ids)
        self.assertNotIn(self.absent_student.id, grouped_ids)
        self.assertEqual(
            insights.pending_students[0].reason, PENDING_INCOMPLETE_EVALUATION
        )

    def test_teacher_can_read_own_assessment_insights(self):
        self.grade_fixture()
        self.authenticate(self.teacher_a)
        response = self.client.get(self.insights_url(self.assessment_a))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["summary"]["complete_results"], 3)
        self.assertEqual(response.data["summary"]["average_percentage"], Decimal("73.33"))
        self.assertEqual(len(response.data["groups"]["foundation"]), 1)
        self.assertEqual(len(response.data["pending_students"]), 1)

    def test_teacher_cannot_read_another_teachers_insights(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(self.insights_url(self.assessment_b))
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_manager_can_read_all(self):
        self.authenticate(self.manager)
        response = self.client.get(self.insights_url(self.assessment_b))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["summary"]["total_students_in_class"], 1)
        self.assertEqual(response.data["summary"]["students_with_submission"], 1)
        self.assertIsNone(response.data["summary"]["average_percentage"])
        self.assertEqual(response.data["summary"]["complete_results"], 0)
        self.assertEqual(response.data["pending_students"][0]["reason"], PENDING_NO_QUESTIONS)

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get(self.insights_url(self.assessment_a))
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get(self.insights_url(self.assessment_a))
        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )

    def test_assessment_with_no_submissions_is_safe(self):
        empty = Assessment.objects.create(
            classroom=self.class_a,
            title="اختبار فارغ",
            created_by=self.teacher_a,
        )
        Question.objects.create(
            assessment=empty,
            order=1,
            text="سؤال",
            max_score=Decimal("5"),
            model_answer="1",
        )
        insights = build_class_insights(empty)
        self.assertEqual(insights.summary.students_with_submission, 0)
        self.assertEqual(insights.summary.complete_results, 0)
        self.assertIsNone(insights.summary.average_percentage)
        self.assertEqual(insights.question_gaps[0].evaluated_students, 0)
        self.assertIsNone(insights.question_gaps[0].gap_percentage)
        self.assertEqual(insights.misconceptions, ())
        self.assertEqual(insights.groups.foundation, ())

    def test_assessment_with_no_questions_is_safe(self):
        insights = build_class_insights(self.assessment_b)
        self.assertEqual(insights.summary.students_with_submission, 1)
        self.assertEqual(insights.summary.complete_results, 0)
        self.assertEqual(insights.summary.incomplete_results, 1)
        self.assertIsNone(insights.summary.average_percentage)
        self.assertEqual(insights.question_gaps, ())
        self.assertEqual(insights.misconceptions, ())
        self.assertEqual(insights.groups.foundation, ())
        self.assertEqual(insights.groups.practice, ())
        self.assertEqual(insights.groups.ready, ())
        self.assertEqual(insights.pending_students[0].reason, PENDING_NO_QUESTIONS)
