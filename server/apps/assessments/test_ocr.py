import shutil
import tempfile
from io import BytesIO
from pathlib import Path
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from pypdf import PdfWriter
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import UserProfile
from apps.assessments.models import (
    Assessment,
    AttachmentOcrResult,
    Submission,
    SubmissionAttachment,
)
from apps.assessments.services.ocr import TesseractExtractor, _has_useful_text
from apps.classrooms.models import Student

from .tests import jpeg_bytes, make_classroom, png_bytes

OCR_MEDIA_ROOT = tempfile.mkdtemp(prefix="bayyin-ocr-media-")


def text_layer_pdf(text="The student wrote three quarters here as the answer"):
    """A one-page PDF whose content stream is real extractable text, not a scan."""
    stream = f"BT /F1 12 Tf 50 200 Td ({text}) Tj ET\n".encode("latin-1")
    objects = [
        b"1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n",
        b"2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n",
        (
            b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 300]"
            b"/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj\n"
        ),
        b"4 0 obj<</Length %d>>stream\n" % len(stream) + stream + b"endstream\nendobj\n",
        b"5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\n",
    ]
    header = b"%PDF-1.1\n"
    body = b"".join(objects)
    startxref = len(header) + len(body)
    offsets = []
    cursor = len(header)
    for obj in objects:
        offsets.append(cursor)
        cursor += len(obj)
    xref = b"xref\n0 6\n0000000000 65535 f \n" + b"".join(
        f"{offset:010d} 00000 n \n".encode() for offset in offsets
    )
    trailer = (
        b"trailer<</Size 6/Root 1 0 R>>\nstartxref\n"
        + str(startxref).encode()
        + b"\n%%EOF\n"
    )
    return header + body + xref + trailer


def tiny_image(fmt):
    buffer = BytesIO()
    Image.new("RGB", (16, 16), "white").save(buffer, format=fmt)
    return buffer.getvalue()


def blank_pdf():
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    buffer = BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


@override_settings(MEDIA_ROOT=OCR_MEDIA_ROOT)
class AttachmentOcrApiTests(APITestCase):
    """Running and reading OCR behind the same scope as the attachment."""

    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        shutil.rmtree(OCR_MEDIA_ROOT, ignore_errors=True)

    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="ocr-manager", password="strong-pass-123"
            ),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="ocr-teacher-a", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="ocr-teacher-b", password="strong-pass-123"
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
        self.submission_a = Submission.objects.create(
            assessment=self.assessment_a,
            student=Student.objects.create(
                classroom=self.class_6a, internal_code="S-001", display_name="طالب أ"
            ),
        )
        self.submission_b = Submission.objects.create(
            assessment=self.assessment_b,
            student=Student.objects.create(
                classroom=self.class_5a, internal_code="S-900"
            ),
        )
        self.attachment_a = self.attach(self.submission_a, "ورقة.jpg")
        self.attachment_b = self.attach(self.submission_b, "secret.jpg")

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def attach(self, submission, filename="paper.jpg", content=None, content_type="image/jpeg"):
        payload = content if content is not None else jpeg_bytes()
        return SubmissionAttachment.objects.create(
            submission=submission,
            file=SimpleUploadedFile(filename, payload),
            original_filename=filename,
            content_type=content_type,
            file_size=len(payload),
        )

    def ocr_url(self, assessment, submission, attachment):
        return (
            f"/api/v1/assessments/{assessment.id}"
            f"/submissions/{submission.id}"
            f"/attachments/{attachment.id}/ocr/"
        )

    def test_teacher_runs_ocr_on_own_image_and_the_result_is_saved(self):
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.ocr.extract_text",
            return_value="ثلاثة أرباع",
        ) as extractor:
            response = self.client.post(
                self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
            )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        extractor.assert_called_once()
        result = AttachmentOcrResult.objects.get(attachment=self.attachment_a)
        self.assertEqual(result.status, AttachmentOcrResult.Status.COMPLETED)
        self.assertEqual(result.extracted_text, "ثلاثة أرباع")
        self.assertIsNotNone(result.processed_at)
        self.assertEqual(response.data["extracted_text"], "ثلاثة أرباع")
        self.assertEqual(response.data["status"], "completed")

    def test_teacher_retrieves_ocr_result(self):
        AttachmentOcrResult.objects.create(
            attachment=self.attachment_a,
            status=AttachmentOcrResult.Status.COMPLETED,
            extracted_text="1/2",
        )
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["extracted_text"], "1/2")

    def test_ocr_has_not_run_yet_is_a_404(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_teacher_cannot_run_ocr_on_another_teachers_attachment(self):
        self.authenticate(self.teacher_a)
        with patch("apps.assessments.services.ocr.extract_text") as extractor:
            response = self.client.post(
                self.ocr_url(self.assessment_b, self.submission_b, self.attachment_b)
            )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        extractor.assert_not_called()
        self.assertFalse(AttachmentOcrResult.objects.exists())

    def test_teacher_cannot_retrieve_another_teachers_ocr_result(self):
        AttachmentOcrResult.objects.create(
            attachment=self.attachment_b,
            status=AttachmentOcrResult.Status.COMPLETED,
            extracted_text="secret answers",
        )
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.ocr_url(self.assessment_b, self.submission_b, self.attachment_b)
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotContains(
            response, "secret answers", status_code=status.HTTP_404_NOT_FOUND
        )

    def test_manager_can_access_ocr_across_classrooms(self):
        self.authenticate(self.manager)
        with patch(
            "apps.assessments.services.ocr.extract_text", return_value="across"
        ):
            created = self.client.post(
                self.ocr_url(self.assessment_b, self.submission_b, self.attachment_b)
            )
        listed = self.client.get(
            self.ocr_url(self.assessment_b, self.submission_b, self.attachment_b)
        )

        self.assertEqual(created.status_code, status.HTTP_200_OK)
        self.assertEqual(listed.status_code, status.HTTP_200_OK)
        self.assertEqual(listed.data["extracted_text"], "across")

    def test_rerunning_ocr_updates_the_same_row(self):
        self.authenticate(self.teacher_a)
        with patch("apps.assessments.services.ocr.extract_text", return_value="first"):
            first = self.client.post(
                self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
            )
        with patch("apps.assessments.services.ocr.extract_text", return_value="second"):
            second = self.client.post(
                self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
            )

        self.assertEqual(first.data["id"], second.data["id"])
        self.assertEqual(second.data["extracted_text"], "second")
        self.assertEqual(
            AttachmentOcrResult.objects.filter(attachment=self.attachment_a).count(),
            1,
        )

    def test_failed_ocr_stores_failed_status_without_leaking_the_engine_error(self):
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.ocr.extract_text",
            side_effect=RuntimeError("tesseract crashed: /tmp/secret"),
        ):
            response = self.client.post(
                self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
            )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "failed")
        self.assertEqual(response.data["error_message"], "تعذر استخراج النص.")
        self.assertNotIn("tesseract", response.data["error_message"])
        self.assertNotIn("/tmp/secret", response.data["extracted_text"])
        result = AttachmentOcrResult.objects.get(attachment=self.attachment_a)
        self.assertEqual(result.status, AttachmentOcrResult.Status.FAILED)

    def test_failed_ocr_can_be_retried(self):
        AttachmentOcrResult.objects.create(
            attachment=self.attachment_a,
            status=AttachmentOcrResult.Status.FAILED,
            error_message="تعذر استخراج النص.",
        )
        self.authenticate(self.teacher_a)
        with patch(
            "apps.assessments.services.ocr.extract_text", return_value="works now"
        ):
            response = self.client.post(
                self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
            )

        self.assertEqual(response.data["status"], "completed")
        self.assertEqual(response.data["extracted_text"], "works now")
        self.assertEqual(
            AttachmentOcrResult.objects.filter(attachment=self.attachment_a).count(),
            1,
        )

    def test_png_attachment_uses_the_same_ocr_endpoint(self):
        png = self.attach(
            self.submission_a, "page.png", png_bytes(), "image/png"
        )
        self.authenticate(self.teacher_a)
        with patch("apps.assessments.services.ocr.extract_text", return_value="png text"):
            response = self.client.post(
                self.ocr_url(self.assessment_a, self.submission_a, png)
            )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["extracted_text"], "png text")

    def test_jpeg_attachment_uses_the_same_ocr_endpoint(self):
        self.authenticate(self.teacher_a)
        with patch("apps.assessments.services.ocr.extract_text", return_value="jpeg text"):
            response = self.client.post(
                self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
            )

        self.assertEqual(response.data["extracted_text"], "jpeg text")

    def test_attachment_from_another_submission_is_a_404_even_for_the_manager(self):
        self.authenticate(self.manager)
        with patch("apps.assessments.services.ocr.extract_text") as extractor:
            response = self.client.post(
                self.ocr_url(self.assessment_a, self.submission_a, self.attachment_b)
            )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        extractor.assert_not_called()

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get(
            self.ocr_url(self.assessment_a, self.submission_a, self.attachment_a)
        )

        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )


@override_settings(MEDIA_ROOT=OCR_MEDIA_ROOT)
class TesseractExtractorTests(TestCase):
    """Engine routing: images go to Tesseract, text PDFs skip it, scans don't."""

    def setUp(self):
        user_model = get_user_model()
        teacher = UserProfile.objects.create(
            user=user_model.objects.create_user(
                username="ocr-engine", password="strong-pass-123"
            ),
            role=UserProfile.Role.TEACHER,
        )
        classroom = make_classroom(teacher, "سادس أ")
        assessment = Assessment.objects.create(classroom=classroom, title="اختبار")
        self.submission = Submission.objects.create(
            assessment=assessment,
            student=Student.objects.create(classroom=classroom, internal_code="S-1"),
        )
        self.extractor = TesseractExtractor()

    def _attachment(self, filename, content, content_type):
        return SubmissionAttachment.objects.create(
            submission=self.submission,
            file=SimpleUploadedFile(filename, content),
            original_filename=filename,
            content_type=content_type,
            file_size=len(content),
        )

    def test_jpeg_path_sends_the_image_to_tesseract(self):
        attachment = self._attachment("page.jpg", tiny_image("JPEG"), "image/jpeg")
        with patch(
            "apps.assessments.services.ocr.pytesseract.image_to_string",
            return_value=" from jpeg ",
        ) as ocr:
            text = self.extractor.extract(attachment)

        self.assertEqual(text, "from jpeg")
        ocr.assert_called_once()
        self.assertEqual(ocr.call_args.kwargs["lang"], "ara+eng")

    def test_png_path_sends_the_image_to_tesseract(self):
        attachment = self._attachment("page.png", tiny_image("PNG"), "image/png")
        with patch(
            "apps.assessments.services.ocr.pytesseract.image_to_string",
            return_value="from png",
        ) as ocr:
            text = self.extractor.extract(attachment)

        self.assertEqual(text, "from png")
        ocr.assert_called_once()

    def test_pdf_with_a_text_layer_skips_tesseract(self):
        payload = text_layer_pdf("The student wrote three quarters here as the answer")
        attachment = self._attachment("paper.pdf", payload, "application/pdf")
        with patch(
            "apps.assessments.services.ocr.pytesseract.image_to_string"
        ) as ocr, patch(
            "apps.assessments.services.ocr.convert_from_bytes"
        ) as raster:
            text = self.extractor.extract(attachment)

        ocr.assert_not_called()
        raster.assert_not_called()
        self.assertIn("three quarters", text)

    def test_scanned_pdf_falls_back_to_ocr_on_rasterized_pages(self):
        attachment = self._attachment("scan.pdf", blank_pdf(), "application/pdf")
        fake_page = Image.new("RGB", (20, 20), "white")
        with patch(
            "apps.assessments.services.ocr.convert_from_bytes",
            return_value=[fake_page],
        ) as raster, patch(
            "apps.assessments.services.ocr.pytesseract.image_to_string",
            return_value="from a scan",
        ) as ocr:
            text = self.extractor.extract(attachment)

        raster.assert_called_once()
        ocr.assert_called_once()
        self.assertEqual(text, "from a scan")

    def test_sparse_pdf_text_is_not_treated_as_a_text_layer(self):
        self.assertFalse(_has_useful_text("1\n2\n"))
        self.assertTrue(
            _has_useful_text("The student wrote three quarters here as the answer")
        )

    def test_installed_tesseract_reads_printed_latin(self):
        """Sanity check that the Docker Tesseract actually runs. Quality of
        Arabic handwriting is out of scope; a high-contrast printed word is
        enough to prove the engine is wired up."""
        image = Image.new("RGB", (400, 120), "white")
        from PIL import ImageDraw

        ImageDraw.Draw(image).text((20, 30), "HELLO", fill="black")
        buffer = BytesIO()
        image.save(buffer, format="PNG")
        attachment = self._attachment("hello.png", buffer.getvalue(), "image/png")

        text = self.extractor.extract(attachment)

        self.assertIn("HELLO", text.upper().replace(" ", ""))


SAMPLE_STUDENT_PDF = (
    Path(__file__).resolve().parent / "fixtures" / "bayyin_sample_student_paper.pdf"
)


@override_settings(MEDIA_ROOT=OCR_MEDIA_ROOT)
class SampleStudentPaperOcrTests(TestCase):
    def test_rtl_pdf_uses_pypdf_layout_not_tesseract(self):
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
        self.assertIn("س:1", text)
        self.assertIn("الإجابة:", text)
        self.assertIn("18 سم", text)
        self.assertIn("لأننا ضربنا 1 في 2", text)
