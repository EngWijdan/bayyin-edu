from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import UserProfile
from apps.assessments.models import (
    AnswerEvaluation,
    Assessment,
    Question,
    RemediationPlan,
    Submission,
    SubmissionAnswer,
)
from apps.assessments.services.gemini import GeminiRemediationProvider
from apps.assessments.services.remediation import (
    GENERIC_FAILURE,
    GROUP_FOCUS,
    INVALID_GROUP,
    RemediationError,
    build_remediation_request,
    generate_remediation_plan,
    parse_provider_payload,
)
from apps.classrooms.models import Student

from .tests import make_classroom


def grade(answer, eval_status, score, feedback="ملاحظات.", misconception=""):
    return AnswerEvaluation.objects.create(
        answer=answer,
        status=eval_status,
        awarded_score=Decimal(str(score)),
        feedback=feedback,
        misconception=misconception,
        model_name="fake-model",
        evaluated_at=timezone.now(),
    )


def plan_payload(**overrides):
    data = {
        "title": "خطة تأسيس الكسور",
        "summary": "بناء مفهوم الكسر من المحسوس إلى الرمز.",
        "objectives": ["يفهم معنى المقام", "يجمع كسرين بوحدة"],
        "activities": [
            {
                "title": "أمثلة موجهة",
                "description": "حل مثالين مع المعلم.",
                "duration_minutes": 15,
            }
        ],
        "teacher_guidance": "ابدأ بالمحسوس ثم انتقل إلى الرمز.",
    }
    data.update(overrides)
    return data


class FakeProvider:
    def __init__(self, payload=None, error=None):
        self.payload = payload if payload is not None else plan_payload()
        self.error = error
        self.calls = []
        self.model_name = "fake-model"

    def complete(self, request):
        self.calls.append(request)
        if self.error is not None:
            raise self.error
        if callable(self.payload):
            return self.payload(request)
        return self.payload


class RemediationFixtureMixin:
    def setUp(self):
        super().setUp()
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="plan-manager", password="strong-pass-123"
            ),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="plan-teacher-a", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="plan-teacher-b", password="strong-pass-123"
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
        for submission in (
            self.foundation_sub,
            self.practice_sub,
            self.ready_sub,
            self.pending_sub,
        ):
            SubmissionAnswer.objects.create(
                submission=submission, question=self.q1, answer_text="3/4"
            )
            SubmissionAnswer.objects.create(
                submission=submission, question=self.q2, answer_text="4/8"
            )
        Submission.objects.create(
            assessment=self.assessment_b, student=self.other_student
        )

    def grade_fixture(self):
        grade(
            self.foundation_sub.answers.get(question=self.q1),
            AnswerEvaluation.Status.INCORRECT,
            0,
            misconception="خلط المقام",
        )
        grade(
            self.foundation_sub.answers.get(question=self.q2),
            AnswerEvaluation.Status.CORRECT,
            10,
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
            misconception="جمع البسط فقط",
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


class RemediationServiceTests(RemediationFixtureMixin, TestCase):
    def test_foundation_plan_is_generated(self):
        self.grade_fixture()
        provider = FakeProvider(
            plan_payload(title="خطة تأسيس", teacher_guidance="بسّط المهارة.")
        )
        result = generate_remediation_plan(
            self.assessment_a, "foundation", provider
        )
        self.assertFalse(result.group_empty)
        self.assertEqual(result.plan.group, RemediationPlan.Group.FOUNDATION)
        self.assertEqual(result.plan.title, "خطة تأسيس")
        self.assertEqual(result.plan.status, RemediationPlan.Status.COMPLETED)
        self.assertEqual(provider.calls[0].group, "foundation")
        self.assertIn("Foundation", provider.calls[0].focus)

    def test_practice_plan_is_generated(self):
        self.grade_fixture()
        result = generate_remediation_plan(
            self.assessment_a, "practice", FakeProvider(plan_payload(title="تدريب"))
        )
        self.assertEqual(result.plan.group, "practice")
        self.assertEqual(result.plan.title, "تدريب")

    def test_ready_plan_is_generated(self):
        self.grade_fixture()
        provider = FakeProvider(plan_payload(title="إثراء"))
        result = generate_remediation_plan(self.assessment_a, "ready", provider)
        self.assertEqual(result.plan.group, "ready")
        self.assertIn("Ready", provider.calls[0].focus)
        self.assertIn("enrichment", provider.calls[0].focus.lower())
        self.assertNotEqual(provider.calls[0].focus, GROUP_FOCUS["foundation"])

    def test_empty_group_skips_gemini(self):
        self.grade_fixture()
        self.ready_sub.delete()
        provider = FakeProvider()
        result = generate_remediation_plan(self.assessment_a, "ready", provider)
        self.assertTrue(result.group_empty)
        self.assertIsNone(result.plan)
        self.assertEqual(provider.calls, [])
        self.assertEqual(RemediationPlan.objects.count(), 0)

    def test_no_questions_assessment_does_not_generate_a_plan(self):
        provider = FakeProvider()
        result = generate_remediation_plan(
            self.assessment_b, "foundation", provider
        )
        self.assertTrue(result.group_empty)
        self.assertIsNone(result.plan)
        self.assertEqual(provider.calls, [])
        self.assertEqual(RemediationPlan.objects.count(), 0)

    def test_invalid_group_is_rejected(self):
        self.grade_fixture()
        with self.assertRaises(RemediationError) as caught:
            generate_remediation_plan(
                self.assessment_a, "advanced", FakeProvider()
            )
        self.assertEqual(str(caught.exception), INVALID_GROUP)
        self.assertEqual(RemediationPlan.objects.count(), 0)

    def test_structured_response_is_saved(self):
        self.grade_fixture()
        result = generate_remediation_plan(
            self.assessment_a, "foundation", FakeProvider()
        )
        self.assertEqual(result.plan.objectives, ["يفهم معنى المقام", "يجمع كسرين بوحدة"])
        self.assertEqual(result.plan.activities[0]["title"], "أمثلة موجهة")
        self.assertEqual(result.plan.activities[0]["duration_minutes"], 15)
        self.assertEqual(result.plan.model_name, "fake-model")
        self.assertIsNotNone(result.plan.generated_at)

    def test_malformed_provider_response_is_rejected(self):
        self.grade_fixture()
        with self.assertRaises(RemediationError):
            generate_remediation_plan(
                self.assessment_a, "foundation", FakeProvider(["not", "a", "dict"])
            )
        self.assertEqual(RemediationPlan.objects.count(), 0)

    def test_provider_error_is_handled_safely(self):
        self.grade_fixture()
        with self.assertRaises(RemediationError) as caught:
            generate_remediation_plan(
                self.assessment_a,
                "foundation",
                FakeProvider(error=RuntimeError("gemini timeout secret")),
            )
        self.assertEqual(str(caught.exception), GENERIC_FAILURE)
        self.assertEqual(RemediationPlan.objects.count(), 0)

    def test_regeneration_updates_the_same_row(self):
        self.grade_fixture()
        first = generate_remediation_plan(
            self.assessment_a, "practice", FakeProvider(plan_payload(title="أولى"))
        ).plan
        second = generate_remediation_plan(
            self.assessment_a, "practice", FakeProvider(plan_payload(title="ثانية"))
        ).plan
        self.assertEqual(first.id, second.id)
        self.assertEqual(second.title, "ثانية")
        self.assertEqual(
            RemediationPlan.objects.filter(
                assessment=self.assessment_a, group="practice"
            ).count(),
            1,
        )

    def test_no_duplicate_plan_rows(self):
        self.grade_fixture()
        generate_remediation_plan(self.assessment_a, "foundation", FakeProvider())
        generate_remediation_plan(self.assessment_a, "foundation", FakeProvider())
        self.assertEqual(RemediationPlan.objects.count(), 1)

    def test_academic_context_is_sent(self):
        self.grade_fixture()
        request = build_remediation_request(self.assessment_a, "foundation")
        self.assertEqual(request.subject, "الرياضيات")
        self.assertEqual(request.grade, "الصف السادس")
        self.assertEqual(request.assessment_title, "اختبار الكسور")
        self.assertEqual(request.group_size, 1)
        self.assertEqual(request.percentage_min, Decimal("50.00"))
        self.assertEqual(len(request.highest_gap_questions), 1)
        self.assertEqual(request.highest_gap_questions[0].question_order, 1)
        self.assertEqual(request.highest_gap_questions[0].model_answer, "3/4")
        self.assertEqual(request.highest_gap_questions[0].incorrect_count, 1)
        self.assertEqual(request.highest_gap_questions[0].partial_count, 0)
        self.assertTrue(any(item.text == "خلط المقام" for item in request.misconceptions))

    def test_no_student_identifying_data_is_sent(self):
        self.grade_fixture()
        provider = FakeProvider()
        generate_remediation_plan(self.assessment_a, "foundation", provider)
        blob = str(provider.calls[0])
        self.assertNotIn("طالب تأسيس", blob)
        self.assertNotIn("طالب تدريب", blob)
        self.assertNotIn("S-001", blob)
        self.assertNotIn("S-002", blob)
        self.assertNotIn("S-004", blob)
        self.assertNotIn("plan-teacher-a", blob)
        self.assertNotIn("plan-manager", blob)

    def test_foundation_context_uses_foundation_gaps_only(self):
        self.grade_fixture()
        provider = FakeProvider()
        generate_remediation_plan(self.assessment_a, "foundation", provider)
        request = provider.calls[0]
        texts = [item.question_text for item in request.highest_gap_questions]
        self.assertEqual(texts, ["ما ناتج 1/2 + 1/4؟"])
        self.assertEqual(request.highest_gap_questions[0].gap_percentage, Decimal("100.00"))
        self.assertEqual([item.text for item in request.misconceptions], ["خلط المقام"])

    def test_practice_context_excludes_foundation_only_gap(self):
        self.grade_fixture()
        provider = FakeProvider()
        generate_remediation_plan(self.assessment_a, "practice", provider)
        request = provider.calls[0]
        texts = [item.question_text for item in request.highest_gap_questions]
        self.assertEqual(texts, ["بسّط الكسر 4/8"])
        self.assertNotIn("ما ناتج 1/2 + 1/4؟", texts)
        self.assertEqual([item.text for item in request.misconceptions], ["جمع البسط فقط"])
        self.assertNotIn("خلط المقام", [item.text for item in request.misconceptions])

    def test_ready_context_excludes_other_groups_misconceptions(self):
        self.grade_fixture()
        provider = FakeProvider()
        generate_remediation_plan(self.assessment_a, "ready", provider)
        request = provider.calls[0]
        self.assertEqual(request.highest_gap_questions, ())
        self.assertEqual(request.misconceptions, ())

    def test_pending_students_are_excluded_from_group_context(self):
        self.grade_fixture()
        for group in ("foundation", "practice", "ready"):
            request = build_remediation_request(self.assessment_a, group)
            texts = [item.text for item in request.misconceptions]
            self.assertNotIn("نسي التبسيط", texts)
            blob = str(request)
            self.assertNotIn("طالب معلق", blob)
            self.assertNotIn("S-004", blob)

    def test_group_averages_use_group_members_only(self):
        self.grade_fixture()
        extra = Student.objects.create(
            classroom=self.class_a, internal_code="S-011", display_name="طالب تأسيس ب"
        )
        submission = Submission.objects.create(
            assessment=self.assessment_a, student=extra
        )
        a1 = SubmissionAnswer.objects.create(
            submission=submission, question=self.q1, answer_text=""
        )
        a2 = SubmissionAnswer.objects.create(
            submission=submission, question=self.q2, answer_text=""
        )
        grade(a1, AnswerEvaluation.Status.INCORRECT, 0, misconception="خلط المقام")
        grade(a2, AnswerEvaluation.Status.INCORRECT, 0)
        request = build_remediation_request(self.assessment_a, "foundation")
        self.assertEqual(request.group_size, 2)
        self.assertEqual(request.percentage_min, Decimal("0.00"))
        self.assertEqual(request.percentage_max, Decimal("50.00"))
        self.assertEqual(request.percentage_average, Decimal("25.00"))
        self.assertNotEqual(request.percentage_average, Decimal("73.33"))
        q1 = request.highest_gap_questions[0]
        self.assertEqual(q1.question_order, 1)
        self.assertEqual(q1.incorrect_count, 2)
        self.assertEqual(q1.gap_count, 2)

    def test_foundation_gemini_prompt_contains_only_group_gaps(self):
        from apps.assessments.test_evaluation import (
            _FakeGeminiClient,
            _FakeGeminiResponse,
        )

        self.grade_fixture()
        request = build_remediation_request(self.assessment_a, "foundation")
        client = _FakeGeminiClient(_FakeGeminiResponse(parsed=plan_payload()))
        GeminiRemediationProvider(client=client).complete(request)
        prompt = client.models.kwargs["contents"]
        self.assertIn("ما ناتج 1/2 + 1/4؟", prompt)
        self.assertNotIn("بسّط الكسر 4/8", prompt)
        self.assertIn("خلط المقام", prompt)
        self.assertNotIn("جمع البسط فقط", prompt)
        self.assertNotIn("نسي التبسيط", prompt)
        self.assertNotIn("طالب تأسيس", prompt)
        self.assertNotIn("S-001", prompt)

    def test_locale_ar_is_passed(self):
        self.grade_fixture()
        provider = FakeProvider()
        generate_remediation_plan(
            self.assessment_a, "foundation", provider, locale="ar"
        )
        self.assertEqual(provider.calls[0].locale, "ar")

    def test_locale_en_is_passed(self):
        self.grade_fixture()
        provider = FakeProvider()
        generate_remediation_plan(
            self.assessment_a, "practice", provider, locale="en"
        )
        self.assertEqual(provider.calls[0].locale, "en")

    def test_invalid_locale_falls_back_to_arabic(self):
        self.grade_fixture()
        provider = FakeProvider()
        generate_remediation_plan(
            self.assessment_a, "foundation", provider, locale="en-US"
        )
        self.assertEqual(provider.calls[0].locale, "ar")


class ParseRemediationPayloadTests(TestCase):
    def test_missing_objectives_are_rejected(self):
        with self.assertRaises(RemediationError):
            parse_provider_payload(plan_payload(objectives=[]))

    def test_non_dict_is_rejected(self):
        with self.assertRaises(RemediationError):
            parse_provider_payload("not-json")


class RemediationApiTests(RemediationFixtureMixin, APITestCase):
    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def list_url(self, assessment):
        return f"/api/v1/assessments/{assessment.id}/remediation-plans/"

    def generate_url(self, assessment, group):
        return (
            f"/api/v1/assessments/{assessment.id}/"
            f"remediation-plans/{group}/generate/"
        )

    @patch("apps.assessments.services.remediation.get_remediation_provider")
    def test_teacher_can_access_own_assessment(self, get_provider):
        self.grade_fixture()
        get_provider.return_value = FakeProvider()
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.generate_url(self.assessment_a, "foundation"),
            {"locale": "ar"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["group_empty"])
        self.assertEqual(response.data["plan"]["title"], "خطة تأسيس الكسور")
        listed = self.client.get(self.list_url(self.assessment_a))
        self.assertEqual(listed.status_code, status.HTTP_200_OK)
        self.assertEqual(len(listed.data), 1)

    def test_teacher_cannot_access_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(self.list_url(self.assessment_b))
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        response = self.client.post(
            self.generate_url(self.assessment_b, "foundation"), format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_manager_can_access_all(self):
        self.authenticate(self.manager)
        response = self.client.get(self.list_url(self.assessment_b))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [])

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get(self.list_url(self.assessment_a))
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get(self.list_url(self.assessment_a))
        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )

    def test_invalid_group_is_rejected_by_api(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.generate_url(self.assessment_a, "stars"), format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    @patch("apps.assessments.services.remediation.get_remediation_provider")
    def test_empty_group_skips_provider_on_api(self, get_provider):
        self.grade_fixture()
        self.ready_sub.delete()
        provider = FakeProvider()
        get_provider.return_value = provider
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.generate_url(self.assessment_a, "ready"), format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["group_empty"])
        self.assertIsNone(response.data["plan"])
        self.assertEqual(provider.calls, [])

    @patch("apps.assessments.services.remediation.get_remediation_provider")
    def test_locale_en_is_forwarded(self, get_provider):
        self.grade_fixture()
        provider = FakeProvider()
        get_provider.return_value = provider
        self.authenticate(self.teacher_a)
        self.client.post(
            self.generate_url(self.assessment_a, "practice"),
            {"locale": "en"},
            format="json",
        )
        self.assertEqual(provider.calls[0].locale, "en")


class GeminiRemediationProviderTests(TestCase):
    def setUp(self):
        from apps.assessments.services.remediation import (
            RemediationMisconception,
            RemediationQuestionContext,
            RemediationRequest,
        )

        self.request = RemediationRequest(
            locale="ar",
            subject="الرياضيات",
            grade="الصف السادس",
            assessment_title="اختبار الكسور",
            group="foundation",
            group_size=2,
            percentage_min=Decimal("40"),
            percentage_max=Decimal("55"),
            percentage_average=Decimal("47.50"),
            highest_gap_questions=(
                RemediationQuestionContext(
                    question_order=2,
                    question_text="بسّط الكسر 4/8",
                    model_answer="1/2",
                    max_score=Decimal("10"),
                    partial_count=1,
                    incorrect_count=1,
                    gap_count=2,
                    gap_percentage=Decimal("66.67"),
                ),
            ),
            misconceptions=(
                RemediationMisconception(text="خلط المقام", count=2),
            ),
            focus=GROUP_FOCUS["foundation"],
        )

    def test_prompt_is_academic_only(self):
        from apps.assessments.test_evaluation import (
            _FakeGeminiClient,
            _FakeGeminiResponse,
        )

        client = _FakeGeminiClient(_FakeGeminiResponse(parsed=plan_payload()))
        GeminiRemediationProvider(client=client).complete(self.request)
        prompt = client.models.kwargs["contents"]
        self.assertIn("اختبار الكسور", prompt)
        self.assertIn("بسّط الكسر 4/8", prompt)
        self.assertIn("1/2", prompt)
        self.assertIn("خلط المقام", prompt)
        self.assertIn("Locale: ar", prompt)
        self.assertNotIn("طالب", prompt)
        self.assertNotIn("S-001", prompt)
        schema = client.models.kwargs["config"]["response_schema"]
        self.assertEqual(schema["required"][-1], "teacher_guidance")

    def test_malformed_json_is_a_safe_error(self):
        from apps.assessments.test_evaluation import (
            _FakeGeminiClient,
            _FakeGeminiResponse,
        )

        client = _FakeGeminiClient(_FakeGeminiResponse(parsed=None, text="not-json"))
        with self.assertRaises(RemediationError) as caught:
            GeminiRemediationProvider(client=client).complete(self.request)
        self.assertEqual(str(caught.exception), GENERIC_FAILURE)

    @override_settings(GEMINI_API_KEY="")
    def test_missing_api_key_does_not_call_the_sdk(self):
        with self.assertRaises(RemediationError) as caught:
            GeminiRemediationProvider().complete(self.request)
        self.assertEqual(str(caught.exception), GENERIC_FAILURE)
