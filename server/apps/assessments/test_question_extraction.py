import shutil
import tempfile
from decimal import Decimal
from pathlib import Path
from unittest import skipUnless
from unittest.mock import patch

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import UserProfile
from apps.assessments.models import (
    Assessment,
    AssessmentQuestionCandidate,
    AssessmentSourceAttachment,
    Question,
)
from apps.assessments.services.ocr import _has_useful_text, _pdf_text_layer, extract_from_bytes
from apps.assessments.services.question_extraction import (
    GENERIC_FAILURE,
    QuestionExtractionError,
    extract_question_candidates,
    normalize_exam_text,
    parse_exam_text,
)
from .tests import jpeg_bytes, make_classroom, pdf_bytes, png_bytes

EXTRACT_MEDIA_ROOT = tempfile.mkdtemp(prefix="bayyin-exam-media-")

ARABIC_PAPER = """
س1: ما ناتج 1/2 + 1/4؟ (درجتان)
الإجابة: 3/4

س 2 بسّط الكسر 4/8
"""

ENGLISH_PAPER = """
Q1. What is 2 + 2? (2 marks)
Answer: 4

Question 2: Name a proper fraction.
"""


class QuestionExtractionParserTests(TestCase):
    def test_arabic_markers_and_score_are_detected(self):
        questions = parse_exam_text(ARABIC_PAPER)

        self.assertEqual(len(questions), 2)
        self.assertEqual(questions[0].order, 1)
        self.assertEqual(questions[0].extracted_text, "ما ناتج 1/2 + 1/4؟")
        self.assertEqual(questions[0].proposed_max_score, Decimal("2"))
        self.assertEqual(questions[0].proposed_model_answer, "3/4")
        self.assertEqual(questions[1].order, 2)
        self.assertIn("بسّط", questions[1].extracted_text)
        self.assertIsNone(questions[1].proposed_max_score)
        self.assertEqual(questions[1].proposed_model_answer, "")

    def test_english_markers_are_detected(self):
        questions = parse_exam_text(ENGLISH_PAPER)

        self.assertEqual([item.order for item in questions], [1, 2])
        self.assertEqual(questions[0].extracted_text, "What is 2 + 2?")
        self.assertEqual(questions[0].proposed_max_score, Decimal("2"))
        self.assertEqual(questions[0].proposed_model_answer, "4")
        self.assertIsNone(questions[1].proposed_max_score)

    def test_missing_score_stays_null(self):
        questions = parse_exam_text("1. What is a fraction?")

        self.assertEqual(len(questions), 1)
        self.assertIsNone(questions[0].proposed_max_score)

    def test_unsure_text_does_not_invent_questions(self):
        questions = extract_question_candidates(
            "This page is a heading and some notes about fractions."
        )

        self.assertEqual(questions, [])

    def test_provider_is_not_used_when_heuristics_find_questions(self):
        class Explosive:
            def extract(self, text):
                raise AssertionError("provider should not run")

        questions = extract_question_candidates(ARABIC_PAPER, provider=Explosive())
        self.assertEqual(len(questions), 2)

    def test_provider_suggestions_are_sanitized(self):
        class FakeProvider:
            def extract(self, text):
                return [
                    {
                        "order": 1,
                        "question_text": "ما ناتج 1/2 + 1/4؟",
                        "max_score": None,
                        "model_answer": "",
                    },
                    {"order": 2, "question_text": "   ", "max_score": 3},
                    {"order": 99, "question_text": ""},
                ]

        questions = extract_question_candidates("no markers here", provider=FakeProvider())
        self.assertEqual(len(questions), 1)
        self.assertEqual(questions[0].extracted_text, "ما ناتج 1/2 + 1/4؟")
        self.assertIsNone(questions[0].proposed_max_score)


RTL_PDF_PAPER = """
س :1 ما ناتج 1/2 + 1/4؟ (درجتان)
الإجابة : 3/4

س :2 ما ناتج 3/5 - 1/5؟ (درجتان)
الإجابة : 2/5
"""


class RtlPdfQuestionExtractionTests(TestCase):
    def test_rtl_pdf_spacing_yields_two_questions_in_order(self):
        questions = parse_exam_text(RTL_PDF_PAPER)

        self.assertEqual([item.order for item in questions], [1, 2])
        self.assertEqual(questions[0].extracted_text, "ما ناتج 1/2 + 1/4؟")
        self.assertEqual(questions[0].proposed_max_score, Decimal("2"))
        self.assertEqual(questions[0].proposed_model_answer, "3/4")
        self.assertEqual(questions[1].extracted_text, "ما ناتج 3/5 - 1/5؟")
        self.assertEqual(questions[1].proposed_max_score, Decimal("2"))
        self.assertEqual(questions[1].proposed_model_answer, "2/5")

    def test_marker_variant_seen_with_space_before_colon(self):
        questions = parse_exam_text("س :1 ما ناتج 1/2 + 1/4؟")
        self.assertEqual(len(questions), 1)
        self.assertEqual(questions[0].order, 1)
        self.assertIn("1/2", questions[0].extracted_text)

    def test_marker_variant_colon_without_spaces(self):
        questions = parse_exam_text("س:1 ما ناتج 1/2 + 1/4؟")
        self.assertEqual(questions[0].order, 1)

    def test_marker_variant_letter_space_number(self):
        questions = parse_exam_text("س 1 ما ناتج 1/2 + 1/4؟")
        self.assertEqual(questions[0].order, 1)

    def test_marker_variant_al_sual_with_spaced_colon(self):
        questions = parse_exam_text("السؤال : 1 ما ناتج 1/2 + 1/4؟")
        self.assertEqual(questions[0].order, 1)
        self.assertIn("1/2", questions[0].extracted_text)

    def test_model_answer_accepts_alif_without_hamza_and_spaced_colon(self):
        questions = parse_exam_text("س1 ما الناتج؟\nالاجابة : 3/4")
        self.assertEqual(questions[0].proposed_model_answer, "3/4")

    def test_english_answer_marker_allows_space_before_colon(self):
        questions = parse_exam_text("Q1 What is 2+2?\nAnswer : 4")
        self.assertEqual(questions[0].proposed_model_answer, "4")

    def test_bidi_marks_are_stripped_before_parsing(self):
        text = "س \u202b:1 ما ناتج 1/2 + 1/4؟\u202c"
        questions = parse_exam_text(text)
        self.assertEqual(len(questions), 1)
        self.assertEqual(questions[0].order, 1)
        self.assertEqual(questions[0].extracted_text, "ما ناتج 1/2 + 1/4؟")

    def test_normalization_does_not_reverse_arabic_or_fractions(self):
        from apps.assessments.services.question_extraction import normalize_exam_text

        raw = "س :1 ما ناتج 1/2 + 1/4؟"
        normalized = normalize_exam_text(raw)
        self.assertIn("ما ناتج", normalized)
        self.assertIn("1/2 + 1/4", normalized)
        self.assertNotIn("4/1", normalized)
        self.assertLess(normalized.index("ما"), normalized.index("ناتج"))


# Exact pypdf text layer from the uploaded `_teacher_exam_source.pdf`.
# Question numbers were dropped by the PDF extractor; only a leading `س` remains.
REAL_ARABIC_EXAM_PDF_TEXT = (
    "اختبار تجريبي - الرياضيات\n"
    "نسخة المعلم - مهيأة لاختبار استخراج الأسئلة في نظام بيّن\n"
    "الصف: السادس\n"
    "المادة: الرياضيات\n"
    "اسم الاختبار: اختبار الكسور والعمليات الأساسية\n"
    "س ما ناتج(درجتان)\n"
    "الإجابة:3/4 \n"
    "س ما ناتج(درجتان)\n"
    "الإجابة:2/5 \n"
    "س ما ناتج(درجتان)\n"
    "الإجابة:1/2 \n"
    "س اكتب العدد(درجتان)\n"
    "الإجابة:3/4 \n"
    "س مستطيل طوله(درجتان)\n"
    "الإجابة:20 \n"
    "س اشرح لماذا(درجتان)\n"
    "الإجابة: لأننا ضربنا البسط والمقام في\n"
    "هذه نسخة اختبار تجريبية تحتوي على نموذج الإجابة لاختبار الاستخراج والمراجعة فقط."
)


class RealArabicExamPdfTextLayerTests(TestCase):
    def test_pypdf_layer_without_question_numbers_yields_six_candidates(self):
        questions = parse_exam_text(REAL_ARABIC_EXAM_PDF_TEXT)

        self.assertEqual(len(questions), 6)
        self.assertEqual([item.order for item in questions], [1, 2, 3, 4, 5, 6])
        self.assertEqual(questions[0].extracted_text, "ما ناتج")
        self.assertEqual(questions[0].proposed_max_score, Decimal("2"))
        self.assertEqual(questions[0].proposed_model_answer, "3/4")
        self.assertEqual(questions[1].proposed_model_answer, "2/5")
        self.assertEqual(questions[2].proposed_model_answer, "1/2")
        self.assertEqual(questions[3].extracted_text, "اكتب العدد")
        self.assertEqual(questions[4].extracted_text, "مستطيل طوله")
        self.assertEqual(questions[4].proposed_model_answer, "20")
        self.assertEqual(questions[5].extracted_text, "اشرح لماذا")
        self.assertIn("البسط", questions[5].proposed_model_answer)

    @skipUnless(
        list(Path("/app/media/assessment_source").glob("*/*.pdf")),
        "uploaded Arabic exam PDF is not mounted in this environment",
    )
    def test_uploaded_pdf_text_layer_and_parser_together(self):
        pdf_path = sorted(
            Path("/app/media/assessment_source").glob("*/*.pdf"),
            key=lambda path: path.stat().st_mtime,
        )[-1]
        data = pdf_path.read_bytes()
        layer = _pdf_text_layer(data)
        extracted = extract_from_bytes(data, "application/pdf")

        self.assertTrue(_has_useful_text(layer))
        self.assertEqual(extracted, layer.strip())
        if "س ما ناتج(درجتان)" not in extracted:
            self.skipTest("mounted PDF is not the teacher exam paper")
        self.assertIn("س ما ناتج(درجتان)", extracted)
        self.assertNotRegex(extracted, r"(?m)^س\s*[:：]?\s*\d")
        questions = parse_exam_text(extracted)
        self.assertEqual(len(questions), 6)
        self.assertEqual([item.order for item in questions], [1, 2, 3, 4, 5, 6])

    def test_provider_failure_is_an_extraction_error_not_empty_result(self):
        class Boom:
            def extract(self, text):
                raise RuntimeError("quota exceeded")

        with self.assertRaises(QuestionExtractionError) as caught:
            extract_question_candidates("heading only, no questions", provider=Boom())

        self.assertEqual(str(caught.exception), GENERIC_FAILURE)


@override_settings(MEDIA_ROOT=EXTRACT_MEDIA_ROOT)
class ExamPaperExtractionApiTests(APITestCase):
    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        shutil.rmtree(EXTRACT_MEDIA_ROOT, ignore_errors=True)

    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="exam-manager", password="strong-pass-123"
            ),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="exam-teacher-a", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="exam-teacher-b", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.class_6a = make_classroom(self.teacher_a, "سادس أ")
        self.class_5a = make_classroom(self.teacher_b, "خامس أ", subject="العلوم")
        self.assessment_a = Assessment.objects.create(
            classroom=self.class_6a, title="اختبار الكسور الأول"
        )
        self.assessment_b = Assessment.objects.create(
            classroom=self.class_5a, title="اختبار الخلية"
        )

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def source_url(self, assessment):
        return f"/api/v1/assessments/{assessment.id}/source-attachments/"

    def extract_url(self, assessment):
        return f"/api/v1/assessments/{assessment.id}/extract-questions/"

    def candidates_url(self, assessment):
        return f"/api/v1/assessments/{assessment.id}/question-candidates/"

    def confirm_url(self, assessment):
        return f"/api/v1/assessments/{assessment.id}/question-candidates/confirm/"

    def upload(self, assessment, filename, content, declared="image/jpeg"):
        return self.client.post(
            self.source_url(assessment),
            {"file": SimpleUploadedFile(filename, content, content_type=declared)},
            format="multipart",
        )

    def extract(self, assessment, text=ARABIC_PAPER):
        with (
            patch(
                "apps.assessments.views.default_extraction_provider",
                return_value=None,
            ),
            patch(
                "apps.assessments.services.question_extraction.extract_stored_file",
                return_value=text,
            ),
        ):
            return self.client.post(self.extract_url(assessment))

    # ---------------------------------------------------------------- upload

    def test_teacher_uploads_exam_jpeg(self):
        self.authenticate(self.teacher_a)
        response = self.upload(self.assessment_a, "ورقة.jpg", jpeg_bytes())

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        attachment = self.assessment_a.source_attachments.get()
        self.assertEqual(attachment.original_filename, "ورقة.jpg")
        self.assertEqual(attachment.content_type, "image/jpeg")
        self.assertEqual(attachment.created_by, self.teacher_a)
        self.assertNotIn("evil", attachment.file.name)

    def test_teacher_uploads_exam_png(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a, "paper.png", png_bytes(), "image/png"
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(
            self.assessment_a.source_attachments.get().content_type, "image/png"
        )

    def test_teacher_uploads_exam_pdf(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a, "paper.pdf", pdf_bytes(), "application/pdf"
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(
            self.assessment_a.source_attachments.get().content_type, "application/pdf"
        )

    def test_unsupported_exam_file_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.upload(self.assessment_a, "notes.txt", b"hello there")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.assessment_a.source_attachments.exists())

    @override_settings(SUBMISSION_ATTACHMENT_MAX_BYTES=64)
    def test_oversized_exam_file_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a, "big.jpg", jpeg_bytes(padding=512)
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.assessment_a.source_attachments.exists())

    def test_stored_exam_filename_is_generated(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "../../evil name.jpg", jpeg_bytes())

        stored = self.assessment_a.source_attachments.get().file.name
        self.assertNotIn("evil", stored)
        self.assertTrue(stored.endswith(".jpg"))

    def test_the_configured_limit_is_ten_megabytes(self):
        self.assertEqual(settings.SUBMISSION_ATTACHMENT_MAX_BYTES, 10 * 1024 * 1024)

    # -------------------------------------------------------------- extract

    def test_ocr_text_is_parsed_into_question_candidates(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        response = self.extract(self.assessment_a)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 2)
        self.assertEqual(response.data[0]["extracted_text"], "ما ناتج 1/2 + 1/4؟")
        self.assertEqual(response.data[0]["proposed_max_score"], 2)
        self.assertEqual(response.data[0]["status"], "suggested")
        self.assertFalse(self.assessment_a.questions.exists())

    def test_extraction_does_not_save_final_questions(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        self.extract(self.assessment_a)

        self.assertEqual(self.assessment_a.questions.count(), 0)
        self.assertEqual(self.assessment_a.question_candidates.count(), 2)

    def test_no_questions_found_returns_an_empty_list(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        response = self.extract(self.assessment_a, text="notes only")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [])

    def test_real_arabic_pdf_text_layer_persists_six_candidates(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "exam.pdf", pdf_bytes(), "application/pdf")
        response = self.extract(self.assessment_a, text=REAL_ARABIC_EXAM_PDF_TEXT)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 6)
        self.assertEqual([item["order"] for item in response.data], [1, 2, 3, 4, 5, 6])
        self.assertEqual(
            self.assessment_a.question_candidates.count(), 6
        )

    def test_provider_failure_returns_extraction_error(self):
        class Boom:
            def extract(self, text):
                raise RuntimeError("quota exceeded")

        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        with (
            patch(
                "apps.assessments.views.default_extraction_provider",
                return_value=Boom(),
            ),
            patch(
                "apps.assessments.services.question_extraction.extract_stored_file",
                return_value="heading only",
            ),
        ):
            response = self.client.post(self.extract_url(self.assessment_a))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["detail"], GENERIC_FAILURE)
        self.assertFalse(self.assessment_a.question_candidates.exists())

    def test_extract_without_an_exam_paper_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(self.extract_url(self.assessment_a))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("ورقة", response.data["detail"])

    # --------------------------------------------------------------- review

    def test_candidate_review_can_update_text(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        self.extract(self.assessment_a)
        candidate = self.assessment_a.question_candidates.get(order=1)

        response = self.client.patch(
            f"{self.candidates_url(self.assessment_a)}{candidate.id}/",
            {"extracted_text": "ما ناتج نصف زائد ربع؟"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        candidate.refresh_from_db()
        self.assertEqual(candidate.extracted_text, "ما ناتج نصف زائد ربع؟")

    def test_candidate_can_be_removed(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        self.extract(self.assessment_a)
        candidate = self.assessment_a.question_candidates.get(order=2)

        response = self.client.delete(
            f"{self.candidates_url(self.assessment_a)}{candidate.id}/"
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(self.assessment_a.question_candidates.count(), 1)

    # -------------------------------------------------------------- confirm

    def _confirm_payload(self, extra=None):
        candidates = list(self.assessment_a.question_candidates.order_by("order"))
        payload = [
            {
                "id": str(candidate.id),
                "order": candidate.order,
                "extracted_text": candidate.extracted_text,
                "proposed_max_score": (
                    candidate.proposed_max_score
                    if candidate.proposed_max_score is not None
                    else Decimal("2")
                ),
                "proposed_model_answer": candidate.proposed_model_answer or "3/4",
            }
            for candidate in candidates
        ]
        if extra:
            payload.extend(extra)
        return {"candidates": payload}

    def test_confirm_creates_real_questions(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        self.extract(self.assessment_a)
        response = self.client.put(
            self.confirm_url(self.assessment_a),
            self._confirm_payload(),
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.assessment_a.questions.count(), 2)
        first = self.assessment_a.questions.get(order=1)
        self.assertEqual(first.text, "ما ناتج 1/2 + 1/4؟")
        self.assertEqual(first.max_score, Decimal("2"))
        self.assertEqual(first.model_answer, "3/4")
        self.assertTrue(
            self.assessment_a.question_candidates.filter(
                status=AssessmentQuestionCandidate.Status.CONFIRMED
            ).exists()
        )

    def test_duplicate_order_is_rejected(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        self.extract(self.assessment_a)
        payload = self._confirm_payload()
        payload["candidates"][1]["order"] = payload["candidates"][0]["order"]

        response = self.client.put(
            self.confirm_url(self.assessment_a), payload, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.assessment_a.questions.exists())

    def test_non_positive_max_score_is_rejected(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        self.extract(self.assessment_a)
        payload = self._confirm_payload()
        payload["candidates"][0]["proposed_max_score"] = 0

        response = self.client.put(
            self.confirm_url(self.assessment_a), payload, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.assessment_a.questions.exists())

    def test_reextraction_does_not_duplicate_confirmed_questions(self):
        self.authenticate(self.teacher_a)
        self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        self.extract(self.assessment_a)
        self.client.put(
            self.confirm_url(self.assessment_a),
            self._confirm_payload(),
            format="json",
        )
        response = self.extract(self.assessment_a)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.assessment_a.questions.count(), 2)
        self.assertEqual(
            self.assessment_a.question_candidates.filter(
                status=AssessmentQuestionCandidate.Status.CONFIRMED
            ).count(),
            2,
        )
        self.assertFalse(
            self.assessment_a.question_candidates.filter(
                status=AssessmentQuestionCandidate.Status.SUGGESTED
            ).exists()
        )

    # ---------------------------------------------------------------- auth

    def test_teacher_cannot_extract_another_teachers_assessment(self):
        self.authenticate(self.teacher_b)
        self.upload(self.assessment_b, "paper.jpg", jpeg_bytes())
        self.authenticate(self.teacher_a)
        response = self.client.post(self.extract_url(self.assessment_b))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_teacher_cannot_upload_to_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.upload(self.assessment_b, "paper.jpg", jpeg_bytes())

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(self.assessment_b.source_attachments.exists())

    def test_manager_can_upload_and_extract(self):
        self.authenticate(self.manager)
        uploaded = self.upload(self.assessment_a, "paper.jpg", jpeg_bytes())
        extracted = self.extract(self.assessment_a)

        self.assertEqual(uploaded.status_code, status.HTTP_201_CREATED)
        self.assertEqual(extracted.status_code, status.HTTP_200_OK)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get(self.candidates_url(self.assessment_a))
        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get(self.candidates_url(self.assessment_a))

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
