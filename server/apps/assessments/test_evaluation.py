from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import UserProfile
from apps.assessments.models import (
    AnswerEvaluation,
    Assessment,
    OcrAnswerCandidate,
    Question,
    Submission,
    SubmissionAnswer,
)
from apps.assessments.services.evaluation import (
    GENERIC_FAILURE,
    NO_CONFIRMED_ANSWERS,
    EMPTY_FEEDBACK,
    EvaluationError,
    EvaluationRequest,
    evaluate_answer,
    evaluate_answers,
    locale_from_request_data,
    normalize_locale,
    parse_provider_payload,
    request_from_answer,
)
from apps.assessments.services.gemini import GeminiEvaluationProvider
from apps.classrooms.models import Student

from .tests import make_classroom


class FakeProvider:
    def __init__(self, payload=None, error=None):
        self.payload = payload
        self.error = error
        self.calls = []
        self.model_name = "fake-model"

    def complete(self, request):
        self.calls.append(request)
        if self.error is not None:
            raise self.error
        return self.payload


def payload(*, status="correct", awarded_score=2, feedback="الإجابة صحيحة.", misconception=""):
    return {
        "status": status,
        "awarded_score": awarded_score,
        "feedback": feedback,
        "misconception": misconception,
    }


class EvaluationServiceTests(TestCase):
    def setUp(self):
        teacher = UserProfile.objects.create(
            user=get_user_model().objects.create_user(
                username="eval-teacher", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        classroom = make_classroom(teacher, "سادس أ")
        self.assessment = Assessment.objects.create(
            classroom=classroom, title="اختبار الكسور"
        )
        self.question = Question.objects.create(
            assessment=self.assessment,
            order=1,
            text="ما ناتج 1/2 + 1/4؟",
            max_score=Decimal("2"),
            model_answer="3/4",
        )
        self.submission = Submission.objects.create(
            assessment=self.assessment,
            student=Student.objects.create(
                classroom=classroom,
                internal_code="S-001",
                display_name="طالب أ",
            ),
        )
        self.answer = SubmissionAnswer.objects.create(
            submission=self.submission,
            question=self.question,
            answer_text="3/4",
        )

    def test_correct_response_is_saved(self):
        evaluation = evaluate_answer(self.answer, FakeProvider(payload()))
        self.assertEqual(evaluation.status, AnswerEvaluation.Status.CORRECT)
        self.assertEqual(evaluation.awarded_score, Decimal("2.00"))
        self.assertEqual(evaluation.feedback, "الإجابة صحيحة.")
        self.assertEqual(evaluation.misconception, "")
        self.assertEqual(evaluation.model_name, "fake-model")

    def test_partial_response_is_saved(self):
        evaluation = evaluate_answer(
            self.answer,
            FakeProvider(
                payload(
                    status="partial",
                    awarded_score=1,
                    feedback="ناقص.",
                    misconception="خلط المقام",
                )
            ),
        )
        self.assertEqual(evaluation.status, AnswerEvaluation.Status.PARTIAL)
        self.assertEqual(evaluation.awarded_score, Decimal("1.00"))
        self.assertEqual(evaluation.misconception, "خلط المقام")

    def test_incorrect_response_is_saved(self):
        evaluation = evaluate_answer(
            self.answer,
            FakeProvider(payload(status="incorrect", awarded_score=0, feedback="خطأ.")),
        )
        self.assertEqual(evaluation.status, AnswerEvaluation.Status.INCORRECT)
        self.assertEqual(evaluation.awarded_score, Decimal("0.00"))

    def test_empty_answer_skips_the_provider(self):
        self.answer.answer_text = "   "
        self.answer.save(update_fields=["answer_text"])
        provider = FakeProvider(payload())
        evaluation = evaluate_answer(self.answer, provider)
        self.assertEqual(provider.calls, [])
        self.assertEqual(evaluation.status, AnswerEvaluation.Status.INCORRECT)
        self.assertEqual(evaluation.awarded_score, Decimal("0.00"))
        self.assertEqual(evaluation.feedback, EMPTY_FEEDBACK)
        self.assertEqual(evaluation.misconception, "")
        self.assertEqual(evaluation.model_name, "deterministic")

    def test_score_above_max_is_rejected(self):
        with self.assertRaises(EvaluationError):
            evaluate_answer(
                self.answer, FakeProvider(payload(awarded_score=9, status="correct"))
            )
        self.assertFalse(AnswerEvaluation.objects.filter(answer=self.answer).exists())

    def test_negative_score_is_rejected(self):
        with self.assertRaises(EvaluationError):
            evaluate_answer(
                self.answer,
                FakeProvider(payload(status="incorrect", awarded_score=-1, feedback="x")),
            )
        self.assertFalse(AnswerEvaluation.objects.filter(answer=self.answer).exists())

    def test_invalid_status_is_rejected(self):
        with self.assertRaises(EvaluationError):
            evaluate_answer(
                self.answer, FakeProvider(payload(status="excellent", awarded_score=2))
            )
        self.assertFalse(AnswerEvaluation.objects.filter(answer=self.answer).exists())

    def test_malformed_provider_response_is_not_saved(self):
        with self.assertRaises(EvaluationError):
            evaluate_answer(self.answer, FakeProvider(payload=["not", "a", "dict"]))
        self.assertFalse(AnswerEvaluation.objects.filter(answer=self.answer).exists())

    def test_provider_error_is_not_saved(self):
        with self.assertRaises(EvaluationError) as caught:
            evaluate_answer(
                self.answer, FakeProvider(error=RuntimeError("gemini timeout secret"))
            )
        self.assertEqual(str(caught.exception), GENERIC_FAILURE)
        self.assertFalse(AnswerEvaluation.objects.filter(answer=self.answer).exists())

    def test_correct_status_must_equal_max_score(self):
        with self.assertRaises(EvaluationError):
            evaluate_answer(
                self.answer, FakeProvider(payload(status="correct", awarded_score=1))
            )

    def test_partial_status_cannot_be_max_or_zero(self):
        with self.assertRaises(EvaluationError):
            evaluate_answer(
                self.answer, FakeProvider(payload(status="partial", awarded_score=2))
            )
        with self.assertRaises(EvaluationError):
            evaluate_answer(
                self.answer, FakeProvider(payload(status="partial", awarded_score=0))
            )

    def test_incorrect_status_cannot_be_max_score(self):
        with self.assertRaises(EvaluationError):
            evaluate_answer(
                self.answer,
                FakeProvider(payload(status="incorrect", awarded_score=2, feedback="x")),
            )

    def test_blank_feedback_is_rejected(self):
        with self.assertRaises(EvaluationError):
            evaluate_answer(self.answer, FakeProvider(payload(feedback="  ")))

    def test_reevaluation_updates_the_same_row(self):
        first = evaluate_answer(self.answer, FakeProvider(payload()))
        second = evaluate_answer(
            self.answer,
            FakeProvider(payload(status="partial", awarded_score=1, feedback="ناقص.")),
        )
        self.assertEqual(first.id, second.id)
        self.assertEqual(AnswerEvaluation.objects.filter(answer=self.answer).count(), 1)
        self.assertEqual(second.status, AnswerEvaluation.Status.PARTIAL)

    def test_evaluate_answers_uses_complete_many_when_available(self):
        class BatchProvider:
            model_name = "batch-model"

            def __init__(self):
                self.complete_calls = 0
                self.many_calls = 0

            def complete(self, request):
                self.complete_calls += 1
                return payload()

            def complete_many(self, requests):
                self.many_calls += 1
                return [payload() for _ in requests]

        second_question = Question.objects.create(
            assessment=self.assessment,
            order=2,
            text="ما ناتج 1/4 + 1/4؟",
            max_score=Decimal("2"),
            model_answer="1/2",
        )
        second = SubmissionAnswer.objects.create(
            submission=self.submission,
            question=second_question,
            answer_text="1/2",
        )
        provider = BatchProvider()
        failed = evaluate_answers([self.answer, second], provider=provider)
        self.assertEqual(failed, 0)
        self.assertEqual(provider.many_calls, 1)
        self.assertEqual(provider.complete_calls, 0)
        self.assertEqual(AnswerEvaluation.objects.count(), 2)

    def test_payload_is_academic_only(self):
        request = request_from_answer(self.answer)
        as_dict = request.__dict__
        self.assertEqual(request.student_answer, "3/4")
        self.assertEqual(request.question, self.question.text)
        self.assertEqual(request.model_answer, "3/4")
        self.assertEqual(request.max_score, Decimal("2"))
        self.assertEqual(request.subject, "الرياضيات")
        self.assertEqual(request.grade, "الصف السادس")
        self.assertNotIn("طالب أ", str(as_dict))
        self.assertNotIn("S-001", str(as_dict))
        self.assertNotIn("eval-teacher", str(as_dict))

    def test_provider_sees_confirmed_answer_not_ocr_text(self):
        OcrAnswerCandidate.objects.create(
            submission=self.submission,
            question=self.question,
            extracted_text="اقتراح من التعرف",
        )
        provider = FakeProvider(payload())
        evaluate_answer(self.answer, provider)
        self.assertEqual(provider.calls[0].student_answer, "3/4")
        self.assertNotIn("اقتراح من التعرف", provider.calls[0].student_answer)

    def test_provider_receives_english_locale(self):
        provider = FakeProvider(payload())
        evaluate_answer(self.answer, provider, locale="en")
        self.assertEqual(provider.calls[0].locale, "en")

    def test_invalid_locale_falls_back_to_arabic(self):
        provider = FakeProvider(payload())
        evaluate_answer(self.answer, provider, locale="fr")
        self.assertEqual(provider.calls[0].locale, "ar")

    def test_missing_locale_defaults_to_arabic(self):
        provider = FakeProvider(payload())
        evaluate_answer(self.answer, provider)
        self.assertEqual(provider.calls[0].locale, "ar")


class LocaleNormalizationTests(TestCase):
    def test_ar_and_en_are_accepted(self):
        self.assertEqual(normalize_locale("ar"), "ar")
        self.assertEqual(normalize_locale("EN"), "en")
        self.assertEqual(normalize_locale(" en "), "en")

    def test_invalid_values_fall_back_to_ar(self):
        self.assertEqual(normalize_locale(None), "ar")
        self.assertEqual(normalize_locale(""), "ar")
        self.assertEqual(normalize_locale("fr"), "ar")
        self.assertEqual(normalize_locale("en-US"), "ar")
        self.assertEqual(normalize_locale(1), "ar")
        self.assertEqual(locale_from_request_data({"locale": "en"}), "en")
        self.assertEqual(locale_from_request_data({"locale": "zh"}), "ar")
        self.assertEqual(locale_from_request_data({}), "ar")
        self.assertEqual(locale_from_request_data(None), "ar")


class ParseProviderPayloadTests(TestCase):
    def test_non_dict_is_rejected(self):
        with self.assertRaises(EvaluationError):
            parse_provider_payload("{}", Decimal("2"))


class GeminiProviderTests(TestCase):
    def setUp(self):
        self.request = EvaluationRequest(
            subject="الرياضيات",
            grade="الصف السادس",
            question="ما ناتج 1/2 + 1/4؟",
            model_answer="3/4",
            max_score=Decimal("2"),
            student_answer="3/4",
            locale="ar",
        )

    def test_parsed_dict_is_returned(self):
        client = _FakeGeminiClient(_FakeGeminiResponse(parsed=payload()))
        provider = GeminiEvaluationProvider(client=client)
        self.assertEqual(provider.complete(self.request)["status"], "correct")
        prompt = client.models.kwargs["contents"]
        self.assertIn("ما ناتج 1/2 + 1/4؟", prompt)
        self.assertIn("3/4", prompt)
        self.assertNotIn("طالب", prompt)
        self.assertNotIn("S-001", prompt)
        self.assertIn("Locale: ar", prompt)
        self.assertIn("Write both feedback and misconception in the language of locale", prompt)

    def test_english_locale_is_in_the_prompt(self):
        client = _FakeGeminiClient(_FakeGeminiResponse(parsed=payload()))
        request = EvaluationRequest(
            subject="Math",
            grade="Grade 6",
            question="What is 1/2 + 1/4?",
            model_answer="3/4",
            max_score=Decimal("2"),
            student_answer="3/4",
            locale="en",
        )
        GeminiEvaluationProvider(client=client).complete(request)
        prompt = client.models.kwargs["contents"]
        self.assertIn("Locale: en", prompt)
        self.assertIn("locale=en means English", prompt)
        self.assertIn("Write both feedback and misconception in the language of locale", prompt)

    def test_json_text_is_accepted_when_parsed_is_missing(self):
        import json

        client = _FakeGeminiClient(
            _FakeGeminiResponse(parsed=None, text=json.dumps(payload()))
        )
        data = GeminiEvaluationProvider(client=client).complete(self.request)
        self.assertEqual(data["awarded_score"], 2)

    def test_malformed_json_text_is_a_safe_error(self):
        client = _FakeGeminiClient(_FakeGeminiResponse(parsed=None, text="not-json"))
        with self.assertRaises(EvaluationError) as caught:
            GeminiEvaluationProvider(client=client).complete(self.request)
        self.assertEqual(str(caught.exception), GENERIC_FAILURE)

    def test_client_exception_does_not_leak(self):
        client = _FakeGeminiClient(error=RuntimeError("API key abc123 timed out"))
        with self.assertRaises(EvaluationError) as caught:
            GeminiEvaluationProvider(client=client).complete(self.request)
        self.assertEqual(str(caught.exception), GENERIC_FAILURE)

    def test_retries_once_on_http_429(self):
        class QuotaThenOk:
            def __init__(self):
                self.models = self
                self.calls = 0
                self.kwargs = None

            def generate_content(self, **kwargs):
                self.kwargs = kwargs
                self.calls += 1
                if self.calls == 1:
                    error = RuntimeError("quota")
                    error.code = 429
                    raise error
                return _FakeGeminiResponse(parsed=payload())

        client = QuotaThenOk()
        with patch("apps.assessments.services.gemini.time.sleep") as slept:
            data = GeminiEvaluationProvider(client=client).complete(self.request)
        slept.assert_called_once()
        self.assertEqual(client.calls, 2)
        self.assertEqual(data["status"], "correct")

    def test_retries_once_on_http_503(self):
        class UnavailableThenOk:
            def __init__(self):
                self.models = self
                self.calls = 0

            def generate_content(self, **kwargs):
                self.calls += 1
                if self.calls == 1:
                    error = RuntimeError("high demand")
                    error.code = 503
                    raise error
                return _FakeGeminiResponse(parsed=payload())

        client = UnavailableThenOk()
        with patch("apps.assessments.services.gemini.time.sleep") as slept:
            data = GeminiEvaluationProvider(client=client).complete(self.request)
        slept.assert_called_once()
        self.assertEqual(client.calls, 2)
        self.assertEqual(data["status"], "correct")

    @override_settings(
        GEMINI_MODEL="gemini-3.6-flash",
        GEMINI_FALLBACK_MODEL="gemini-3.5-flash",
    )
    def test_falls_back_when_primary_model_stays_unavailable(self):
        class PrimaryBusyFallbackOk:
            def __init__(self):
                self.models = self
                self.calls = []

            def generate_content(self, **kwargs):
                self.calls.append(kwargs["model"])
                if kwargs["model"] == "gemini-3.6-flash":
                    error = RuntimeError("high demand")
                    error.code = 503
                    raise error
                return _FakeGeminiResponse(parsed=payload())

        client = PrimaryBusyFallbackOk()
        provider = GeminiEvaluationProvider(client=client)
        with patch("apps.assessments.services.gemini.time.sleep"):
            data = provider.complete(self.request)
        self.assertEqual(data["status"], "correct")
        self.assertEqual(provider.model_name, "gemini-3.5-flash")
        self.assertIn("gemini-3.6-flash", client.calls)
        self.assertIn("gemini-3.5-flash", client.calls)

    def test_complete_many_uses_one_gemini_request(self):
        client = _FakeGeminiClient(
            _FakeGeminiResponse(
                parsed={
                    "evaluations": [
                        {**payload(), "index": 0},
                        {
                            **payload(
                                status="incorrect",
                                awarded_score=0,
                                feedback="الإجابة غير صحيحة.",
                            ),
                            "index": 1,
                        },
                    ]
                }
            )
        )
        second = EvaluationRequest(
            subject="الرياضيات",
            grade="الصف السادس",
            question="ما ناتج 1/4 + 1/4؟",
            model_answer="1/2",
            max_score=Decimal("2"),
            student_answer="1",
            locale="ar",
        )
        mapped = GeminiEvaluationProvider(client=client).complete_many(
            [self.request, second]
        )
        self.assertEqual(len(mapped), 2)
        self.assertEqual(mapped[0]["status"], "correct")
        self.assertEqual(mapped[1]["status"], "incorrect")
        self.assertIn("Items:", client.kwargs["contents"])
        self.assertEqual(
            client.kwargs["config"]["response_schema"]["required"], ["evaluations"]
        )

    @override_settings(GEMINI_API_KEY="")
    def test_missing_api_key_does_not_call_the_sdk(self):
        with self.assertRaises(EvaluationError) as caught:
            GeminiEvaluationProvider().complete(self.request)
        self.assertEqual(str(caught.exception), GENERIC_FAILURE)


class _FakeGeminiResponse:
    def __init__(self, parsed=None, text=""):
        self.parsed = parsed
        self.text = text


class _FakeGeminiClient:
    def __init__(self, response=None, error=None):
        self.models = self
        self.response = response
        self.error = error
        self.kwargs = None

    def generate_content(self, **kwargs):
        self.kwargs = kwargs
        if self.error is not None:
            raise self.error
        return self.response


class EvaluationApiTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="eval-manager", password="strong-pass-123"
            ),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="eval-teacher-a", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="eval-teacher-b", password="strong-pass-123"
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
        self.answer_a = SubmissionAnswer.objects.create(
            submission=self.submission_a, question=self.q1, answer_text="3/4"
        )
        self.answer_b = SubmissionAnswer.objects.create(
            submission=self.submission_b,
            question=Question.objects.create(
                assessment=self.assessment_b,
                order=1,
                text="ما وظيفة النواة؟",
                max_score=Decimal("2"),
                model_answer="تنظيم",
            ),
            answer_text="تنظيم",
        )

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def evaluate_url(self, assessment, submission, answer):
        return (
            f"/api/v1/assessments/{assessment.id}/submissions/"
            f"{submission.id}/answers/{answer.id}/evaluate/"
        )

    def bulk_url(self, assessment, submission):
        return f"/api/v1/assessments/{assessment.id}/submissions/{submission.id}/evaluate/"

    def answers_url(self, assessment, submission):
        return (
            f"/api/v1/assessments/{assessment.id}/submissions/"
            f"{submission.id}/answers/"
        )

    def test_teacher_evaluates_own_answer(self):
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(payload()),
        ):
            response = self.client.post(
                self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
            )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "correct")
        self.assertEqual(response.data["awarded_score"], 2)
        self.assertEqual(AnswerEvaluation.objects.get().answer, self.answer_a)

    def test_teacher_cannot_evaluate_another_teachers_answer(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.evaluate_url(self.assessment_b, self.submission_b, self.answer_b)
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(AnswerEvaluation.objects.exists())

    def test_manager_can_evaluate(self):
        self.authenticate(self.manager)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(payload()),
        ):
            response = self.client.post(
                self.evaluate_url(self.assessment_b, self.submission_b, self.answer_b)
            )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(AnswerEvaluation.objects.get().answer, self.answer_b)

    def test_foreign_answer_id_under_wrong_submission_is_404(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.evaluate_url(self.assessment_a, self.submission_a, self.answer_b)
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.post(
            self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
        )
        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )

    def test_get_returns_404_before_an_evaluation_exists(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_get_returns_the_saved_evaluation(self):
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(payload()),
        ):
            self.client.post(
                self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
            )
        response = self.client.get(
            self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "correct")

    def test_provider_error_is_a_safe_400(self):
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(error=RuntimeError("quota exceeded xyz")),
        ):
            response = self.client.post(
                self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
            )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn(GENERIC_FAILURE, str(response.data))
        self.assertNotIn("xyz", str(response.data))
        self.assertFalse(AnswerEvaluation.objects.exists())

    def test_changing_the_student_answer_drops_the_evaluation(self):
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(payload()),
        ):
            self.client.post(
                self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
            )
        self.assertTrue(AnswerEvaluation.objects.filter(answer=self.answer_a).exists())
        response = self.client.put(
            self.answers_url(self.assessment_a, self.submission_a),
            {
                "answers": [
                    {"question_id": str(self.q1.id), "answer_text": "إجابة جديدة"},
                ]
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIsNone(response.data["answers"][0]["evaluation"])
        self.assertFalse(AnswerEvaluation.objects.filter(answer=self.answer_a).exists())

    def test_unchanged_answer_keeps_the_evaluation(self):
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(payload()),
        ):
            self.client.post(
                self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
            )
        self.client.put(
            self.answers_url(self.assessment_a, self.submission_a),
            {
                "answers": [
                    {"question_id": str(self.q1.id), "answer_text": "3/4"},
                ]
            },
            format="json",
        )
        self.assertTrue(AnswerEvaluation.objects.filter(answer=self.answer_a).exists())

    def test_bulk_evaluates_only_existing_answers(self):
        SubmissionAnswer.objects.create(
            submission=self.submission_a, question=self.q2, answer_text="1/2"
        )
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(
                payload(status="partial", awarded_score=1, feedback="ناقص.")
            ),
        ):
            response = self.client.post(
                self.bulk_url(self.assessment_a, self.submission_a)
            )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(AnswerEvaluation.objects.count(), 2)
        self.assertIsNotNone(response.data["answers"][0]["evaluation"])
        self.assertIsNotNone(response.data["answers"][1]["evaluation"])
        self.assertEqual(response.data["failed_count"], 0)

    def test_bulk_without_confirmed_answers_is_rejected(self):
        self.answer_a.delete()
        self.authenticate(self.teacher_a)
        response = self.client.post(self.bulk_url(self.assessment_a, self.submission_a))
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn(NO_CONFIRMED_ANSWERS, str(response.data))

    def test_bulk_keeps_successes_when_one_answer_fails(self):
        second = SubmissionAnswer.objects.create(
            submission=self.submission_a, question=self.q2, answer_text="1/2"
        )
        calls = {"n": 0}

        def provider_for(_request=None):
            class Switching(FakeProvider):
                def complete(inner, request):
                    calls["n"] += 1
                    if calls["n"] == 2:
                        raise RuntimeError("second failed")
                    return payload()

            return Switching(payload())

        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            side_effect=lambda: provider_for(),
        ):
            response = self.client.post(
                self.bulk_url(self.assessment_a, self.submission_a)
            )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(AnswerEvaluation.objects.count(), 1)
        self.assertEqual(response.data["failed_count"], 1)
        self.assertTrue(AnswerEvaluation.objects.filter(answer=self.answer_a).exists())
        self.assertFalse(AnswerEvaluation.objects.filter(answer=second).exists())

    def test_empty_answer_does_not_call_gemini_over_http(self):
        self.answer_a.answer_text = ""
        self.answer_a.save(update_fields=["answer_text"])
        provider = FakeProvider(payload())
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=provider,
        ):
            response = self.client.post(
                self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
            )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(provider.calls, [])
        self.assertEqual(response.data["status"], "incorrect")
        self.assertEqual(response.data["awarded_score"], 0)

    def test_submission_detail_nests_evaluation(self):
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(payload()),
        ):
            self.client.post(
                self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a)
            )
        response = self.client.get(
            f"/api/v1/assessments/{self.assessment_a.id}/submissions/{self.submission_a.id}/"
        )
        evaluation = response.data["answers"][0]["evaluation"]
        self.assertEqual(evaluation["status"], "correct")
        self.assertEqual(response.data["answers"][0]["id"], str(self.answer_a.id))
        self.assertIsNone(response.data["answers"][1]["evaluation"])
        self.assertIsNone(response.data["answers"][1]["id"])

    def test_api_forwards_english_locale_to_the_provider(self):
        provider = FakeProvider(payload())
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=provider,
        ):
            response = self.client.post(
                self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a),
                {"locale": "en"},
                format="json",
            )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(provider.calls[0].locale, "en")

    def test_api_forwards_arabic_locale_to_the_provider(self):
        provider = FakeProvider(payload())
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=provider,
        ):
            response = self.client.post(
                self.bulk_url(self.assessment_a, self.submission_a),
                {"locale": "ar"},
                format="json",
            )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(provider.calls[0].locale, "ar")

    def test_api_falls_back_when_locale_is_invalid(self):
        provider = FakeProvider(payload())
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=provider,
        ):
            response = self.client.post(
                self.evaluate_url(self.assessment_a, self.submission_a, self.answer_a),
                {"locale": "zh-CN"},
                format="json",
            )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(provider.calls[0].locale, "ar")


ACCEPTANCE_ANSWERS = (
    (1, "3/4"),
    (2, "1/5"),
    (3, "1/2"),
    (4, "3/4"),
    (5, "18 سم"),
    (6, "لأننا ضربنا 1 في 2"),
)


class ConfirmedAnswerEvaluationTests(APITestCase):
    """OCR confirm must land in SubmissionAnswer.answer_text before grading."""

    def setUp(self):
        teacher = UserProfile.objects.create(
            user=get_user_model().objects.create_user(
                username="confirm-eval-teacher", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        classroom = make_classroom(teacher, "سادس أ")
        self.assessment = Assessment.objects.create(
            classroom=classroom, title="اختبار القبول"
        )
        self.questions = [
            Question.objects.create(
                assessment=self.assessment,
                order=order,
                text=f"سؤال {order}",
                max_score=Decimal("2"),
                model_answer=text,
            )
            for order, text in ACCEPTANCE_ANSWERS
        ]
        self.submission = Submission.objects.create(
            assessment=self.assessment,
            student=Student.objects.create(
                classroom=classroom, internal_code="S-010", display_name="طالب أ"
            ),
        )
        token, _ = Token.objects.get_or_create(user=teacher.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def test_evaluation_receives_confirmed_answer_text(self):
        confirm = self.client.put(
            (
                f"/api/v1/assessments/{self.assessment.id}/submissions/"
                f"{self.submission.id}/ocr-mapping/confirm/"
            ),
            {
                "answers": [
                    {
                        "question_id": str(question.id),
                        "answer_text": text,
                    }
                    for question, (_, text) in zip(self.questions, ACCEPTANCE_ANSWERS)
                ]
            },
            format="json",
        )
        self.assertEqual(confirm.status_code, status.HTTP_200_OK)
        for question, (_, text) in zip(self.questions, ACCEPTANCE_ANSWERS):
            self.assertEqual(
                SubmissionAnswer.objects.get(question=question).answer_text, text
            )

        detail = self.client.get(
            f"/api/v1/assessments/{self.assessment.id}/submissions/{self.submission.id}/"
        )
        self.assertEqual(
            [entry["answer_text"] for entry in detail.data["answers"]],
            [text for _, text in ACCEPTANCE_ANSWERS],
        )

        provider = FakeProvider(payload())
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=provider,
        ):
            response = self.client.post(
                (
                    f"/api/v1/assessments/{self.assessment.id}/submissions/"
                    f"{self.submission.id}/evaluate/"
                ),
                {"locale": "ar"},
                format="json",
            )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            [call.student_answer for call in provider.calls],
            [text for _, text in ACCEPTANCE_ANSWERS],
        )
        for entry in response.data["answers"]:
            self.assertNotEqual(entry["evaluation"]["feedback"], EMPTY_FEEDBACK)
            self.assertEqual(entry["evaluation"]["status"], "correct")
        for answer in SubmissionAnswer.objects.filter(submission=self.submission):
            self.assertEqual(
                request_from_answer(answer).student_answer, answer.answer_text
            )


class SixAnswerBulkEvaluationTests(APITestCase):
    """Bulk evaluate must persist every non-empty answer and complete the result."""

    def setUp(self):
        teacher = UserProfile.objects.create(
            user=get_user_model().objects.create_user(
                username="six-eval-teacher", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        classroom = make_classroom(teacher, "سادس أ")
        self.assessment = Assessment.objects.create(
            classroom=classroom, title="اختبار القبول"
        )
        self.questions = [
            Question.objects.create(
                assessment=self.assessment,
                order=order,
                text=f"سؤال {order}",
                max_score=Decimal("2"),
                model_answer=text,
            )
            for order, text in ACCEPTANCE_ANSWERS
        ]
        self.submission = Submission.objects.create(
            assessment=self.assessment,
            student=Student.objects.create(
                classroom=classroom, internal_code="S-016", display_name="طالب أ"
            ),
        )
        self.answers = [
            SubmissionAnswer.objects.create(
                submission=self.submission,
                question=question,
                answer_text=text,
            )
            for question, (_, text) in zip(self.questions, ACCEPTANCE_ANSWERS)
        ]
        token, _ = Token.objects.get_or_create(user=teacher.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def bulk_url(self):
        return (
            f"/api/v1/assessments/{self.assessment.id}/submissions/"
            f"{self.submission.id}/evaluate/"
        )

    def result_url(self):
        return (
            f"/api/v1/assessments/{self.assessment.id}/submissions/"
            f"{self.submission.id}/result/"
        )

    def test_bulk_evaluate_creates_six_rows_and_completes_the_result(self):
        self.assertEqual(len(self.answers), 6)
        self.assertEqual(AnswerEvaluation.objects.count(), 0)
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(payload()),
        ):
            response = self.client.post(self.bulk_url(), {"locale": "ar"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["failed_count"], 0)
        self.assertEqual(
            AnswerEvaluation.objects.filter(answer__submission=self.submission).count(),
            6,
        )
        for answer in self.answers:
            self.assertTrue(AnswerEvaluation.objects.filter(answer=answer).exists())
        result = self.client.get(self.result_url())
        self.assertEqual(result.status_code, status.HTTP_200_OK)
        self.assertEqual(result.data["unevaluated_count"], 0)
        self.assertTrue(result.data["is_complete"])
        self.assertEqual(result.data["evaluated_questions"], 6)

    def test_bulk_all_provider_failures_are_a_safe_400(self):
        with patch(
            "apps.assessments.services.evaluation.get_provider",
            return_value=FakeProvider(error=RuntimeError("quota secret xyz")),
        ):
            response = self.client.post(self.bulk_url(), {"locale": "ar"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn(GENERIC_FAILURE, str(response.data))
        self.assertNotIn("xyz", str(response.data))
        self.assertNotIn("quota", str(response.data))
        self.assertEqual(AnswerEvaluation.objects.count(), 0)

    @override_settings(GEMINI_API_KEY="")
    def test_bulk_missing_api_key_is_a_safe_400(self):
        response = self.client.post(self.bulk_url(), {"locale": "ar"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn(GENERIC_FAILURE, str(response.data))
        self.assertEqual(AnswerEvaluation.objects.count(), 0)

    def test_partial_provider_failure_is_reported_not_silent_success(self):
        calls = {"n": 0}

        def provider_for():
            class Switching(FakeProvider):
                def complete(inner, request):
                    calls["n"] += 1
                    if calls["n"] == 3:
                        raise RuntimeError("third failed secret")
                    return payload()

            return Switching(payload())

        with patch(
            "apps.assessments.services.evaluation.get_provider",
            side_effect=lambda: provider_for(),
        ):
            response = self.client.post(self.bulk_url(), {"locale": "ar"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["failed_count"], 1)
        self.assertNotIn("secret", str(response.data))
        self.assertEqual(AnswerEvaluation.objects.count(), 5)
        result = self.client.get(self.result_url())
        self.assertEqual(result.data["unevaluated_count"], 1)
        self.assertFalse(result.data["is_complete"])
