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
from apps.assessments.services.results import build_submission_result
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


class SubmissionResultTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="result-manager", password="strong-pass-123"
            ),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="result-teacher-a", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="result-teacher-b", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.class_a = make_classroom(self.teacher_a, "سادس أ")
        self.class_b = make_classroom(self.teacher_b, "خامس أ", subject="العلوم")
        self.assessment_a = Assessment.objects.create(
            classroom=self.class_a, title="اختبار الكسور", created_by=self.teacher_a
        )
        self.assessment_b = Assessment.objects.create(
            classroom=self.class_b, title="اختبار الخلية", created_by=self.teacher_b
        )
        self.q1 = Question.objects.create(
            assessment=self.assessment_a,
            order=1,
            text="ما ناتج 1/2 + 1/4؟",
            max_score=Decimal("2"),
            model_answer="3/4",
        )
        self.q2 = Question.objects.create(
            assessment=self.assessment_a,
            order=2,
            text="بسّط الكسر 4/8",
            max_score=Decimal("3"),
            model_answer="1/2",
        )
        self.q3 = Question.objects.create(
            assessment=self.assessment_a,
            order=3,
            text="حوّل 0.5 إلى كسر",
            max_score=Decimal("5"),
            model_answer="1/2",
        )
        self.student_a = Student.objects.create(
            classroom=self.class_a, internal_code="S-001", display_name="طالب أ"
        )
        self.student_b = Student.objects.create(
            classroom=self.class_b, internal_code="S-900", display_name="طالب ب"
        )
        self.submission_a = Submission.objects.create(
            assessment=self.assessment_a, student=self.student_a
        )
        self.submission_b = Submission.objects.create(
            assessment=self.assessment_b, student=self.student_b
        )
        self.answer_1 = SubmissionAnswer.objects.create(
            submission=self.submission_a, question=self.q1, answer_text="3/4"
        )
        self.answer_2 = SubmissionAnswer.objects.create(
            submission=self.submission_a, question=self.q2, answer_text="1/4"
        )
        self.answer_3 = SubmissionAnswer.objects.create(
            submission=self.submission_a, question=self.q3, answer_text="0.5"
        )

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def result_url(self, assessment, submission):
        return (
            f"/api/v1/assessments/{assessment.id}/submissions/"
            f"{submission.id}/result/"
        )

    def answers_url(self, assessment, submission):
        return (
            f"/api/v1/assessments/{assessment.id}/submissions/"
            f"{submission.id}/answers/"
        )

    def fully_grade(self):
        grade(
            self.answer_1,
            AnswerEvaluation.Status.CORRECT,
            2,
            "صحيحة.",
            misconception="",
        )
        grade(
            self.answer_2,
            AnswerEvaluation.Status.PARTIAL,
            Decimal("1.5"),
            "ناقص.",
            misconception="خلط المقام",
        )
        grade(
            self.answer_3,
            AnswerEvaluation.Status.INCORRECT,
            0,
            "خطأ.",
            misconception="خلط المقام",
        )

    def test_fully_evaluated_submission_returns_correct_totals(self):
        self.fully_grade()
        result = build_submission_result(self.submission_a)
        self.assertTrue(result.is_complete)
        self.assertEqual(result.awarded_score_total, Decimal("3.50"))
        self.assertEqual(result.max_score_total, Decimal("10"))
        self.assertEqual(result.percentage, Decimal("35.00"))
        self.assertEqual(result.evaluated_questions, 3)
        self.assertEqual(result.total_questions, 3)
        self.assertEqual(result.unevaluated_count, 0)

    def test_status_counts_are_accurate(self):
        self.fully_grade()
        result = build_submission_result(self.submission_a)
        self.assertEqual(result.correct_count, 1)
        self.assertEqual(result.partial_count, 1)
        self.assertEqual(result.incorrect_count, 1)

    def test_unevaluated_questions_are_counted_separately(self):
        grade(self.answer_1, AnswerEvaluation.Status.CORRECT, 2, "صحيحة.")
        result = build_submission_result(self.submission_a)
        self.assertFalse(result.is_complete)
        self.assertEqual(result.evaluated_questions, 1)
        self.assertEqual(result.unevaluated_count, 2)
        self.assertEqual(result.incorrect_count, 0)

    def test_is_complete_only_when_every_question_is_evaluated(self):
        grade(self.answer_1, AnswerEvaluation.Status.CORRECT, 2, "صحيحة.")
        grade(self.answer_2, AnswerEvaluation.Status.INCORRECT, 0, "خطأ.")
        self.assertFalse(build_submission_result(self.submission_a).is_complete)
        grade(self.answer_3, AnswerEvaluation.Status.CORRECT, 5, "صحيحة.")
        self.assertTrue(build_submission_result(self.submission_a).is_complete)

    def test_incomplete_percentage_uses_evaluated_max_only(self):
        grade(self.answer_1, AnswerEvaluation.Status.CORRECT, 2, "صحيحة.")
        result = build_submission_result(self.submission_a)
        self.assertFalse(result.is_complete)
        self.assertEqual(result.percentage, Decimal("100.00"))
        self.assertEqual(result.awarded_score_total, Decimal("2"))
        self.assertEqual(result.max_score_total, Decimal("10"))

    def test_awarded_total_never_exceeds_max_total(self):
        self.fully_grade()
        result = build_submission_result(self.submission_a)
        self.assertLessEqual(result.awarded_score_total, result.max_score_total)

    def test_gaps_include_partial_and_incorrect_only(self):
        self.fully_grade()
        result = build_submission_result(self.submission_a)
        statuses = [gap.status for gap in result.gaps]
        self.assertEqual(statuses, ["partial", "incorrect"])
        self.assertEqual(result.gaps[0].question_order, 2)
        self.assertEqual(result.gaps[1].question_order, 3)

    def test_correct_questions_are_excluded_from_gaps(self):
        self.fully_grade()
        ids = {
            str(gap.question_id)
            for gap in build_submission_result(self.submission_a).gaps
        }
        self.assertNotIn(str(self.q1.id), ids)

    def test_misconceptions_skip_blanks_and_dedupe_exact_text(self):
        self.fully_grade()
        result = build_submission_result(self.submission_a)
        self.assertEqual(result.misconceptions, ("خلط المقام",))

    def test_question_without_an_answer_is_unevaluated_not_a_gap(self):
        self.answer_3.delete()
        grade(self.answer_1, AnswerEvaluation.Status.CORRECT, 2, "صحيحة.")
        grade(self.answer_2, AnswerEvaluation.Status.INCORRECT, 0, "خطأ.")
        result = build_submission_result(self.submission_a)
        self.assertEqual(result.unevaluated_count, 1)
        self.assertEqual(len(result.gaps), 1)
        self.assertFalse(result.is_complete)

    def test_editing_an_answer_drops_stale_evaluation_from_the_result(self):
        self.fully_grade()
        self.authenticate(self.teacher_a)
        response = self.client.put(
            self.answers_url(self.assessment_a, self.submission_a),
            {
                "answers": [
                    {"question_id": str(self.q1.id), "answer_text": "إجابة جديدة"},
                    {"question_id": str(self.q2.id), "answer_text": "1/4"},
                    {"question_id": str(self.q3.id), "answer_text": "0.5"},
                ]
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        result = self.client.get(
            self.result_url(self.assessment_a, self.submission_a)
        )
        self.assertFalse(result.data["is_complete"])
        self.assertEqual(result.data["evaluated_questions"], 2)
        self.assertEqual(result.data["unevaluated_count"], 1)
        self.assertEqual(result.data["correct_count"], 0)

    def test_re_evaluation_updates_the_result(self):
        evaluation = grade(
            self.answer_1, AnswerEvaluation.Status.INCORRECT, 0, "خطأ."
        )
        before = build_submission_result(self.submission_a)
        self.assertEqual(before.incorrect_count, 1)
        evaluation.status = AnswerEvaluation.Status.CORRECT
        evaluation.awarded_score = Decimal("2")
        evaluation.feedback = "صحيحة بعد المراجعة."
        evaluation.save()
        after = build_submission_result(self.submission_a)
        self.assertEqual(after.correct_count, 1)
        self.assertEqual(after.incorrect_count, 0)
        self.assertEqual(after.awarded_score_total, Decimal("2"))

    def test_teacher_can_read_own_result(self):
        self.fully_grade()
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.result_url(self.assessment_a, self.submission_a)
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["is_complete"])
        self.assertEqual(response.data["awarded_score_total"], 3.5)
        self.assertEqual(len(response.data["gaps"]), 2)
        self.assertEqual(response.data["misconceptions"], ["خلط المقام"])

    def test_teacher_cannot_read_another_teachers_result(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.result_url(self.assessment_b, self.submission_b)
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_manager_can_read_all(self):
        self.authenticate(self.manager)
        response = self.client.get(
            self.result_url(self.assessment_b, self.submission_b)
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["total_questions"], 0)
        self.assertFalse(response.data["is_complete"])
        self.assertFalse(response.data["is_evaluable"])

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.result_url(self.assessment_a, self.submission_a)
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get(
            self.result_url(self.assessment_a, self.submission_a)
        )
        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )

    def test_assessment_with_no_questions_is_not_complete(self):
        result = build_submission_result(self.submission_b)
        self.assertFalse(result.is_evaluable)
        self.assertFalse(result.is_complete)
        self.assertEqual(result.total_questions, 0)
        self.assertEqual(result.awarded_score_total, Decimal("0.00"))
        self.assertEqual(result.max_score_total, Decimal("0.00"))
        self.assertEqual(result.percentage, Decimal("0.00"))
        self.assertEqual(result.gaps, ())
        self.assertEqual(result.misconceptions, ())
