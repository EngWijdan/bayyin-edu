import shutil
import tempfile
from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.signals import request_finished
from django.db import IntegrityError, close_old_connections, transaction
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import UserProfile
from apps.classrooms.models import Classroom, Student

from .models import (
    Assessment,
    Question,
    Submission,
    SubmissionAnswer,
    SubmissionAttachment,
)


def make_classroom(teacher, name, subject="الرياضيات"):
    return Classroom.objects.create(
        teacher=teacher,
        name=name,
        grade="الصف السادس",
        subject=subject,
        academic_year="1448",
    )


class AssessmentModelTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.teacher = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-one", password="test-only-password"),
            role=UserProfile.Role.TEACHER,
        )
        self.assessment = Assessment.objects.create(
            classroom=make_classroom(self.teacher, "سادس أ"),
            title="اختبار الكسور الأول",
            created_by=self.teacher,
        )

    def make_question(self, order, text="ما ناتج 1/2 + 1/4؟"):
        return Question.objects.create(
            assessment=self.assessment,
            order=order,
            text=text,
            max_score=Decimal("2"),
            model_answer="3/4",
        )

    def test_question_order_is_unique_inside_the_same_assessment(self):
        self.make_question(order=1)

        with self.assertRaises(IntegrityError), transaction.atomic():
            self.make_question(order=1, text="سؤال آخر")

    def test_same_order_is_allowed_in_a_different_assessment(self):
        self.make_question(order=1)
        other = Assessment.objects.create(
            classroom=self.assessment.classroom, title="اختبار ثانٍ"
        )

        Question.objects.create(
            assessment=other, order=1, text="سؤال", max_score=Decimal("1"), model_answer="نعم"
        )

        self.assertEqual(other.questions.count(), 1)

    def test_database_rejects_a_non_positive_max_score(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            Question.objects.create(
                assessment=self.assessment,
                order=1,
                text="سؤال",
                max_score=Decimal("0"),
                model_answer="لا شيء",
            )

    def test_next_order_follows_the_highest_existing_question(self):
        self.assertEqual(self.assessment.next_question_order(), 1)
        self.make_question(order=1)
        self.make_question(order=4, text="سؤال رابع")

        self.assertEqual(self.assessment.next_question_order(), 5)

    def test_questions_are_returned_in_order(self):
        self.make_question(order=3, text="ثالث")
        self.make_question(order=1, text="أول")
        self.make_question(order=2, text="ثانٍ")

        self.assertEqual(
            [question.text for question in self.assessment.questions.all()],
            ["أول", "ثانٍ", "ثالث"],
        )

    def test_active_queryset_hides_archived_assessments(self):
        archived = Assessment.objects.create(
            classroom=self.assessment.classroom,
            title="اختبار مؤرشف",
            created_by=self.teacher,
            archived_at=timezone.now(),
        )

        self.assertEqual(list(Assessment.objects.active()), [self.assessment])
        self.assertEqual(list(Assessment.objects.archived()), [archived])


class AssessmentApiTests(APITestCase):
    """Every teacher stays inside their own classrooms; the manager sees everything."""

    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(username="manager", password="strong-pass-123"),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-a", password="strong-pass-123"),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-b", password="strong-pass-123"),
            role=UserProfile.Role.TEACHER,
        )
        self.class_6a = make_classroom(self.teacher_a, "سادس أ")
        self.class_5a = make_classroom(self.teacher_b, "خامس أ", subject="العلوم")
        self.assessment_a = Assessment.objects.create(
            classroom=self.class_6a, title="اختبار الكسور الأول", created_by=self.teacher_a
        )
        self.assessment_b = Assessment.objects.create(
            classroom=self.class_5a, title="اختبار الخلية", created_by=self.teacher_b
        )

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def questions_url(self, assessment):
        return f"/api/v1/assessments/{assessment.id}/questions/"

    def question_payload(self, **overrides):
        return {
            "text": "ما ناتج 1/2 + 1/4؟",
            "max_score": 2,
            "model_answer": "3/4",
            **overrides,
        }

    # ---------------------------------------------------------------- create

    def test_teacher_creates_an_assessment_for_their_own_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            "/api/v1/assessments/",
            {"title": "اختبار الكسور الثاني", "classroom_id": str(self.class_6a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        created = Assessment.objects.get(title="اختبار الكسور الثاني")
        self.assertEqual(created.classroom, self.class_6a)
        self.assertEqual(created.created_by, self.teacher_a)
        self.assertEqual(response.data["classroom_name"], "سادس أ")
        self.assertEqual(response.data["subject"], "الرياضيات")

    def test_teacher_cannot_create_an_assessment_for_another_teachers_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            "/api/v1/assessments/",
            {"title": "اختبار مسروق", "classroom_id": str(self.class_5a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("classroom_id", response.data)
        self.assertFalse(Assessment.objects.filter(title="اختبار مسروق").exists())

    def test_manager_creates_an_assessment_for_any_classroom(self):
        self.authenticate(self.manager)
        response = self.client.post(
            "/api/v1/assessments/",
            {"title": "اختبار إداري", "classroom_id": str(self.class_5a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Assessment.objects.get(title="اختبار إداري").classroom, self.class_5a)

    def test_assessment_title_is_required(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            "/api/v1/assessments/",
            {"title": "", "classroom_id": str(self.class_6a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    # ------------------------------------------------------------------ list

    def test_teacher_sees_only_assessments_of_their_own_classrooms(self):
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/assessments/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual({item["title"] for item in response.data}, {"اختبار الكسور الأول"})

    def test_manager_sees_all_assessments(self):
        self.authenticate(self.manager)
        response = self.client.get("/api/v1/assessments/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            {item["title"] for item in response.data},
            {"اختبار الكسور الأول", "اختبار الخلية"},
        )

    def test_list_reports_question_count_and_total_score(self):
        Question.objects.create(
            assessment=self.assessment_a,
            order=1,
            text="سؤال أول",
            max_score=Decimal("2.5"),
            model_answer="3/4",
        )
        Question.objects.create(
            assessment=self.assessment_a,
            order=2,
            text="سؤال ثانٍ",
            max_score=Decimal("1.5"),
            model_answer="1/2",
        )
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/assessments/")

        self.assertEqual(response.data[0]["questions_count"], 2)
        self.assertEqual(Decimal(str(response.data[0]["total_score"])), Decimal("4"))
        self.assertFalse(response.data[0]["archived"])
        self.assertIsNone(response.data[0]["archived_at"])

    def test_default_list_hides_archived_assessments(self):
        self.assessment_a.archived_at = timezone.now()
        self.assessment_a.save(update_fields=["archived_at"])
        self.authenticate(self.teacher_a)

        active = self.client.get("/api/v1/assessments/")
        archived = self.client.get("/api/v1/assessments/?status=archived")
        everything = self.client.get("/api/v1/assessments/?status=all")

        self.assertEqual(active.data, [])
        self.assertEqual({item["title"] for item in archived.data}, {"اختبار الكسور الأول"})
        self.assertTrue(archived.data[0]["archived"])
        self.assertIsNotNone(archived.data[0]["archived_at"])
        self.assertEqual({item["title"] for item in everything.data}, {"اختبار الكسور الأول"})

    def test_invalid_list_status_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/assessments/?status=trash")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("status", response.data)

    def test_teacher_archives_and_restores_their_own_assessment(self):
        self.authenticate(self.teacher_a)
        archived = self.client.patch(
            f"/api/v1/assessments/{self.assessment_a.id}/",
            {"archived": True},
            format="json",
        )

        self.assertEqual(archived.status_code, status.HTTP_200_OK)
        self.assertTrue(archived.data["archived"])
        self.assessment_a.refresh_from_db()
        self.assertIsNotNone(self.assessment_a.archived_at)

        restored = self.client.patch(
            f"/api/v1/assessments/{self.assessment_a.id}/",
            {"archived": False},
            format="json",
        )

        self.assertEqual(restored.status_code, status.HTTP_200_OK)
        self.assertFalse(restored.data["archived"])
        self.assessment_a.refresh_from_db()
        self.assertIsNone(self.assessment_a.archived_at)

    def test_teacher_deletes_their_own_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.delete(f"/api/v1/assessments/{self.assessment_a.id}/")

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Assessment.objects.filter(id=self.assessment_a.id).exists())

    def test_teacher_cannot_archive_or_delete_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        archived = self.client.patch(
            f"/api/v1/assessments/{self.assessment_b.id}/",
            {"archived": True},
            format="json",
        )
        removed = self.client.delete(f"/api/v1/assessments/{self.assessment_b.id}/")

        self.assertEqual(archived.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(removed.status_code, status.HTTP_404_NOT_FOUND)
        self.assessment_b.refresh_from_db()
        self.assertIsNone(self.assessment_b.archived_at)
        self.assertTrue(Assessment.objects.filter(id=self.assessment_b.id).exists())

    # --------------------------------------------------------------- retrieve

    def test_teacher_retrieves_their_own_assessment_with_questions(self):
        Question.objects.create(
            assessment=self.assessment_a,
            order=1,
            text="ما ناتج 1/2 + 1/4؟",
            max_score=Decimal("2"),
            model_answer="3/4",
        )
        self.authenticate(self.teacher_a)
        response = self.client.get(f"/api/v1/assessments/{self.assessment_a.id}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data["questions"]), 1)
        self.assertEqual(response.data["questions"][0]["text"], "ما ناتج 1/2 + 1/4؟")
        self.assertEqual(response.data["questions"][0]["model_answer"], "3/4")

    def test_teacher_cannot_retrieve_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(f"/api/v1/assessments/{self.assessment_b.id}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotContains(response, "اختبار الخلية", status_code=status.HTTP_404_NOT_FOUND)

    def test_teacher_updates_the_title_of_their_own_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.patch(
            f"/api/v1/assessments/{self.assessment_a.id}/",
            {"title": "اختبار الكسور المعدل"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assessment_a.refresh_from_db()
        self.assertEqual(self.assessment_a.title, "اختبار الكسور المعدل")

    def test_teacher_cannot_update_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.patch(
            f"/api/v1/assessments/{self.assessment_b.id}/",
            {"title": "عنوان مفروض"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assessment_b.refresh_from_db()
        self.assertEqual(self.assessment_b.title, "اختبار الخلية")

    # --------------------------------------------------------------- questions

    def test_teacher_adds_a_question_to_their_own_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.questions_url(self.assessment_a), self.question_payload(), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        question = self.assessment_a.questions.get()
        self.assertEqual(question.text, "ما ناتج 1/2 + 1/4؟")
        self.assertEqual(question.max_score, Decimal("2"))
        self.assertEqual(question.model_answer, "3/4")

    def test_question_order_defaults_to_the_end_of_the_assessment(self):
        self.authenticate(self.teacher_a)
        for _ in range(3):
            self.client.post(
                self.questions_url(self.assessment_a), self.question_payload(), format="json"
            )

        self.assertEqual(
            list(self.assessment_a.questions.values_list("order", flat=True)), [1, 2, 3]
        )

    def test_teacher_cannot_add_a_question_to_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.questions_url(self.assessment_b), self.question_payload(), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(self.assessment_b.questions.exists())

    def test_teacher_cannot_read_questions_of_another_teachers_assessment(self):
        Question.objects.create(
            assessment=self.assessment_b,
            order=1,
            text="ما وظيفة النواة؟",
            max_score=Decimal("3"),
            model_answer="تنظيم نشاط الخلية",
        )
        self.authenticate(self.teacher_a)
        response = self.client.get(self.questions_url(self.assessment_b))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotContains(response, "النواة", status_code=status.HTTP_404_NOT_FOUND)

    def test_zero_max_score_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.questions_url(self.assessment_a),
            self.question_payload(max_score=0),
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("max_score", response.data)
        self.assertFalse(self.assessment_a.questions.exists())

    def test_negative_max_score_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.questions_url(self.assessment_a),
            self.question_payload(max_score=-1),
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.assessment_a.questions.exists())

    def test_duplicate_question_order_is_rejected(self):
        self.authenticate(self.teacher_a)
        first = self.client.post(
            self.questions_url(self.assessment_a),
            self.question_payload(order=1),
            format="json",
        )
        duplicate = self.client.post(
            self.questions_url(self.assessment_a),
            self.question_payload(order=1, text="سؤال مكرر الترتيب"),
            format="json",
        )

        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(duplicate.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("order", duplicate.data)
        self.assertEqual(self.assessment_a.questions.count(), 1)

    def test_teacher_edits_and_deletes_a_question_of_their_own_assessment(self):
        self.authenticate(self.teacher_a)
        created = self.client.post(
            self.questions_url(self.assessment_a), self.question_payload(), format="json"
        )
        question_id = created.data["id"]
        detail_url = f"{self.questions_url(self.assessment_a)}{question_id}/"

        edited = self.client.patch(detail_url, {"max_score": 5}, format="json")
        self.assertEqual(edited.status_code, status.HTTP_200_OK)
        self.assertEqual(self.assessment_a.questions.get().max_score, Decimal("5"))

        removed = self.client.delete(detail_url)
        self.assertEqual(removed.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(self.assessment_a.questions.exists())

    def test_teacher_cannot_delete_a_question_of_another_teachers_assessment(self):
        question = Question.objects.create(
            assessment=self.assessment_b,
            order=1,
            text="ما وظيفة النواة؟",
            max_score=Decimal("3"),
            model_answer="تنظيم نشاط الخلية",
        )
        self.authenticate(self.teacher_a)
        response = self.client.delete(
            f"{self.questions_url(self.assessment_b)}{question.id}/"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertTrue(Question.objects.filter(id=question.id).exists())

    # -------------------------------------------------------------- accounts

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/assessments/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get("/api/v1/assessments/")

        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )


class SubmissionModelTests(TestCase):
    """The API validates these too, but the model guards the admin and the ORM."""

    def setUp(self):
        user_model = get_user_model()
        self.teacher = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-one", password="test-only-password"),
            role=UserProfile.Role.TEACHER,
        )
        self.class_6a = make_classroom(self.teacher, "سادس أ")
        self.class_6b = make_classroom(self.teacher, "سادس ب")
        self.assessment = Assessment.objects.create(
            classroom=self.class_6a, title="اختبار الكسور الأول"
        )
        self.question = Question.objects.create(
            assessment=self.assessment,
            order=1,
            text="ما ناتج 1/2 + 1/4؟",
            max_score=Decimal("2"),
            model_answer="3/4",
        )
        self.student_6a = Student.objects.create(
            classroom=self.class_6a, internal_code="S-001", display_name="طالب أ"
        )
        self.student_6b = Student.objects.create(
            classroom=self.class_6b, internal_code="S-900"
        )

    def test_one_submission_per_student_and_assessment(self):
        Submission.objects.create(assessment=self.assessment, student=self.student_6a)

        with self.assertRaises(IntegrityError), transaction.atomic():
            Submission.objects.create(
                assessment=self.assessment, student=self.student_6a
            )

    def test_clean_rejects_a_student_from_another_classroom(self):
        submission = Submission(assessment=self.assessment, student=self.student_6b)

        with self.assertRaises(ValidationError):
            submission.full_clean()

    def test_clean_accepts_a_student_from_the_assessment_classroom(self):
        submission = Submission(assessment=self.assessment, student=self.student_6a)

        submission.full_clean()

    def test_one_answer_per_question_and_submission(self):
        submission = Submission.objects.create(
            assessment=self.assessment, student=self.student_6a
        )
        SubmissionAnswer.objects.create(
            submission=submission, question=self.question, answer_text="3/4"
        )

        with self.assertRaises(IntegrityError), transaction.atomic():
            SubmissionAnswer.objects.create(
                submission=submission, question=self.question, answer_text="1/2"
            )

    def test_clean_rejects_a_question_from_another_assessment(self):
        submission = Submission.objects.create(
            assessment=self.assessment, student=self.student_6a
        )
        foreign_question = Question.objects.create(
            assessment=Assessment.objects.create(
                classroom=self.class_6a, title="اختبار آخر"
            ),
            order=1,
            text="سؤال غريب",
            max_score=Decimal("1"),
            model_answer="لا",
        )

        with self.assertRaises(ValidationError):
            SubmissionAnswer(
                submission=submission, question=foreign_question, answer_text="س"
            ).full_clean()


class SubmissionApiTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(username="manager", password="strong-pass-123"),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-a", password="strong-pass-123"),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-b", password="strong-pass-123"),
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
        self.question_a1 = self.make_question(self.assessment_a, 1, "ما ناتج 1/2 + 1/4؟", "3/4")
        self.question_a2 = self.make_question(self.assessment_a, 2, "بسّط الكسر 4/8", "1/2")
        self.question_b1 = self.make_question(self.assessment_b, 1, "ما وظيفة النواة؟", "تنظيم")
        self.student_6a = Student.objects.create(
            classroom=self.class_6a, internal_code="S-001", display_name="طالب أ"
        )
        self.student_5a = Student.objects.create(
            classroom=self.class_5a, internal_code="S-900", display_name="طالب ب"
        )

    def make_question(self, assessment, order, text, model_answer):
        return Question.objects.create(
            assessment=assessment,
            order=order,
            text=text,
            max_score=Decimal("2"),
            model_answer=model_answer,
        )

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def submissions_url(self, assessment):
        return f"/api/v1/assessments/{assessment.id}/submissions/"

    def answers_url(self, assessment, submission):
        return f"{self.submissions_url(assessment)}{submission.id}/answers/"

    def make_submission(self, assessment, student):
        return Submission.objects.create(assessment=assessment, student=student)

    # ---------------------------------------------------------------- create

    def test_teacher_creates_a_submission_for_a_student_in_the_assessment_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.submissions_url(self.assessment_a),
            {"student_id": str(self.student_6a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        submission = Submission.objects.get()
        self.assertEqual(submission.student, self.student_6a)
        self.assertEqual(submission.assessment, self.assessment_a)
        self.assertEqual(submission.created_by, self.teacher_a)
        self.assertEqual(response.data["student_code"], "S-001")
        # Every question shows up so the entry screen renders in one round trip.
        self.assertEqual(len(response.data["answers"]), 2)
        self.assertEqual(response.data["answers"][0]["answer_text"], "")

    def test_created_by_ignores_anything_the_client_sends(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.submissions_url(self.assessment_a),
            {"student_id": str(self.student_6a.id), "created_by": str(self.teacher_b.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Submission.objects.get().created_by, self.teacher_a)

    def test_duplicate_submission_for_the_same_student_is_rejected(self):
        self.make_submission(self.assessment_a, self.student_6a)
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.submissions_url(self.assessment_a),
            {"student_id": str(self.student_6a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("student_id", response.data)
        self.assertEqual(Submission.objects.count(), 1)

    def test_student_from_another_classroom_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.submissions_url(self.assessment_a),
            {"student_id": str(self.student_5a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("student_id", response.data)
        self.assertFalse(Submission.objects.exists())

    def test_teacher_cannot_create_a_submission_on_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.submissions_url(self.assessment_b),
            {"student_id": str(self.student_5a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(Submission.objects.exists())

    # ------------------------------------------------------------------ read

    def test_teacher_lists_submissions_of_their_own_assessment_only(self):
        self.make_submission(self.assessment_a, self.student_6a)
        self.make_submission(self.assessment_b, self.student_5a)
        self.authenticate(self.teacher_a)
        response = self.client.get(self.submissions_url(self.assessment_a))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([item["student_code"] for item in response.data], ["S-001"])

    def test_teacher_cannot_list_submissions_of_another_teachers_assessment(self):
        self.make_submission(self.assessment_b, self.student_5a)
        self.authenticate(self.teacher_a)
        response = self.client.get(self.submissions_url(self.assessment_b))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotContains(response, "S-900", status_code=status.HTTP_404_NOT_FOUND)

    def test_teacher_cannot_retrieve_another_teachers_submission(self):
        submission = self.make_submission(self.assessment_b, self.student_5a)
        self.authenticate(self.teacher_a)
        response = self.client.get(
            f"{self.submissions_url(self.assessment_b)}{submission.id}/"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_a_submission_cannot_be_reached_through_a_different_assessment(self):
        submission = self.make_submission(self.assessment_b, self.student_5a)
        self.authenticate(self.teacher_a)
        response = self.client.get(
            f"{self.submissions_url(self.assessment_a)}{submission.id}/"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_detail_lists_every_question_in_order_with_current_answers(self):
        submission = self.make_submission(self.assessment_a, self.student_6a)
        SubmissionAnswer.objects.create(
            submission=submission, question=self.question_a2, answer_text="1/2"
        )
        self.authenticate(self.teacher_a)
        response = self.client.get(
            f"{self.submissions_url(self.assessment_a)}{submission.id}/"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["assessment_title"], "اختبار الكسور الأول")
        self.assertEqual(response.data["student_name"], "طالب أ")
        answers = response.data["answers"]
        self.assertEqual([entry["order"] for entry in answers], [1, 2])
        self.assertEqual(answers[0]["answer_text"], "")
        self.assertEqual(answers[1]["answer_text"], "1/2")

    # --------------------------------------------------------------- answers

    def test_teacher_saves_answers_for_their_own_submission(self):
        submission = self.make_submission(self.assessment_a, self.student_6a)
        self.authenticate(self.teacher_a)
        response = self.client.put(
            self.answers_url(self.assessment_a, submission),
            {
                "answers": [
                    {"question_id": str(self.question_a1.id), "answer_text": "3/4"},
                    {"question_id": str(self.question_a2.id), "answer_text": "1/2"},
                ]
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(submission.answers.count(), 2)
        self.assertEqual(
            submission.answers.get(question=self.question_a1).answer_text, "3/4"
        )
        self.assertEqual(
            [entry["answer_text"] for entry in response.data["answers"]], ["3/4", "1/2"]
        )

    def test_saving_again_updates_the_existing_answer_instead_of_duplicating(self):
        submission = self.make_submission(self.assessment_a, self.student_6a)
        self.authenticate(self.teacher_a)
        payload = {
            "answers": [{"question_id": str(self.question_a1.id), "answer_text": "3/4"}]
        }
        self.client.put(
            self.answers_url(self.assessment_a, submission), payload, format="json"
        )
        payload["answers"][0]["answer_text"] = "٣/٤ بعد التعديل"
        response = self.client.put(
            self.answers_url(self.assessment_a, submission), payload, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(submission.answers.count(), 1)
        self.assertEqual(submission.answers.get().answer_text, "٣/٤ بعد التعديل")

    def test_two_answers_for_the_same_question_in_one_payload_are_rejected(self):
        submission = self.make_submission(self.assessment_a, self.student_6a)
        self.authenticate(self.teacher_a)
        response = self.client.put(
            self.answers_url(self.assessment_a, submission),
            {
                "answers": [
                    {"question_id": str(self.question_a1.id), "answer_text": "3/4"},
                    {"question_id": str(self.question_a1.id), "answer_text": "1/2"},
                ]
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(submission.answers.exists())

    def test_question_from_another_assessment_is_rejected(self):
        submission = self.make_submission(self.assessment_a, self.student_6a)
        self.authenticate(self.teacher_a)
        response = self.client.put(
            self.answers_url(self.assessment_a, submission),
            {
                "answers": [
                    {"question_id": str(self.question_b1.id), "answer_text": "تنظيم"}
                ]
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(submission.answers.exists())

    def test_a_rejected_payload_saves_nothing_at_all(self):
        submission = self.make_submission(self.assessment_a, self.student_6a)
        self.authenticate(self.teacher_a)
        self.client.put(
            self.answers_url(self.assessment_a, submission),
            {
                "answers": [
                    {"question_id": str(self.question_a1.id), "answer_text": "3/4"},
                    {"question_id": str(self.question_b1.id), "answer_text": "تنظيم"},
                ]
            },
            format="json",
        )

        self.assertFalse(submission.answers.exists())

    def test_blank_answers_are_allowed(self):
        submission = self.make_submission(self.assessment_a, self.student_6a)
        self.authenticate(self.teacher_a)
        response = self.client.put(
            self.answers_url(self.assessment_a, submission),
            {"answers": [{"question_id": str(self.question_a1.id), "answer_text": ""}]},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(submission.answers.get().answer_text, "")

    def test_teacher_cannot_save_answers_on_another_teachers_submission(self):
        submission = self.make_submission(self.assessment_b, self.student_5a)
        self.authenticate(self.teacher_a)
        response = self.client.put(
            self.answers_url(self.assessment_b, submission),
            {
                "answers": [
                    {"question_id": str(self.question_b1.id), "answer_text": "تنظيم"}
                ]
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(submission.answers.exists())

    # --------------------------------------------------------------- manager

    def test_manager_reads_submissions_across_classrooms(self):
        self.make_submission(self.assessment_a, self.student_6a)
        self.make_submission(self.assessment_b, self.student_5a)
        self.authenticate(self.manager)

        for assessment, code in ((self.assessment_a, "S-001"), (self.assessment_b, "S-900")):
            response = self.client.get(self.submissions_url(assessment))
            self.assertEqual(response.status_code, status.HTTP_200_OK)
            self.assertEqual([item["student_code"] for item in response.data], [code])

    def test_manager_creates_a_submission_on_another_teachers_assessment(self):
        self.authenticate(self.manager)
        response = self.client.post(
            self.submissions_url(self.assessment_b),
            {"student_id": str(self.student_5a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Submission.objects.get().created_by, self.manager)

    # -------------------------------------------------------------- accounts

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get(self.submissions_url(self.assessment_a))

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get(self.submissions_url(self.assessment_a))

        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )


def jpeg_bytes(padding=32):
    return b"\xff\xd8\xff\xe0" + b"\x00" * padding + b"\xff\xd9"


def png_bytes(padding=32):
    return b"\x89PNG\r\n\x1a\n" + b"\x00" * padding


def pdf_bytes(padding=32):
    return b"%PDF-1.4\n" + b"0" * padding + b"%%EOF\n"


TEST_MEDIA_ROOT = tempfile.mkdtemp(prefix="bayyin-test-media-")


def read_streamed(response):
    """Draining a streaming response makes the test client fire
    request_finished, which would close the connection this test's transaction
    is running on, so hold that handler off until the body is read."""
    request_finished.disconnect(close_old_connections)
    try:
        return b"".join(response.streaming_content)
    finally:
        request_finished.connect(close_old_connections)


@override_settings(MEDIA_ROOT=TEST_MEDIA_ROOT)
class SubmissionAttachmentApiTests(APITestCase):
    """Uploading, listing and deleting the photo or PDF of a student's paper."""

    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        shutil.rmtree(TEST_MEDIA_ROOT, ignore_errors=True)

    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(username="manager", password="strong-pass-123"),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-a", password="strong-pass-123"),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-b", password="strong-pass-123"),
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

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def attachments_url(self, assessment, submission):
        return (
            f"/api/v1/assessments/{assessment.id}"
            f"/submissions/{submission.id}/attachments/"
        )

    def upload(self, assessment, submission, filename, content, declared="image/jpeg"):
        return self.client.post(
            self.attachments_url(assessment, submission),
            {"file": SimpleUploadedFile(filename, content, content_type=declared)},
            format="multipart",
        )

    def attach(self, submission, filename="paper.jpg"):
        """Creates an attachment straight through the ORM."""
        return SubmissionAttachment.objects.create(
            submission=submission,
            file=SimpleUploadedFile(filename, jpeg_bytes()),
            original_filename=filename,
            content_type="image/jpeg",
            file_size=len(jpeg_bytes()),
        )

    # ---------------------------------------------------------------- upload

    def test_teacher_uploads_a_jpeg_to_their_own_submission(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a, self.submission_a, "ورقة.jpg", jpeg_bytes()
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        attachment = self.submission_a.attachments.get()
        self.assertEqual(attachment.original_filename, "ورقة.jpg")
        self.assertEqual(attachment.content_type, "image/jpeg")
        self.assertEqual(attachment.file_size, len(jpeg_bytes()))
        self.assertEqual(attachment.created_by, self.teacher_a)
        self.assertTrue(Path(attachment.file.path).exists())

    def test_teacher_uploads_a_png(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a, self.submission_a, "page.png", png_bytes(), "image/png"
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(self.submission_a.attachments.get().content_type, "image/png")

    def test_teacher_uploads_a_pdf(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a,
            self.submission_a,
            "paper.pdf",
            pdf_bytes(),
            "application/pdf",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(
            self.submission_a.attachments.get().content_type, "application/pdf"
        )

    def test_the_stored_name_is_generated_not_the_client_filename(self):
        self.authenticate(self.teacher_a)
        self.upload(
            self.assessment_a, self.submission_a, "../../evil name.jpg", jpeg_bytes()
        )

        attachment = self.submission_a.attachments.get()
        stored = Path(attachment.file.name)
        self.assertNotIn("evil", stored.name)
        self.assertEqual(stored.suffix, ".jpg")
        self.assertEqual(stored.parent.name, str(self.submission_a.id))
        # The client's name survives for display only.
        self.assertEqual(attachment.original_filename, "evil name.jpg")

    # ------------------------------------------------------------ validation

    def test_unsupported_extension_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a, self.submission_a, "notes.txt", b"hello there"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.submission_a.attachments.exists())

    def test_a_supported_extension_over_the_wrong_bytes_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a, self.submission_a, "paper.png", pdf_bytes(), "image/png"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.submission_a.attachments.exists())

    def test_a_declared_content_type_alone_does_not_get_a_file_in(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a, self.submission_a, "script.sh", jpeg_bytes(), "image/jpeg"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.submission_a.attachments.exists())

    @override_settings(SUBMISSION_ATTACHMENT_MAX_BYTES=64)
    def test_oversized_file_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_a, self.submission_a, "big.jpg", jpeg_bytes(padding=512)
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.submission_a.attachments.exists())

    def test_the_configured_limit_is_ten_megabytes(self):
        self.assertEqual(settings.SUBMISSION_ATTACHMENT_MAX_BYTES, 10 * 1024 * 1024)

    # -------------------------------------------------------------- multiple

    def test_a_submission_accepts_several_files_in_upload_order(self):
        self.authenticate(self.teacher_a)
        for name, content in (
            ("page-1.jpg", jpeg_bytes()),
            ("page-2.png", png_bytes()),
            ("page-3.pdf", pdf_bytes()),
        ):
            created = self.upload(self.assessment_a, self.submission_a, name, content)
            self.assertEqual(created.status_code, status.HTTP_201_CREATED)

        response = self.client.get(
            self.attachments_url(self.assessment_a, self.submission_a)
        )

        self.assertEqual(
            [item["original_filename"] for item in response.data],
            ["page-1.jpg", "page-2.png", "page-3.pdf"],
        )

    # ------------------------------------------------------------------ read

    def test_teacher_lists_attachments_of_their_own_submission(self):
        self.attach(self.submission_a, "ورقة.jpg")
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.attachments_url(self.assessment_a, self.submission_a)
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["original_filename"], "ورقة.jpg")
        self.assertNotIn("file", response.data[0])

    def test_teacher_cannot_list_another_teachers_attachments(self):
        self.attach(self.submission_b, "secret.jpg")
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.attachments_url(self.assessment_b, self.submission_b)
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotContains(response, "secret", status_code=status.HTTP_404_NOT_FOUND)

    def test_teacher_cannot_upload_to_another_teachers_submission(self):
        self.authenticate(self.teacher_a)
        response = self.upload(
            self.assessment_b, self.submission_b, "paper.jpg", jpeg_bytes()
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(self.submission_b.attachments.exists())

    def test_teacher_downloads_their_own_attachment(self):
        attachment = self.attach(self.submission_a)
        self.authenticate(self.teacher_a)
        response = self.client.get(
            f"{self.attachments_url(self.assessment_a, self.submission_a)}"
            f"{attachment.id}/download/"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(read_streamed(response), jpeg_bytes())

    def test_teacher_cannot_download_another_teachers_attachment(self):
        attachment = self.attach(self.submission_b)
        self.authenticate(self.teacher_a)
        response = self.client.get(
            f"{self.attachments_url(self.assessment_b, self.submission_b)}"
            f"{attachment.id}/download/"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    # ---------------------------------------------------------------- delete

    def test_teacher_deletes_their_own_attachment_and_its_file(self):
        attachment = self.attach(self.submission_a)
        stored = Path(attachment.file.path)
        self.assertTrue(stored.exists())
        self.authenticate(self.teacher_a)
        response = self.client.delete(
            f"{self.attachments_url(self.assessment_a, self.submission_a)}"
            f"{attachment.id}/"
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(SubmissionAttachment.objects.filter(id=attachment.id).exists())
        self.assertFalse(stored.exists())

    def test_teacher_cannot_delete_another_teachers_attachment(self):
        attachment = self.attach(self.submission_b)
        self.authenticate(self.teacher_a)
        response = self.client.delete(
            f"{self.attachments_url(self.assessment_b, self.submission_b)}"
            f"{attachment.id}/"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertTrue(SubmissionAttachment.objects.filter(id=attachment.id).exists())

    def test_an_attachment_cannot_be_deleted_through_another_submissions_url(self):
        attachment = self.attach(self.submission_b)
        # The manager can reach both submissions, so only the id/URL mismatch
        # can be what rejects this.
        self.authenticate(self.manager)
        response = self.client.delete(
            f"{self.attachments_url(self.assessment_a, self.submission_a)}"
            f"{attachment.id}/"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertTrue(SubmissionAttachment.objects.filter(id=attachment.id).exists())

    def test_deleting_the_submission_removes_the_attachment_files_too(self):
        attachment = self.attach(self.submission_a)
        stored = Path(attachment.file.path)

        self.submission_a.delete()

        self.assertFalse(SubmissionAttachment.objects.exists())
        self.assertFalse(stored.exists())

    # --------------------------------------------------------------- manager

    def test_manager_reaches_attachments_across_classrooms(self):
        self.attach(self.submission_a, "6a.jpg")
        self.attach(self.submission_b, "5a.jpg")
        self.authenticate(self.manager)

        for assessment, submission, name in (
            (self.assessment_a, self.submission_a, "6a.jpg"),
            (self.assessment_b, self.submission_b, "5a.jpg"),
        ):
            response = self.client.get(self.attachments_url(assessment, submission))
            self.assertEqual(response.status_code, status.HTTP_200_OK)
            self.assertEqual(
                [item["original_filename"] for item in response.data], [name]
            )

    # -------------------------------------------------------------- accounts

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get(
            self.attachments_url(self.assessment_a, self.submission_a)
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get(
            self.attachments_url(self.assessment_a, self.submission_a)
        )

        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )
