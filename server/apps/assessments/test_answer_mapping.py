import shutil
import tempfile
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import UserProfile
from apps.assessments.models import (
    Assessment,
    AttachmentOcrResult,
    OcrAnswerCandidate,
    Question,
    Submission,
    SubmissionAnswer,
    SubmissionAttachment,
)
from apps.assessments.services.answer_mapping import (
    NoExtractedTextError,
    map_ocr_text_to_questions,
    split_answers_by_markers,
)
from apps.assessments.services.ocr import TesseractExtractor, run_ocr
from apps.classrooms.models import Student

from .tests import jpeg_bytes, make_classroom

MAPPING_MEDIA = tempfile.mkdtemp(prefix="bayyin-mapping-media-")


class MarkerSplittingTests(TestCase):
    def test_arabic_sin_marker(self):
        blocks = split_answers_by_markers("س1\nثلاثة أرباع\nس2\nالنصف")
        self.assertEqual(blocks[1], "ثلاثة أرباع")
        self.assertEqual(blocks[2], "النصف")

    def test_arabic_question_word_marker(self):
        blocks = split_answers_by_markers("السؤال 1\n3/4")
        self.assertEqual(blocks[1], "3/4")

    def test_english_q_marker(self):
        blocks = split_answers_by_markers("Q1\n3/4\nQ2\n1/2")
        self.assertEqual(blocks[1], "3/4")
        self.assertEqual(blocks[2], "1/2")

    def test_english_question_word_marker(self):
        blocks = split_answers_by_markers("Question 1\nthree quarters")
        self.assertEqual(blocks[1], "three quarters")

    def test_dotted_and_parenthesis_numbers(self):
        blocks = split_answers_by_markers("1. first\n2) second")
        self.assertEqual(blocks[1], "first")
        self.assertEqual(blocks[2], "second")

    def test_a_fraction_is_not_a_question_marker(self):
        self.assertEqual(split_answers_by_markers("1/2 + 1/4 = 3/4"), {})

    def test_unmarked_text_is_not_guessed_as_question_one(self):
        self.assertEqual(split_answers_by_markers("just some writing"), {})

    def test_unnumbered_sin_with_answer_label(self):
        blocks = split_answers_by_markers(
            "س ما ناتج(درجتان)\n"
            "الإجابة:3/4\n"
            "س ما ناتج(درجتان)\n"
            "الإجابة:1/5\n"
            "س ما ناتج(درجتان)\n"
            "الإجابة:1/2\n"
            "س اكتب العدد(درجتان)\n"
            "الإجابة:3/4\n"
            "س مستطيل طوله(درجتان)\n"
            "الإجابة:18 سم\n"
            "س اشرح لماذا(درجتان)\n"
            "الإجابة: لأننا ضربنا 1 في 2"
        )
        self.assertEqual(
            blocks,
            {
                1: "3/4",
                2: "1/5",
                3: "1/2",
                4: "3/4",
                5: "18 سم",
                6: "لأننا ضربنا 1 في 2",
            },
        )

    def test_colon_between_sin_and_number(self):
        blocks = split_answers_by_markers(
            "س:1\nالإجابة: 3/4\nس :2\nالإجابة: 1/5"
        )
        self.assertEqual(blocks[1], "3/4")
        self.assertEqual(blocks[2], "1/5")

    def test_answer_labels_with_spaces_and_english(self):
        blocks = split_answers_by_markers(
            "س1\nالإجابة : 3/4\n"
            "س2\nالاجابة:1/5\n"
            "س3\nAnswer: 1/2\n"
            "س4\nAnswer : 3/4"
        )
        self.assertEqual(blocks[1], "3/4")
        self.assertEqual(blocks[2], "1/5")
        self.assertEqual(blocks[3], "1/2")
        self.assertEqual(blocks[4], "3/4")

    def test_footer_is_not_glued_to_the_last_answer(self):
        blocks = split_answers_by_markers(
            "س1\nالإجابة: 3/4\n"
            "س2\nالإجابة: لأننا ضربنا 1 في 2\n"
            "هذه الورقة تحتوي عمدًا على إجابات صحيحة"
        )
        self.assertEqual(blocks[1], "3/4")
        self.assertEqual(blocks[2], "لأننا ضربنا 1 في 2")

    def test_each_question_keeps_its_own_answer(self):
        blocks = split_answers_by_markers(
            "س:1 ما ناتج\nالإجابة: 3/4\n"
            "س:2 ما ناتج\nالإجابة: 1/5\n"
            "س:3 ما ناتج\nالإجابة: 1/2\n"
            "س:4 اكتب العدد\nالإجابة: 3/4\n"
            "س:5 مستطيل\nالإجابة: 18 سم\n"
            "س:6 اشرح\nالإجابة: لأننا ضربنا 1 في 2"
        )
        self.assertEqual(list(blocks), [1, 2, 3, 4, 5, 6])
        self.assertEqual(blocks[1], "3/4")
        self.assertEqual(blocks[6], "لأننا ضربنا 1 في 2")
        self.assertNotIn("1/5", blocks[1])
        self.assertNotIn("3/4", blocks[6])


@override_settings(MEDIA_ROOT=MAPPING_MEDIA)
class AnswerMappingServiceTests(TestCase):
    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        shutil.rmtree(MAPPING_MEDIA, ignore_errors=True)

    def setUp(self):
        teacher = UserProfile.objects.create(
            user=get_user_model().objects.create_user(
                username="map-teacher", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        classroom = make_classroom(teacher, "سادس أ")
        self.assessment = Assessment.objects.create(
            classroom=classroom, title="اختبار الكسور"
        )
        self.q1 = Question.objects.create(
            assessment=self.assessment,
            order=1,
            text="ما ناتج 1/2 + 1/4؟",
            max_score=Decimal("2"),
            model_answer="3/4",
        )
        self.q2 = Question.objects.create(
            assessment=self.assessment,
            order=2,
            text="بسّط الكسر 4/8",
            max_score=Decimal("3"),
            model_answer="1/2",
        )
        self.submission = Submission.objects.create(
            assessment=self.assessment,
            student=Student.objects.create(classroom=classroom, internal_code="S-1"),
        )

    def attach(self, name, created=None):
        attachment = SubmissionAttachment.objects.create(
            submission=self.submission,
            file=SimpleUploadedFile(name, jpeg_bytes()),
            original_filename=name,
            content_type="image/jpeg",
            file_size=len(jpeg_bytes()),
        )
        if created is not None:
            SubmissionAttachment.objects.filter(id=attachment.id).update(
                created_at=created
            )
            attachment.refresh_from_db()
        return attachment

    def complete(self, attachment, text):
        return AttachmentOcrResult.objects.create(
            attachment=attachment,
            status=AttachmentOcrResult.Status.COMPLETED,
            extracted_text=text,
        )

    def test_maps_completed_ocr_by_question_order(self):
        self.complete(self.attach("p.jpg"), "1. 3/4\n2. 1/2")
        outcome = map_ocr_text_to_questions(self.submission)
        by_order = {row.question.order: row.extracted_text for row in outcome.candidates}
        self.assertEqual(by_order[1], "3/4")
        self.assertEqual(by_order[2], "1/2")
        self.assertFalse(outcome.incomplete_ocr)

    def test_multiple_pages_are_joined_in_upload_order(self):
        first = self.attach("page-1.jpg")
        second = self.attach("page-2.jpg")
        self.complete(first, "س1\nمن الصفحة الأولى")
        self.complete(second, "س2\nمن الصفحة الثانية")
        outcome = map_ocr_text_to_questions(self.submission)
        by_order = {row.question.order: row.extracted_text for row in outcome.candidates}
        self.assertEqual(by_order[1], "من الصفحة الأولى")
        self.assertEqual(by_order[2], "من الصفحة الثانية")

    def test_missing_marker_leaves_an_empty_candidate(self):
        self.complete(self.attach("p.jpg"), "س1\nفقط الأولى")
        outcome = map_ocr_text_to_questions(self.submission)
        by_order = {row.question.order: row.extracted_text for row in outcome.candidates}
        self.assertEqual(by_order[1], "فقط الأولى")
        self.assertEqual(by_order[2], "")

    def test_no_completed_ocr_raises(self):
        self.attach("p.jpg")
        with self.assertRaises(NoExtractedTextError):
            map_ocr_text_to_questions(self.submission)

    def test_partial_ocr_still_maps_available_text(self):
        self.complete(self.attach("done.jpg"), "Q1\n3/4\nQ2\n1/2")
        self.attach("pending.jpg")
        outcome = map_ocr_text_to_questions(self.submission)
        self.assertTrue(outcome.incomplete_ocr)
        self.assertEqual(outcome.candidates[0].extracted_text, "3/4")

    def test_manual_submission_answer_is_not_overwritten(self):
        SubmissionAnswer.objects.create(
            submission=self.submission, question=self.q1, answer_text="يدوي"
        )
        self.complete(self.attach("p.jpg"), "1. من الورقة")
        map_ocr_text_to_questions(self.submission)
        self.assertEqual(
            SubmissionAnswer.objects.get(question=self.q1).answer_text, "يدوي"
        )
        self.assertEqual(
            OcrAnswerCandidate.objects.get(question=self.q1).extracted_text,
            "من الورقة",
        )

    def test_rerunning_updates_the_same_candidate_row(self):
        self.complete(self.attach("p.jpg"), "1. أولاً\n2. ثانياً")
        first = map_ocr_text_to_questions(self.submission)
        AttachmentOcrResult.objects.filter(attachment__submission=self.submission).update(
            extracted_text="1. جديد\n2. أيضاً"
        )
        second = map_ocr_text_to_questions(self.submission)
        self.assertEqual(first.candidates[0].id, second.candidates[0].id)
        self.assertEqual(
            OcrAnswerCandidate.objects.filter(submission=self.submission).count(), 2
        )
        self.assertEqual(
            OcrAnswerCandidate.objects.get(question=self.q1).extracted_text, "جديد"
        )


@override_settings(MEDIA_ROOT=MAPPING_MEDIA)
class OcrMappingApiTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="map-manager", password="strong-pass-123"
            ),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="map-teacher-a", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="map-teacher-b", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.class_a = make_classroom(self.teacher_a, "سادس أ")
        self.class_b = make_classroom(self.teacher_b, "خامس أ", subject="العلوم")
        self.assessment_a = Assessment.objects.create(
            classroom=self.class_a, title="اختبار الكسور"
        )
        self.assessment_b = Assessment.objects.create(
            classroom=self.class_b, title="اختبار الخلية"
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
        self.submission_a = Submission.objects.create(
            assessment=self.assessment_a,
            student=Student.objects.create(
                classroom=self.class_a, internal_code="S-001", display_name="طالب أ"
            ),
        )
        self.submission_b = Submission.objects.create(
            assessment=self.assessment_b,
            student=Student.objects.create(classroom=self.class_b, internal_code="S-900"),
        )
        self.foreign_question = Question.objects.create(
            assessment=self.assessment_b,
            order=1,
            text="ما الخلية؟",
            max_score=Decimal("1"),
            model_answer="وحدة",
        )

    def authenticate(self, profile):
        token, _ = Token.objects.get_or_create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def attach_ocr(self, submission, text, name="page.jpg"):
        attachment = SubmissionAttachment.objects.create(
            submission=submission,
            file=SimpleUploadedFile(name, jpeg_bytes()),
            original_filename=name,
            content_type="image/jpeg",
            file_size=len(jpeg_bytes()),
        )
        AttachmentOcrResult.objects.create(
            attachment=attachment,
            status=AttachmentOcrResult.Status.COMPLETED,
            extracted_text=text,
        )
        return attachment

    def mapping_url(self, assessment, submission):
        return (
            f"/api/v1/assessments/{assessment.id}"
            f"/submissions/{submission.id}/ocr-mapping/"
        )

    def confirm_url(self, assessment, submission):
        return f"{self.mapping_url(assessment, submission)}confirm/"

    def test_teacher_maps_own_submission(self):
        self.attach_ocr(self.submission_a, "س1\n3/4\nس2\n1/2")
        self.authenticate(self.teacher_a)
        response = self.client.post(self.mapping_url(self.assessment_a, self.submission_a))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        texts = [row["extracted_text"] for row in response.data["candidates"]]
        self.assertEqual(texts, ["3/4", "1/2"])
        self.assertFalse(response.data["incomplete_ocr"])

    def test_teacher_retrieves_candidates(self):
        self.attach_ocr(self.submission_a, "1. 3/4\n2. 1/2")
        self.authenticate(self.teacher_a)
        self.client.post(self.mapping_url(self.assessment_a, self.submission_a))
        response = self.client.get(self.mapping_url(self.assessment_a, self.submission_a))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data["candidates"]), 2)

    def test_no_completed_ocr_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(self.mapping_url(self.assessment_a, self.submission_a))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("لا يوجد نص مستخرج", str(response.data))

    def test_confirm_creates_and_updates_submission_answers(self):
        self.attach_ocr(self.submission_a, "1. 3/4\n2. 1/2")
        self.authenticate(self.teacher_a)
        self.client.post(self.mapping_url(self.assessment_a, self.submission_a))
        created = self.client.put(
            self.confirm_url(self.assessment_a, self.submission_a),
            {
                "answers": [
                    {"question_id": str(self.q1.id), "answer_text": "3/4"},
                    {"question_id": str(self.q2.id), "answer_text": "1/2"},
                ]
            },
            format="json",
        )
        self.assertEqual(created.status_code, status.HTTP_200_OK)
        self.assertEqual(
            SubmissionAnswer.objects.get(question=self.q1).answer_text, "3/4"
        )
        self.assertEqual(
            OcrAnswerCandidate.objects.get(question=self.q1).status,
            OcrAnswerCandidate.Status.CONFIRMED,
        )

        updated = self.client.put(
            self.confirm_url(self.assessment_a, self.submission_a),
            {
                "answers": [
                    {"question_id": str(self.q1.id), "answer_text": "ثلاثة أرباع"},
                ]
            },
            format="json",
        )
        self.assertEqual(updated.status_code, status.HTTP_200_OK)
        self.assertEqual(
            SubmissionAnswer.objects.get(question=self.q1).answer_text, "ثلاثة أرباع"
        )
        self.assertEqual(SubmissionAnswer.objects.filter(question=self.q2).count(), 1)

    def test_foreign_question_id_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.client.put(
            self.confirm_url(self.assessment_a, self.submission_a),
            {
                "answers": [
                    {
                        "question_id": str(self.foreign_question.id),
                        "answer_text": "مزور",
                    }
                ]
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(SubmissionAnswer.objects.exists())

    def test_teacher_cannot_map_another_teachers_submission(self):
        self.attach_ocr(self.submission_b, "1. secret")
        self.authenticate(self.teacher_a)
        response = self.client.post(self.mapping_url(self.assessment_b, self.submission_b))
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_teacher_cannot_retrieve_another_teachers_candidates(self):
        self.attach_ocr(self.submission_b, "1. secret")
        self.authenticate(self.teacher_b)
        self.client.post(self.mapping_url(self.assessment_b, self.submission_b))
        self.authenticate(self.teacher_a)
        response = self.client.get(self.mapping_url(self.assessment_b, self.submission_b))
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_teacher_cannot_confirm_another_teachers_candidates(self):
        self.authenticate(self.teacher_a)
        response = self.client.put(
            self.confirm_url(self.assessment_b, self.submission_b),
            {"answers": []},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_manager_can_map_across_classrooms(self):
        self.attach_ocr(self.submission_b, "Question 1\nunit")
        Question.objects.create(
            assessment=self.assessment_b,
            order=2,
            text="extra",
            max_score=Decimal("1"),
            model_answer="x",
        )
        self.authenticate(self.manager)
        response = self.client.post(self.mapping_url(self.assessment_b, self.submission_b))
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get(self.mapping_url(self.assessment_a, self.submission_a))
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get(self.mapping_url(self.assessment_a, self.submission_a))
        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )

    def test_current_answer_prefers_the_manual_row(self):
        self.attach_ocr(self.submission_a, "1. من الورقة\n2. الثانية")
        SubmissionAnswer.objects.create(
            submission=self.submission_a, question=self.q1, answer_text="يدوي"
        )
        self.authenticate(self.teacher_a)
        response = self.client.post(self.mapping_url(self.assessment_a, self.submission_a))
        first = response.data["candidates"][0]
        self.assertEqual(first["extracted_text"], "من الورقة")
        self.assertEqual(first["current_answer"], "يدوي")

    def test_confirm_writes_nonempty_text_and_detail_returns_it(self):
        self.attach_ocr(self.submission_a, "1. 3/4\n2. 1/2")
        self.authenticate(self.teacher_a)
        self.client.post(self.mapping_url(self.assessment_a, self.submission_a))
        confirmed = self.client.put(
            self.confirm_url(self.assessment_a, self.submission_a),
            {
                "answers": [
                    {"question_id": str(self.q1.id), "answer_text": "3/4"},
                    {"question_id": str(self.q2.id), "answer_text": "1/2"},
                ]
            },
            format="json",
        )
        self.assertEqual(confirmed.status_code, status.HTTP_200_OK)
        self.assertEqual(
            SubmissionAnswer.objects.get(question=self.q1).answer_text, "3/4"
        )
        self.assertEqual(
            SubmissionAnswer.objects.get(question=self.q2).answer_text, "1/2"
        )

        detail = self.client.get(
            f"/api/v1/assessments/{self.assessment_a.id}/submissions/{self.submission_a.id}/"
        )
        self.assertEqual(detail.status_code, status.HTTP_200_OK)
        texts = {
            entry["question_id"]: entry["answer_text"]
            for entry in detail.data["answers"]
        }
        self.assertEqual(texts[str(self.q1.id)], "3/4")
        self.assertEqual(texts[str(self.q2.id)], "1/2")

        wiped = self.client.put(
            f"/api/v1/assessments/{self.assessment_a.id}/submissions/{self.submission_a.id}/answers/",
            {
                "answers": [
                    {"question_id": str(self.q1.id), "answer_text": ""},
                    {"question_id": str(self.q2.id), "answer_text": ""},
                ]
            },
            format="json",
        )
        self.assertEqual(wiped.status_code, status.HTTP_200_OK)
        self.assertEqual(
            SubmissionAnswer.objects.get(question=self.q1).answer_text, "3/4"
        )
        self.assertEqual(
            [entry["answer_text"] for entry in wiped.data["answers"]],
            ["3/4", "1/2"],
        )


SAMPLE_STUDENT_PDF = (
    Path(__file__).resolve().parent / "fixtures" / "bayyin_sample_student_paper.pdf"
)


@override_settings(MEDIA_ROOT=MAPPING_MEDIA)
class SampleStudentPaperMappingTests(TestCase):
    """PDF text layer → six answers. No Gemini."""

    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        shutil.rmtree(MAPPING_MEDIA, ignore_errors=True)

    def setUp(self):
        teacher = UserProfile.objects.create(
            user=get_user_model().objects.create_user(
                username="sample-paper-teacher", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        classroom = make_classroom(teacher, "سادس أ")
        self.assessment = Assessment.objects.create(
            classroom=classroom, title="اختبار الكسور"
        )
        stems = [
            "ما ناتج 1/4 + 1/2؟",
            "ما ناتج 1/5 - 3/5؟",
            "ما ناتج 3/4 × 2/3؟",
            "اكتب العدد 0.75 في صورة كسر",
            "مستطيل طوله 6 سم وعرضه 4 سم. ما محيطه؟",
            "اشرح لماذا 1/2 يساوي 2/4",
        ]
        for order, text in enumerate(stems, start=1):
            Question.objects.create(
                assessment=self.assessment,
                order=order,
                text=text,
                max_score=Decimal("2"),
                model_answer="x",
            )
        self.submission = Submission.objects.create(
            assessment=self.assessment,
            student=Student.objects.create(classroom=classroom, internal_code="S-TEST"),
        )

    def test_layout_text_maps_to_six_candidates(self):
        data = SAMPLE_STUDENT_PDF.read_bytes()
        with patch(
            "apps.assessments.services.ocr.pytesseract.image_to_string"
        ) as ocr, patch(
            "apps.assessments.services.ocr.convert_from_bytes"
        ) as raster:
            text = TesseractExtractor().extract_from_bytes(
                data, "application/pdf", rebuild_layout=True
            )
        ocr.assert_not_called()
        raster.assert_not_called()
        blocks = split_answers_by_markers(text)
        self.assertEqual(
            blocks,
            {
                1: "3/4",
                2: "1/5",
                3: "1/2",
                4: "3/4",
                5: "18 سم",
                6: "لأننا ضربنا 1 في 2",
            },
        )

    def test_run_ocr_then_map_persists_six_candidates(self):
        payload = SAMPLE_STUDENT_PDF.read_bytes()
        attachment = SubmissionAttachment.objects.create(
            submission=self.submission,
            file=SimpleUploadedFile(
                "bayyin_sample_student_paper.pdf", payload, "application/pdf"
            ),
            original_filename="bayyin_sample_student_paper.pdf",
            content_type="application/pdf",
            file_size=len(payload),
        )
        with patch(
            "apps.assessments.services.ocr.pytesseract.image_to_string"
        ) as ocr, patch(
            "apps.assessments.services.ocr.convert_from_bytes"
        ) as raster:
            result = run_ocr(attachment)
        ocr.assert_not_called()
        raster.assert_not_called()
        self.assertEqual(result.status, AttachmentOcrResult.Status.COMPLETED)
        outcome = map_ocr_text_to_questions(self.submission)
        by_order = {
            row.question.order: row.extracted_text for row in outcome.candidates
        }
        self.assertEqual(len(outcome.candidates), 6)
        self.assertEqual(by_order[1], "3/4")
        self.assertEqual(by_order[2], "1/5")
        self.assertEqual(by_order[3], "1/2")
        self.assertEqual(by_order[4], "3/4")
        self.assertEqual(by_order[5], "18 سم")
        self.assertEqual(by_order[6], "لأننا ضربنا 1 في 2")
